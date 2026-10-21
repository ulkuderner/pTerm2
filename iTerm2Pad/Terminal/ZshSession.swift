import Darwin
import Foundation
import LocalShell
import SSHClient

extension Notification.Name {
    static let ptermSSHLaunch = Notification.Name("ptermSSHLaunch")
}

@_silgen_name("pterm_start_zsh")
private func pterm_start_zsh(_ fd: Int32, _ columns: Int32, _ rows: Int32) -> Int32

@_silgen_name("pterm_set_winsize")
private func pterm_set_winsize(_ fd: Int32, _ columns: Int32, _ rows: Int32)

/// Interactive login zsh on a pseudoterminal. The prompt and command line are
/// drawn by zsh itself, so the screen is a terminal rather than a text field.
/// `launchProgram` replaces zsh with an agent CLI on the same pty.
final class ZshSession {
    var onOutput: ((Data) -> Void)?
    var onExit: (() -> Void)?
    /// Absolute path of a program to run instead of an interactive zsh.
    var launchProgram: String?
    var missingNotice: String?
    private var master: Int32 = -1
    private var child: pid_t = -1
    private var reader: DispatchSourceRead?
    private var watch: DispatchSourceProcess?
    private var started = false
    private var exited = false
    /// Used when iPadOS refuses openpty. Commands run inside the app sandbox.
    private var builtin: ShellSession?
    private var line = ""
    private var history: [String] = []
    private var historyCursor = 0
    private var pendingEscape = ""
    private var writeFD: Int32 = -1
    private var translateNewlines = false
    private var lastWasReturn = false
    private var launchSource: DispatchSourceFileSystemObject?
    private var commandTimer: DispatchSourceTimer?
    private var launchFD: Int32 = -1

    static var accountHome: String {
        if let users = try? FileManager.default.contentsOfDirectory(atPath: "/Users") {
            for name in users where name != "Shared" && !name.hasPrefix(".") {
                let candidate = "/Users/\(name)/.oh-my-zsh/oh-my-zsh.sh"
                if FileManager.default.isReadableFile(atPath: candidate) {
                    return "/Users/\(name)"
                }
            }
        }
        return NSHomeDirectory()
    }

    func start(columns: UInt16 = 80, rows: UInt16 = 24) {
        guard !started else {
            return
        }
        started = true
        startBundledZsh(columns: columns, rows: rows)
    }

