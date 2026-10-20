import Darwin
import Foundation

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
        var masterFD: Int32 = -1
        var slaveFD: Int32 = -1
        var size = winsize(ws_row: rows, ws_col: columns, ws_xpixel: 0, ws_ypixel: 0)
        guard openpty(&masterFD, &slaveFD, nil, nil, &size) == 0 else {
            emit("zsh: openpty failed (\(errno))\r\n")
            return
        }
        master = masterFD

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        posix_spawn_file_actions_adddup2(&actions, slaveFD, STDIN_FILENO)
        posix_spawn_file_actions_adddup2(&actions, slaveFD, STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&actions, slaveFD, STDERR_FILENO)
        posix_spawn_file_actions_addclose(&actions, slaveFD)
        posix_spawn_file_actions_addclose(&actions, masterFD)

        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSID))

        let environment = Self.environment()
        let program: String
        let arguments: [String]
        if let launchProgram, FileManager.default.isExecutableFile(atPath: launchProgram) {
            let script = "cd '\(Self.accountHome)' && exec '\(launchProgram)'"
            program = "/bin/zsh"
            arguments = ["/bin/zsh", "-i", "-l", "-c", script]
        } else {
            if let missingNotice {
                emit(missingNotice + "\r\n")
            }
            program = "/bin/zsh"
            arguments = ["/bin/zsh", "-i", "-l"]
        }
        var argv: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) }
        argv.append(nil)
        var env: [UnsafeMutablePointer<CChar>?] = environment.map { strdup($0) }
        env.append(nil)
        defer {
            argv.forEach { free($0) }
            env.forEach { free($0) }
            posix_spawn_file_actions_destroy(&actions)
            posix_spawnattr_destroy(&attr)
        }

        var pid: pid_t = 0
        let result = argv.withUnsafeMutableBufferPointer { argvBuf in
            env.withUnsafeMutableBufferPointer { envBuf in
                posix_spawn(&pid, program, &actions, &attr, argvBuf.baseAddress, envBuf.baseAddress)
            }
        }
        close(slaveFD)
        guard result == 0 else {
            emit("zsh: could not start (\(result))\r\n")
            close(masterFD)
            master = -1
            return
        }
        child = pid
        let process = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
        process.setEventHandler { [weak self] in
            self?.noteExit()
        }
        watch = process
        process.resume()
        let source = DispatchSource.makeReadSource(fileDescriptor: masterFD, queue: .global(qos: .userInteractive))
        source.setEventHandler { [weak self] in
            self?.readAvailable()
        }
        source.setCancelHandler {
            if masterFD >= 0 {
                close(masterFD)
            }
        }
        reader = source
        source.resume()
    }

    func send(_ data: Data) {
        guard master >= 0, !data.isEmpty else {
            return
        }
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else {
                return
            }
            _ = write(master, base, data.count)
        }
    }

    func resize(columns: Int, rows: Int) {
        guard master >= 0 else {
            return
        }
        var size = winsize(ws_row: UInt16(rows), ws_col: UInt16(columns), ws_xpixel: 0, ws_ypixel: 0)
        ioctl(master, TIOCSWINSZ, &size)
    }

    func stop() {
        onExit = nil
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
        let data = Data(buffer.prefix(count))
        DispatchQueue.main.async { [weak self] in
            self?.onOutput?(data)
        }
    }

    private func noteExit() {
        guard !exited else {
            return
        }
        exited = true
        onExit?()
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
