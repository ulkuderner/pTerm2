import Foundation
import LocalShell
import SSHClient
import SwiftUI

@main
enum PtermMain {
    static func main() {
        if CommandLine.arguments.contains("--pterm-exec") {
            exit(PtermExec.run())
        }
        if CommandLine.arguments.contains("--pterm-zsh") {
            exit(pterm_enter_zsh())
        }
        iTerm2PadApp.main()
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
