import Darwin
import Foundation
import LocalShell

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
        let result = pterm_start_zsh(pair[1], Int32(columns), Int32(rows))
        guard result == 0 else {
            close(pair[0])
            close(pair[1])
            emit("zsh: could not start in the sandbox (\(result))\r\n")
            startBuiltin()
            return
        }
        master = pair[0]
        writeFD = pair[0]
        translateNewlines = true
        let owned = pair[0]
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
        let zshrc = home.appendingPathComponent(".zshrc")
        let stamp = home.appendingPathComponent(".pterm2-zshrc")
        if (try? String(contentsOf: stamp, encoding: .utf8)) != "11" {
            let text = """
            if [[ -n $ZDOTDIR ]]; then
              export HOME="$ZDOTDIR"
            fi
            export ZSH="$HOME/.oh-my-zsh"
            export ZSH_THEME="robbyrussell"
            export DISABLE_AUTO_UPDATE=true
            export DISABLE_UPDATE_PROMPT=true
            export DISABLE_MAGIC_FUNCTIONS=true
            export ZSH_DISABLE_COMPFIX=true
            fpath=("$ZSH/functions" $fpath)
            source "$ZSH/oh-my-zsh.sh"
            cd "$HOME"
            unalias ls 2>/dev/null
            ls() {
              emulate -L zsh
              setopt localoptions nullglob
              local show_all=0 long=0
              local -a targets
              local arg
              for arg in "$@"; do
                if [[ $arg == -* ]]; then
                  [[ $arg == *a* ]] && show_all=1
                  [[ $arg == *l* ]] && long=1
                else
                  targets+=("$arg")
                fi
              done
              (( ${#targets} )) || targets=(".")
              local target name kind
              for target in "${targets[@]}"; do
                if [[ ! -e $target ]]; then
                  print -r -- "ls: $target: No such file or directory"
                  continue
                fi
                if [[ -d $target ]]; then
                  local -a names
                  if (( show_all )); then
                    names=("$target"/.*(N) "$target"/*(N))
                  else
                    names=("$target"/*(N))
                  fi
                  for name in "${names[@]}"; do
                    kind="-"
                    [[ -d $name ]] && kind="d"
                    [[ -L $name ]] && kind="l"
                    if (( long )); then
                      print -r -- "$kind ${name:t}"
                    else
                      print -r -- "${name:t}"
                    fi
                  done
                else
                  print -r -- "$target"
                fi
              done
            }
            PROMPT='%F{green}➜%f %F{cyan}%~%f %# '
            """
            try? text.write(to: zshrc, atomically: true, encoding: .utf8)
            try? Data("11".utf8).write(to: stamp)
        }
        return home
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
