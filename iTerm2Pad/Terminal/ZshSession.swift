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
    /// Held open for the life of the pane. zsh waits on one byte here instead of forking sleep.
    private var replyFD: Int32 = -1
    private var startupFault: String?
    private var spawnStatus: Int32 = -1

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
        let commandName = "cmd-\(UUID().uuidString)"
        let commandDir = ShellRoot.commandDirectory(id: commandName)
        setenv("HOME", home.path, 1)
        setenv("ZDOTDIR", home.path, 1)
        setenv("PTERM_ROOT", ShellRoot.root.path, 1)
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
        try? FileManager.default.createDirectory(at: launchDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: commandDir, withIntermediateDirectories: true)
        openReplyPipe(in: commandDir)
        setenv("PTERM_LAUNCH_DIR", launchDir.path, 1)
        setenv("PTERM_CMD_DIR", commandDir.path, 1)
        let startup = ShellRoot.profile.appendingPathComponent(".zshrc")
        home.path.withCString { pterm_set_shell_home($0) }
        startup.path.withCString { pterm_set_zshrc($0) }
        setenv("ZDOTDIR", ShellRoot.profile.path, 1)
        setenv("PTERM_ZSHRC", startup.path, 1)
        setenv("PTERM_CMD_DIR", commandDir.path, 1)
        setenv("PTERM_ROOT", ShellRoot.root.path, 1)
        if let startupFault {
            emit(startupFault)
        }
        watchLaunches(at: launchDir)
        watchCommands(at: commandDir)
        if CommandLine.arguments.contains("-pterm-uitest") {
            setenv("PTERM_UTEST", "1", 1)
            try? Data("1".utf8).write(to: home.appendingPathComponent(".pterm-utest"))
        }
        if CommandLine.arguments.contains("-pterm-selftest") {
            setenv("PTERM_SELFTEST", "1", 1)
        }

        var pair = [Int32](repeating: 0, count: 2)
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &pair) == 0 else {
            startBuiltin()
            return
        }
        var noSignal: Int32 = 1
        setsockopt(pair[0], SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        let forceInProcess = CommandLine.arguments.contains("-pterm-inprocess")
        if !forceInProcess,
           let executable = Bundle.main.executableURL,
           spawnZsh(executable: executable, socket: pair[1], parent: pair[0], home: home, commandDir: commandDir, columns: columns, rows: rows) {
            close(pair[1])
            attach(pair[0])
            return
        }
        let result = pterm_start_zsh(pair[1], Int32(columns), Int32(rows))
        if result == 0 {
            if spawnStatus >= 0 {
                emit("pterm: in-process shell (spawn \(spawnStatus))\r\n")
            } else {
                emit("pterm: in-process shell\r\n")
            }
            attach(pair[0])
            return
        }
        close(pair[0])
        close(pair[1])
        if result == EBUSY {
            missingNotice = String(localized: "Pad.Shell.OtherPane",
                                   defaultValue: "zsh is running in another pane. This pane uses the built-in shell.",
                                   comment: "Shown when a second pane cannot start another zsh.")
        } else {
            missingNotice = "zsh: could not start in the sandbox (\(result))"
        }
        startBuiltin()
    }

    private func spawnZsh(executable: URL, socket: Int32, parent: Int32, home: URL, commandDir: URL, columns: UInt16, rows: UInt16) -> Bool {
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
        var environment = [
            "HOME": home.path,
            "ZDOTDIR": ShellRoot.profile.path,
            "PTERM_ZSHRC": ShellRoot.profile.appendingPathComponent(".zshrc").path,
            "PTERM_ROOT": ShellRoot.root.path,
            "USER": "mobile",
            "LOGNAME": "mobile",
            "TERM": "xterm-256color",
            "LANG": "en_US.UTF-8",
            "COLUMNS": "\(columns)",
            "LINES": "\(rows)",
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "PTERM_APP": executable.path,
            "PTERM_LAUNCH_DIR": home.appendingPathComponent("Library/Caches/pterm-launch").path,
            "PTERM_CMD_DIR": commandDir.path
        ]
        if CommandLine.arguments.contains("-pterm-uitest") {
            environment["PTERM_UTEST"] = "1"
        }
        if CommandLine.arguments.contains("-pterm-selftest") {
            environment["PTERM_SELFTEST"] = "1"
        }
        let inherited = ProcessInfo.processInfo.environment
        if inherited["SIMULATOR_ROOT"] != nil || inherited["SIMULATOR_UDID"] != nil {
            for (key, value) in inherited where key.hasPrefix("DYLD_") || key.hasPrefix("SIMULATOR_") {
                environment[key] = value
            }
        }
        if CommandLine.arguments.contains("-pterm-strip-env") {
            environment["HOME"] = "/var/mobile"
            environment.removeValue(forKey: "ZDOTDIR")
            environment.removeValue(forKey: "PTERM_ZSHRC")
            environment.removeValue(forKey: "PTERM_CMD_DIR")
        }
        let arguments = [executable.path, "--pterm-zsh", "--pterm-home", home.path, "--pterm-root", ShellRoot.root.path, "--pterm-cmd", commandDir.path, "--pterm-zshrc", ShellRoot.profile.appendingPathComponent(".zshrc").path]
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
        spawnStatus = result
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
        let fileManager = FileManager.default
        let root = ShellRoot.root
        let home = ShellRoot.mobile
        try? fileManager.createDirectory(at: root.appendingPathComponent("tmp"), withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: root.appendingPathComponent("bin"), withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: home, withIntermediateDirectories: true)
        let profile = ShellRoot.profile
        do {
            try fileManager.createDirectory(at: profile, withIntermediateDirectories: true)
        } catch {
            startupFault = "pterm: shell directory \(profile.path) (\(error.localizedDescription))\r\n"
        }
        let omz = profile.appendingPathComponent(".oh-my-zsh", isDirectory: true)
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
        try? fileManager.createDirectory(at: home.appendingPathComponent("opt"), withIntermediateDirectories: true)
        let prefix = profile.appendingPathComponent("opt/homebrew", isDirectory: true)
        try? fileManager.createDirectory(at: prefix.appendingPathComponent("bin"), withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: prefix.appendingPathComponent("Cellar"), withIntermediateDirectories: true)
        let zshrc = profile.appendingPathComponent(".zshrc")
        let stamp = profile.appendingPathComponent(".pterm2-zshrc")
        if (try? String(contentsOf: stamp, encoding: .utf8)) != "41" {
            let bundledP10k = Bundle.main.bundleURL.appendingPathComponent("Shell/omz/p10k.zsh")
            let installedP10k = profile.appendingPathComponent(".p10k.zsh")
            if fileManager.fileExists(atPath: bundledP10k.path) {
                try? fileManager.removeItem(at: installedP10k)
                try? fileManager.copyItem(at: bundledP10k, to: installedP10k)
            }
            let text = """
            unsetopt xtrace verbose
            setopt typeset_silent
            bindkey -e
            bindkey '^?' backward-delete-char
            bindkey '^H' backward-delete-char
            PS1=$'%F{green}%~%f %# '
            pterm_keep_prompt() { [[ $PS1 == *'%m%#'* ]] && PS1=$'%F{green}%~%f %# ' }
            precmd_functions+=(pterm_keep_prompt)
            cd "$HOME"
            export ZSH="${ZDOTDIR:-$HOME}/.oh-my-zsh"
            export ZSH_THEME="powerlevel10k/powerlevel10k"
            export DISABLE_AUTO_UPDATE=true
            export DISABLE_UPDATE_PROMPT=true
            export DISABLE_MAGIC_FUNCTIONS=true
            export ZSH_DISABLE_COMPFIX=true
            export GITSTATUS_AUTO_INSTALL=0
            setopt extended_glob
            fpath=($ZSH/completions/Base/*(/N) $ZSH/completions/Zsh/*(/N) $ZSH/completions/Unix/Type(/N) $ZSH/completions $ZSH/functions $ZSH/zsh-functions $fpath)
            autoload -Uz compinit
            plugins=(git bgnotify sudo history dotenv)
            pterm_load_theme() {
              compinit -u -d "${ZDOTDIR:-$HOME}/.zcompdump" || true
              source "$ZSH/oh-my-zsh.sh" || true
              [[ ! -f ${ZDOTDIR:-$HOME}/.p10k.zsh ]] || source ${ZDOTDIR:-$HOME}/.p10k.zsh
            }
            pterm_load_theme
            unsetopt xtrace
            bindkey -e
            bindkey '^?' backward-delete-char
            bindkey '^H' backward-delete-char
            bindkey '^I' expand-or-complete
            zstyle ':completion:*' menu select
            if [[ -n $PTERM_ROOT ]]; then
              cd() {
                builtin cd "$@" || return
                case $PWD in
                  $PTERM_ROOT|$PTERM_ROOT/*) ;;
                  *) builtin cd -- "$PTERM_ROOT" ;;
                esac
              }
            fi
            if [[ -n $PTERM_UTEST ]]; then
              print -r -- "pterm-complete:$(bindkey '^I')"
            fi
            pterm_say() {
              if [[ -n $PTERM_FD ]] && zmodload zsh/system 2>/dev/null; then
                syswrite -o $PTERM_FD -- "$*"$'\n'
              elif [[ -n $PTERM_FD ]]; then
                print -u $PTERM_FD -r -- "$*"
              else
                print -ru2 -- "$*"
              fi
            }
            pterm_arm() {
              emulate -L zsh
              zmodload zsh/system 2>/dev/null || { pterm_say "pterm: zsh/system missing"; return 127 }
              local dir=$PTERM_CMD_DIR
              if [[ -z $dir ]]; then
                pterm_say "pterm: command directory missing"
                return 127
              fi
              local id="c${RANDOM}$SECONDS" fd arg text code chunk
              sysopen -w -o creat,trunc -u fd -- "$dir/$id.pwd" || { pterm_say "pterm: $1 could not queue"; return 127 }
              syswrite -o $fd -- "$PWD"$'\n'
              exec {fd}>&-
              sysopen -w -o creat,trunc -u fd -- "$dir/$id.args" || { pterm_say "pterm: $1 could not queue"; return 127 }
              for arg in "$@"; do
                syswrite -o $fd -- "$arg"$'\n'
              done
              exec {fd}>&-
              sysopen -r -u fd -- "$dir/reply" || { pterm_say "pterm: $1 has no reply pipe"; return 127 }
              sysread -i $fd -s 1 -t 0 chunk
              exec {fd}>&-
              sysopen -w -o creat,trunc -u fd -- "$dir/$id.ready" || { pterm_say "pterm: $1 could not queue"; return 127 }
              exec {fd}>&-
              sysopen -r -u fd -- "$dir/reply" || { pterm_say "pterm: $1 has no reply pipe"; return 127 }
              sysread -i $fd -s 1 -t 4 chunk
              exec {fd}>&-
              if [[ ! -f $dir/$id.out ]]; then
                pterm_say "pterm: $1 timed out"
                return 127
              fi
              sysopen -r -u fd -- "$dir/$id.out" || { pterm_say "pterm: $1 unreadable"; return 127 }
              sysread -i $fd text
              exec {fd}>&-
              [[ -z $text ]] || pterm_say "$text"
              code=1
              if [[ -f $dir/$id.code ]]; then
                sysopen -r -u fd -- "$dir/$id.code" || { pterm_say "pterm: $1 unreadable"; return 1 }
                sysread -i $fd code
                exec {fd}>&-
              fi
              return $code
            }
            for pterm_cmd in ls cat mkdir touch rm cp mv grep egrep fgrep head wc ssh mosh scp git sshfs umount python3 python pip3 pip brew; do
              unalias "$pterm_cmd" 2>/dev/null
              eval "$pterm_cmd() { pterm_arm $pterm_cmd \\"\\$@\\"; }"
            done
            unset pterm_cmd
            if [[ $PS1 == '%m%# ' ]]; then
              PS1=$'%F{green}%~%f %# '
            fi
            if [[ -n $PTERM_SELFTEST ]]; then
              print -r -- SELFTEST-LS
              ls
              print -r -- SELFTEST-BREW
              brew --prefix
              print -r -- SELFTEST-GIT
              git status
            fi
            """
            do {
                try text.write(to: zshrc, atomically: false, encoding: .utf8)
                try Data("41".utf8).write(to: stamp)
            } catch {
                startupFault = "pterm: shell startup \(zshrc.path) (\(error.localizedDescription))\r\n"
            }
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

    private func openReplyPipe(in directory: URL) {
        let reply = directory.appendingPathComponent("reply")
        if mkfifo(reply.path, 0o600) != 0 && errno != EEXIST {
            return
        }
        replyFD = open(reply.path, O_RDWR)
    }

    private func signalReply() {
        guard replyFD >= 0 else {
            return
        }
        var byte: UInt8 = 1
        _ = Darwin.write(replyFD, &byte, 1)
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
            let argsURL = directory.appendingPathComponent("\(id).args")
            let raw = (try? String(contentsOf: argsURL, encoding: .utf8)) ?? ""
            var argv = raw.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            if argv.last?.isEmpty == true {
                argv.removeLast()
            }
            let session = ShellSession(home: ShellRoot.mobile, root: ShellRoot.root)
            session.useDirectory(pwd)
            var text = ""
            session.output = { text += $0 }
            let code = argv.isEmpty ? 0 : session.run(arguments: argv)
            if SSHLaunchMailbox.pending != nil {
                NotificationCenter.default.post(name: .ptermSSHLaunch, object: nil)
            }
            let codeURL = directory.appendingPathComponent("\(id).code")
            let outURL = directory.appendingPathComponent("\(id).out")
            try? Data("\(code)\n".utf8).write(to: codeURL, options: .atomic)
            try? Data(text.utf8).write(to: outURL, options: .atomic)
            signalReply()
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
        let shell = ShellSession(home: ShellRoot.mobile, root: ShellRoot.root)
        shell.output = { [weak self] text in
            self?.writeTerminal(text)
        }
        builtin = shell
        if let missingNotice {
            writeTerminal(missingNotice + "\r\n")
        } else {
            writeTerminal(String(localized: "Pad.Shell.Sandbox",
                                 defaultValue: "iPad sandbox shell. zsh cannot open a terminal here, so built-in commands are running. Type help.\r\n",
                                 comment: "Banner when the iPad sandbox cannot start zsh."))
        }
        if let launchProgram {
            writeTerminal("\(launchProgram) is not available in the iPad sandbox.\r\n")
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
                let trimmed = command.trimmingCharacters(in: .whitespaces)
                if trimmed == "exit" || trimmed == "logout" {
                    onExit?()
                    return
                }
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
