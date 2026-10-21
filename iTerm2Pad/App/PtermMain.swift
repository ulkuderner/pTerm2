import Foundation
import LocalShell
import SSHClient
import SwiftUI

/// Every pane shares this directory. iPadOS denies chroot(2), so the shell
/// treats it as `/` by refusing to leave it.
enum ShellRoot {
    /// The app container is the shell's root. iPadOS denies chroot(2),
    /// and a nested directory would hide Documents.
    static var root: URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }

    static var mobile: URL { root }

    /// Container root rejects new files on iPadOS. Startup files live here.
    static var profile: URL {
        root.appendingPathComponent("Library/pterm", isDirectory: true)
    }

    static func commandDirectory(id: String) -> URL {
        root.appendingPathComponent("Library/Caches/pterm-cmd/\(id)", isDirectory: true)
    }
}

@main
enum PtermMain {
    static func main() {
        if CommandLine.arguments.contains("--pterm-keychain-check") {
            let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            let ready = ClaudeKeychain.importFile(at: home) && ClaudeKeychain.load() != nil
            let message = ready ? "keychain-ok\n" : "keychain-missing \(ClaudeKeychain.lastStatus)\n"
            try? message.write(to: home.appendingPathComponent("pterm-keychain.txt"), atomically: true, encoding: .utf8)
            fputs(message, stdout)
            exit(ready ? 0 : 1)
        }
        if CommandLine.arguments.contains("--pterm-exec") {
            exit(PtermExec.run())
        }
        if CommandLine.arguments.contains("--pterm-zsh") {
            // A spawned copy of the app does not get the container as
            // NSHomeDirectory(); the parent passes the directory it prepared.
            let mobile = Self.argument(after: "--pterm-home") ?? ShellRoot.mobile.path
            let root = Self.argument(after: "--pterm-root") ?? mobile
            let jailed = root.withCString { pterm_try_chroot($0) }
            let home = jailed == 0 ? mobile : "/home/mobile"
            home.withCString { pterm_set_shell_home($0) }
            let startup = Self.argument(after: "--pterm-zshrc") ?? home + "/.zshrc"
            let rc = jailed == 0 ? startup : "/.zshrc"
            rc.withCString { pterm_set_zshrc($0) }
            setenv("ZDOTDIR", URL(fileURLWithPath: rc).deletingLastPathComponent().path, 1)
            if let command = Self.argument(after: "--pterm-cmd") {
                let directory = jailed == 0 ? command : "/Library/Caches/pterm-cmd/" + URL(fileURLWithPath: command).lastPathComponent
                setenv("PTERM_CMD_DIR", directory, 1)
            }
            setenv("PTERM_ROOT", jailed == 0 ? root : "/", 1)
            setenv("USER", "mobile", 1)
            setenv("LOGNAME", "mobile", 1)
            setenv("TERM", "xterm-256color", 1)
            setenv("LANG", "en_US.UTF-8", 1)
            if getenv("PTERM_APP") == nil, let executable = Bundle.main.executablePath {
                setenv("PTERM_APP", executable, 1)
            }
            exit(pterm_enter_zsh())
        }
        iTerm2PadApp.main()
    }

    private static func argument(after flag: String) -> String? {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: flag), index + 1 < args.count else {
            return nil
        }
        return args[index + 1]
    }
}

/// Runs one sandbox command inside the already-signed ARM64 app binary.
enum PtermExec {
    static func run() -> Int32 {
        let args = CommandLine.arguments
        guard let flag = args.firstIndex(of: "--pterm-exec"), flag + 1 < args.count else {
            fputs("usage: pterm --pterm-exec command [args]\n", stderr)
            return 2
        }
        let homePath = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
        let home = URL(fileURLWithPath: homePath, isDirectory: true)
        let session = ShellSession(home: home)
        session.output = { text in
            FileHandle.standardOutput.write(Data(text.utf8))
        }
        session.useCurrentDirectory()
        let status = session.run(arguments: Array(args[(flag + 1)...]))
        if let pending = SSHLaunchMailbox.pending {
            let directory = ProcessInfo.processInfo.environment["PTERM_LAUNCH_DIR"]
                .map { URL(fileURLWithPath: $0, isDirectory: true) }
                ?? home.appendingPathComponent("Library/Caches/pterm-launch", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if let data = try? JSONEncoder().encode(pending.host) {
                let url = directory.appendingPathComponent(UUID().uuidString + ".json")
                try? data.write(to: url)
            }
        }
        return status
    }
}

@_silgen_name("pterm_enter_zsh")
func pterm_enter_zsh() -> Int32

@_silgen_name("pterm_set_shell_home")
func pterm_set_shell_home(_ home: UnsafePointer<CChar>)

@_silgen_name("pterm_set_zshrc")
func pterm_set_zshrc(_ path: UnsafePointer<CChar>)

@_silgen_name("pterm_try_chroot")
func pterm_try_chroot(_ root: UnsafePointer<CChar>) -> Int32
