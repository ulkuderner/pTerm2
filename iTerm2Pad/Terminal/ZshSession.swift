import Darwin
import Foundation

/// Interactive login zsh on a pseudoterminal. The prompt and command line are
/// drawn by zsh itself, so the screen is a terminal rather than a text field.
final class ZshSession {
    var onOutput: ((Data) -> Void)?
    private var master: Int32 = -1
    private var child: pid_t = -1
    private var reader: DispatchSourceRead?

    func start(columns: UInt16 = 80, rows: UInt16 = 24) {
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
        let arguments = ["/bin/zsh", "-i", "-l"]
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
                posix_spawn(&pid, "/bin/zsh", &actions, &attr, argvBuf.baseAddress, envBuf.baseAddress)
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
        let source = DispatchSource.makeReadSource(fileDescriptor: masterFD, queue: .global(qos: .userInteractive))
        source.setEventHandler { [weak self] in
            self?.readAvailable()
        }
        source.setCancelHandler { [weak self] in
            if let fd = self?.master, fd >= 0 {
                close(fd)
                self?.master = -1
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
        reader?.cancel()
        reader = nil
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
        guard count > 0 else {
            return
        }
        let data = Data(buffer.prefix(count))
        DispatchQueue.main.async { [weak self] in
            self?.onOutput?(data)
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
        var home = NSHomeDirectory()
        var zshRoot = ""
        if let users = try? FileManager.default.contentsOfDirectory(atPath: "/Users") {
            for name in users where name != "Shared" && !name.hasPrefix(".") {
                let candidate = "/Users/\(name)/.oh-my-zsh/oh-my-zsh.sh"
                if FileManager.default.isReadableFile(atPath: candidate) {
                    home = "/Users/\(name)"
                    zshRoot = "/Users/\(name)/.oh-my-zsh"
                    break
                }
            }
        }
        let user = (home as NSString).lastPathComponent
        var values = [
            "HOME=\(home)",
            "USER=\(user)",
            "LOGNAME=\(user)",
            "SHELL=/bin/zsh",
            "TERM=xterm-256color",
            "LANG=en_US.UTF-8",
            "PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        ]
        if !zshRoot.isEmpty {
            values.append("ZSH=\(zshRoot)")
        }
        return values
    }
}
