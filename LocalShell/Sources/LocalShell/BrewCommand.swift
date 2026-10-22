import Foundation
import PadSystem

/// Sandbox prefix for packages this iPad can actually run.
/// Homebrew's macOS and Linux bottles are a different executable format.
struct BrewCommand: ShellCommand {
    let name = "brew"

    static let builtIn = [
        "ls", "cat", "mkdir", "touch", "rm", "cp", "mv", "grep", "head", "wc",
        "whoami", "uname", "date", "ssh", "scp", "git", "sshfs", "python3", "pip3", "claude"
    ]

    func run(arguments: [String], context: inout CommandContext) throws -> Int32 {
        let prefix = context.home.appendingPathComponent("Library/pterm/opt/homebrew")
        try FileManager.default.createDirectory(at: prefix.appendingPathComponent("bin"),
                                                withIntermediateDirectories: true)
        let verb = arguments.first ?? "help"
        switch verb {
        case "--prefix":
            context.stdout(prefix.path + "\n")
            return 0
        case "search":
            let query = arguments.dropFirst()
                .filter { !$0.hasPrefix("-") }
                .joined(separator: " ")
                .lowercased()
            let names = Self.builtIn.filter { query.isEmpty || $0.contains(query) }
            if names.isEmpty {
                context.stdout("No command matches \(query).\n")
            } else {
                context.stdout(names.joined(separator: "\n") + "\n")
            }
            return 0
        case "list", "help", "--help":
            context.stdout("ARM64 commands built into pTerm2:\n")
            context.stdout(Self.builtIn.joined(separator: "  ") + "\n")
            context.stdout("Prefix: \(prefix.path)\n")
            if pad_python3_ready() != 0 {
                context.stdout("brew install PACKAGE uses the embedded CPython for pure-Python packages.\n")
            } else {
                context.stdout("This list is the whole brew. Extra packages need CPython, which is not in this build.\n")
            }
            return 0
        case "install":
            let packages = arguments.dropFirst().filter { !$0.hasPrefix("-") }
            if packages.isEmpty {
                throw ShellError.usage("brew install PACKAGE")
            }
            var status: Int32 = 0
            for package in packages {
                if Self.builtIn.contains(package) {
                    context.stdout("\(package) is already built into this app as ARM64.\n")
                    continue
                }
                if pad_python3_ready() != 0 {
                    let code = try PipCommand().run(arguments: ["install", package], context: &context)
                    if code != 0 {
                        status = code
                    }
                    continue
                }
                context.stderr("brew: \(package) has no iPad ARM64 build in this app. macOS Homebrew bottles cannot run here.\n")
                status = 1
            }
            return status
        default:
            throw ShellError.usage("brew [--prefix|list|search|install PACKAGE]")
        }
    }
}