    func send(_ data: Data) {
        if builtin != nil {
            acceptBuiltin(data)
            return
        }
        let fd = writeFD >= 0 ? writeFD : master
        guard fd >= 0, !data.isEmpty else {
            return
        }
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else {
                return
            }
            _ = write(fd, base, data.count)
        }
    }

    func resize(columns: Int, rows: Int) {
        guard master >= 0 else {
            return
        }
        pterm_set_winsize(Int32(master), Int32(columns), Int32(rows))
        var size = winsize(ws_row: UInt16(rows), ws_col: UInt16(columns), ws_xpixel: 0, ws_ypixel: 0)
        ioctl(master, TIOCSWINSZ, &size)
    }

    func stop() {
        onExit = nil
        builtin = nil
        launchSource?.cancel()
        launchSource = nil
        commandTimer?.cancel()
        commandTimer = nil
        if writeFD >= 0, writeFD != master {
            close(writeFD)
        }
        writeFD = -1
        master = -1
        reader?.cancel()
        reader = nil
        watch?.cancel()
        watch = nil
        if child > 0 {
            kill(child, SIGTERM)
            child = -1
        }
    }

    private func readAvailable() {
        guard master >= 0 else {
            return
        }
        var buffer = [UInt8](repeating: 0, count: 4096)
        let count = read(master, &buffer, buffer.count)
        if count == 0 {
            DispatchQueue.main.async { [weak self] in
                self?.noteExit()
            }
            return
        }
        guard count > 0 else {
            return
        }
        var output = Data()
        if translateNewlines {
            for byte in buffer.prefix(count) {
                if byte == 10, !lastWasReturn {
                    output.append(13)
                }
                output.append(byte)
                lastWasReturn = byte == 13
            }
        } else {
            output = Data(buffer.prefix(count))
        }
        DispatchQueue.main.async { [weak self] in
            self?.onOutput?(output)
        }
    }

    /// iPad build. zsh and oh-my-zsh ship inside the app and talk over pipes.
    /// openpty is not used.
    private func startBundledZsh(columns: UInt16, rows: UInt16) {
        let home = prepareSandboxHome()
        setenv("HOME", home.path, 1)
        setenv("ZDOTDIR", home.path, 1)
        setenv("USER", "mobile", 1)
        setenv("LOGNAME", "mobile", 1)
        setenv("TERM", "xterm-256color", 1)
        setenv("COLORTERM", "truecolor", 1)
        setenv("LANG", "en_US.UTF-8", 1)
        setenv("COLUMNS", "\(columns)", 1)
        setenv("LINES", "\(rows)", 1)
        setenv("PTERM_ZSHRC", home.appendingPathComponent(".zshrc").path, 1)
        setenv("PATH", "/usr/bin:/bin:/usr/sbin:/sbin", 1)
        if let executable = Bundle.main.executableURL {
            setenv("PTERM_APP", executable.path, 1)
        }
        let launchDir = home.appendingPathComponent("Library/Caches/pterm-launch", isDirectory: true)
        let commandDir = home.appendingPathComponent("Library/Caches/pterm-cmd", isDirectory: true)
        try? FileManager.default.createDirectory(at: launchDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: commandDir, withIntermediateDirectories: true)
        setenv("PTERM_LAUNCH_DIR", launchDir.path, 1)
        setenv("PTERM_CMD_DIR", commandDir.path, 1)
        watchLaunches(at: launchDir)
        watchCommands(at: commandDir)
        if CommandLine.arguments.contains("-pterm-uitest") {
            setenv("PTERM_UTEST", "1", 1)
            try? Data("1".utf8).write(to: home.appendingPathComponent(".pterm-utest"))
        }

        var pair = [Int32](repeating: 0, count: 2)
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &pair) == 0 else {
            startBuiltin()
            return
        }
        var noSignal: Int32 = 1
        setsockopt(pair[0], SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        if let executable = Bundle.main.executableURL,
           spawnZsh(executable: executable, socket: pair[1], parent: pair[0], home: home, columns: columns, rows: rows) {
            close(pair[1])
            attach(pair[0])
            return
        }
        let result = pterm_start_zsh(pair[1], Int32(columns), Int32(rows))
        guard result == 0 else {
            close(pair[0])
            close(pair[1])
            emit("zsh: could not start in the sandbox (\(result))\r\n")
            startBuiltin()
            return
        }
        attach(pair[0])
    }

    private func spawnZsh(executable: URL, socket: Int32, parent: Int32, home: URL, columns: UInt16, rows: UInt16) -> Bool {
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        posix_spawn_file_actions_adddup2(&actions, socket, STDIN_FILENO)
        posix_spawn_file_actions_adddup2(&actions, socket, STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&actions, socket, STDERR_FILENO)
        posix_spawn_file_actions_addclose(&actions, parent)
        posix_spawn_file_actions_addclose(&actions, socket)
        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        defer {
            posix_spawn_file_actions_destroy(&actions)
            posix_spawnattr_destroy(&attr)
        }
        var environment = ProcessInfo.processInfo.environment
        environment["HOME"] = home.path
        environment["ZDOTDIR"] = home.path
        environment["PTERM_ZSHRC"] = home.appendingPathComponent(".zshrc").path
        environment["USER"] = "mobile"
        environment["LOGNAME"] = "mobile"
        environment["TERM"] = "xterm-256color"
        environment["COLUMNS"] = "\(columns)"
        environment["LINES"] = "\(rows)"
        environment["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
        environment["PTERM_APP"] = executable.path
        environment["PTERM_LAUNCH_DIR"] = home.appendingPathComponent("Library/Caches/pterm-launch").path
        environment["PTERM_CMD_DIR"] = home.appendingPathComponent("Library/Caches/pterm-cmd").path
        if CommandLine.arguments.contains("-pterm-strip-env") {
            environment["HOME"] = "/var/mobile"
            environment.removeValue(forKey: "ZDOTDIR")
            environment.removeValue(forKey: "PTERM_ZSHRC")
            environment.removeValue(forKey: "PTERM_CMD_DIR")
        }
        let arguments = [executable.path, "--pterm-zsh"]
        var argv: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) }
        argv.append(nil)
        var env: [UnsafeMutablePointer<CChar>?] = []
        for (key, value) in environment {
            env.append(strdup("\(key)=\(value)"))
        }
        env.append(nil)
        defer {
            argv.forEach { free($0) }
            env.forEach { free($0) }
        }
        var pid: pid_t = 0
        let result = argv.withUnsafeMutableBufferPointer { argvBuf in
            env.withUnsafeMutableBufferPointer { envBuf in
                posix_spawn(&pid, executable.path, &actions, &attr, argvBuf.baseAddress, envBuf.baseAddress)
            }
        }
        guard result == 0 else {
            return false
        }
        child = pid
        let process = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
        process.setEventHandler { [weak self] in
            self?.noteExit()
        }
        watch = process
        process.resume()
        return true
    }

    private func attach(_ fd: Int32) {
        master = fd
        writeFD = fd
        translateNewlines = true
        let owned = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: owned, queue: .global(qos: .userInteractive))
        source.setEventHandler { [weak self] in
            self?.readAvailable()
        }
        source.setCancelHandler {
            close(owned)
        }
        reader = source
        source.resume()
    }

    private func prepareSandboxHome() -> URL {
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let fileManager = FileManager.default
        let omz = home.appendingPathComponent(".oh-my-zsh", isDirectory: true)
        let marker = omz.appendingPathComponent("pterm2-omz-version")
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Shell/omz", isDirectory: true)
        let wanted = (try? String(contentsOf: bundled.appendingPathComponent("pterm2-omz-version"), encoding: .utf8)) ?? "3"
        let installed = (try? String(contentsOf: marker, encoding: .utf8)) ?? ""
        if installed != wanted,
           fileManager.fileExists(atPath: bundled.appendingPathComponent("oh-my-zsh.sh").path) {
            try? fileManager.removeItem(at: omz)
            try? fileManager.copyItem(at: bundled, to: omz)
        }
        try? fileManager.createDirectory(at: omz.appendingPathComponent("custom", isDirectory: true),
                                         withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: omz.appendingPathComponent("cache", isDirectory: true),
                                         withIntermediateDirectories: true)
        let prefix = home.appendingPathComponent("opt/homebrew", isDirectory: true)
        try? fileManager.createDirectory(at: prefix.appendingPathComponent("bin"), withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: prefix.appendingPathComponent("Cellar"), withIntermediateDirectories: true)
        let zshrc = home.appendingPathComponent(".zshrc")
        let stamp = home.appendingPathComponent(".pterm2-zshrc")
        if (try? String(contentsOf: stamp, encoding: .utf8)) != "22" {
            let bundledP10k = Bundle.main.bundleURL.appendingPathComponent("Shell/omz/p10k.zsh")
            let installedP10k = home.appendingPathComponent(".p10k.zsh")
            if fileManager.fileExists(atPath: bundledP10k.path) {
                try? fileManager.removeItem(at: installedP10k)
                try? fileManager.copyItem(at: bundledP10k, to: installedP10k)
            }
            let text = """
            unsetopt xtrace verbose
            setopt typeset_silent
            if [[ -n $ZDOTDIR ]]; then
              export HOME="$ZDOTDIR"
            fi
            export ZSH="$HOME/.oh-my-zsh"
            export ZSH_THEME="powerlevel10k/powerlevel10k"
            export DISABLE_AUTO_UPDATE=true
            export DISABLE_UPDATE_PROMPT=true
            export DISABLE_MAGIC_FUNCTIONS=true
            export ZSH_DISABLE_COMPFIX=true
            export GITSTATUS_AUTO_INSTALL=0
            fpath=("$ZSH/zsh-functions" "$ZSH/functions" $fpath)
            plugins=(git bgnotify sudo history dotenv)
            source "$ZSH/oh-my-zsh.sh"
            unsetopt xtrace
            [[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
            cd "$HOME"
            pterm_arm() {
              emulate -L zsh
              local dir=$PTERM_CMD_DIR
              if [[ -z $dir ]]; then
                print -ru2 -- "pterm: command directory missing"
                return 127
              fi
              local id="c${RANDOM}$SECONDS"
              print -r -- "$PWD" > "$dir/$id.pwd"
              print -l -- "$@" > "$dir/$id.ready"
              local spins=0
              while [[ ! -f $dir/$id.out && spins -lt 400 ]]; do
                read -t 0.05 || true
                (( spins++ ))
              done
              if [[ ! -f $dir/$id.out ]]; then
                print -ru2 -- "pterm: $1 timed out"
                return 127
              fi
              local text="$(<"$dir/$id.out")"
              [[ -z $text ]] || print -r -- "$text"
              local code=1
              [[ -f $dir/$id.code ]] && code=$(<"$dir/$id.code")
              return $code
            }
            for pterm_cmd in ls cat mkdir touch rm cp mv grep egrep fgrep head wc ssh mosh scp git sshfs umount python3 python pip3 pip brew; do
              unalias "$pterm_cmd" 2>/dev/null
              eval "$pterm_cmd() { pterm_arm $pterm_cmd \\"\\$@\\"; }"
            done
            unset pterm_cmd
            if [[ -n $PTERM_SELFTEST ]]; then
              print -r -- SELFTEST-LS
              ls
              print -r -- SELFTEST-BREW
              brew --prefix
              print -r -- SELFTEST-GIT
              git status
            fi
            """
            try? text.write(to: zshrc, atomically: true, encoding: .utf8)
            try? Data("22".utf8).write(to: stamp)
        }
        return home
    }

    private func watchLaunches(at directory: URL) {
        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else {
            return
        }
        launchFD = fd
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in
            self?.drainLaunches(at: directory)
        }
        source.setCancelHandler { [weak self] in
            if let fd = self?.launchFD, fd >= 0 {
                close(fd)
                self?.launchFD = -1
            }
        }
        launchSource = source
        source.resume()
    }

    private func watchCommands(at directory: URL) {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(40))
        timer.setEventHandler { [weak self] in
            self?.drainCommands(at: directory)
        }
        commandTimer = timer
        timer.resume()
    }

    private func drainCommands(at directory: URL) {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for ready in files where ready.pathExtension == "ready" {
            let id = ready.deletingPathExtension().lastPathComponent
            let pwdURL = directory.appendingPathComponent("\(id).pwd")
            let pwd = (try? String(contentsOf: pwdURL, encoding: .utf8)) ?? ""
            let raw = (try? String(contentsOf: ready, encoding: .utf8)) ?? ""
            var argv = raw.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            if argv.last?.isEmpty == true {
                argv.removeLast()
            }
            let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            let session = ShellSession(home: home)
            session.useDirectory(pwd)
            var text = ""
            session.output = { text += $0 }
            let code = argv.isEmpty ? 0 : session.run(arguments: argv)
            if SSHLaunchMailbox.pending != nil {
                NotificationCenter.default.post(name: .ptermSSHLaunch, object: nil)
            }
            let codeURL = directory.appendingPathComponent("\(id).code")
            let outURL = directory.appendingPathComponent("\(id).out")
            try? Data("\(code)\n".utf8).write(to: codeURL)
            try? Data(text.utf8).write(to: outURL)
            try? FileManager.default.removeItem(at: ready)
            try? FileManager.default.removeItem(at: pwdURL)
        }
    }

    private func drainLaunches(at directory: URL) {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "json" {
            defer { try? FileManager.default.removeItem(at: file) }
            guard let data = try? Data(contentsOf: file),
                  let host = try? JSONDecoder().decode(SSHHost.self, from: data) else {
                continue
            }
            SSHLaunchMailbox.stage(host)
            NotificationCenter.default.post(name: .ptermSSHLaunch, object: nil)
        }
    }

    private func noteExit() {
        guard !exited else {
            return
        }
        exited = true
        onExit?()
    }

    /// Line editor for the iPad sandbox. iPadOS returns EPERM from openpty and
    /// does not ship /bin/zsh, so the embedded command set runs in-process.
    private func startBuiltin() {
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let shell = ShellSession(home: home)
        shell.output = { [weak self] text in
            self?.writeTerminal(text)
        }
        builtin = shell
        writeTerminal(String(localized: "Pad.Shell.Sandbox",
                             defaultValue: "iPad sandbox shell. zsh cannot open a terminal here, so built-in commands are running. Type help.\r\n",
                             comment: "Banner when the iPad sandbox cannot start zsh."))
        if let launchProgram {
            writeTerminal("\(launchProgram) is not available in the iPad sandbox.\r\n")
        } else if let missingNotice {
            writeTerminal(missingNotice + "\r\n")
        }
        writeTerminal(shell.prompt())
    }

    private func acceptBuiltin(_ data: Data) {
        for byte in data {
            if !pendingEscape.isEmpty || byte == 0x1b {
                pendingEscape.append(Character(UnicodeScalar(byte)))
                if pendingEscape.count > 1, let last = pendingEscape.last, last.isLetter || last == "~" {
                    handleEscape(pendingEscape)
                    pendingEscape = ""
                }
                continue
            }
            switch byte {
            case 0x0d, 0x0a:
                writeTerminal("\r\n")
                let command = line
                if !command.isEmpty {
                    history.append(command)
                }
                historyCursor = history.count
                line = ""
                _ = builtin?.run(command)
                writeTerminal(builtin?.prompt() ?? "")
            case 0x7f, 0x08:
                guard !line.isEmpty else { continue }
                line.removeLast()
                writeTerminal("\u{8} \u{8}")
            case 0x03:
                line = ""
                writeTerminal("^C\r\n")
                writeTerminal(builtin?.prompt() ?? "")
            case 0x15:
                line = ""
                writeTerminal("\r\n")
                writeTerminal(builtin?.prompt() ?? "")
            case 32...126:
                let character = String(UnicodeScalar(byte))
                line.append(character)
                writeTerminal(character)
            default:
                break
            }
        }
    }

    private func handleEscape(_ sequence: String) {
        guard sequence == "\u{1b}[A" || sequence == "\u{1b}[B" else {
            return
        }
        if sequence == "\u{1b}[A" {
            guard historyCursor > 0 else { return }
            historyCursor -= 1
        } else if historyCursor < history.count {
            historyCursor += 1
        }
        replaceLine(historyCursor < history.count ? history[historyCursor] : "")
    }

    private func replaceLine(_ next: String) {
        if !line.isEmpty {
            writeTerminal(String(repeating: "\u{8}", count: line.count))
            writeTerminal(String(repeating: " ", count: line.count))
            writeTerminal(String(repeating: "\u{8}", count: line.count))
        }
        line = next
        writeTerminal(next)
    }

    private func writeTerminal(_ text: String) {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n", with: "\r\n")
        let data = Data(normalized.utf8)
        if Thread.isMainThread {
            onOutput?(data)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.onOutput?(data)
            }
        }
    }

    private func emit(_ text: String) {
        let data = Data(text.utf8)
        DispatchQueue.main.async { [weak self] in
            self?.onOutput?(data)
        }
    }

    /// Prefer the Mac account that already has oh-my-zsh, so a login zsh
    /// sources the same ~/.zshrc the user uses in Terminal.
    private static func environment() -> [String] {
        let home = accountHome
        let zshRoot = FileManager.default.isReadableFile(atPath: "\(home)/.oh-my-zsh/oh-my-zsh.sh")
            ? "\(home)/.oh-my-zsh"
            : ""
        let user = (home as NSString).lastPathComponent
        var values = [
            "HOME=\(home)",
            "USER=\(user)",
            "LOGNAME=\(user)",
            "SHELL=/bin/zsh",
            "TERM=xterm-256color",
            "COLORTERM=truecolor",
            "LANG=en_US.UTF-8",
            "LC_ALL=en_US.UTF-8",
            "PATH=\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        ]
        if !zshRoot.isEmpty {
            values.append("ZSH=\(zshRoot)")
        }
        return values
    }
}
