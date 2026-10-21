import Foundation
import PadSystem

public struct CommandContext {
    public var home: URL
    public var root: URL
    public var workingDirectory: URL
    public var environment: [String: String]
    public var stdout: (String) -> Void
    public var stderr: (String) -> Void

    public init(home: URL,
                workingDirectory: URL,
                environment: [String: String] = [:],
                stdout: @escaping (String) -> Void,
                stderr: @escaping (String) -> Void,
                root: URL? = nil) {
        self.home = home
        self.root = root ?? home
        self.workingDirectory = workingDirectory
        self.environment = environment
        self.stdout = stdout
        self.stderr = stderr
    }
}

public protocol ShellCommand {
    var name: String { get }
    var aliases: [String] { get }
    func run(arguments: [String], context: inout CommandContext) throws -> Int32
}

public extension ShellCommand {
    var aliases: [String] { [] }
}

public enum ShellError: Error, LocalizedError {
    case usage(String)
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .usage(let message), .failed(let message):
            return message
        }
    }
}

/// Blink / ios_system command dictionary plus the extra commands this app adds.
public final class CommandRegistry: @unchecked Sendable {
    public static let blinkCommands: [String] = [
        "awk", "bc", "cat", "chflags", "chksum", "compress", "cp", "curl",
        "date", "df", "diff", "du", "egrep", "env", "fgrep", "find", "grep",
        "groups", "gunzip", "gzip", "head", "host", "id", "less", "ln", "ls",
        "md5", "mkdir", "mv", "nc", "nslookup", "open", "pbcopy", "pbpaste",
        "ping", "ping6", "printenv", "pwd", "readlink", "rm", "rmdir", "sed",
        "sftp", "sort", "stat", "tail", "tar", "touch", "uname", "uncompress",
        "uniq", "uptime", "wc", "whoami", "xargs"
    ]

    private var commands: [String: ShellCommand] = [:]

    public init() {
        registerBuiltins()
    }

    public func register(_ command: ShellCommand) {
        commands[command.name] = command
        for alias in command.aliases {
            commands[alias] = command
        }
    }

    public func run(_ line: String, context: inout CommandContext) -> Int32 {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return 0
        }
        return run(arguments: tokenize(trimmed), context: &context)
    }

    /// Runs an already-split argv. The zsh child passes arguments this way so
    /// spaces survive the trip into the signed ARM binary.
    public func run(arguments: [String], context: inout CommandContext) -> Int32 {
        guard let name = arguments.first else {
            return 0
        }
        let tokens = arguments
        if name == "help" || name == "?" {
            listCommands(context: context)
            return 0
        }
        if pad_ios_system_ready() != 0, Self.blinkCommands.contains(name) {
            let line = arguments.joined(separator: " ")
            let rc = line.withCString { pad_ios_system($0) }
            if rc != -1 {
                return rc
            }
        }
        guard let command = commands[name] else {
            context.stderr(String(localized: "Shell.UnknownCommand",
                                  defaultValue: "command not found: \(name)\n",
                                  comment: "Local-shell error when a typed command is not registered. %1$@ is the command name."))
            return 127
        }
        do {
            return try command.run(arguments: Array(tokens.dropFirst()), context: &context)
        } catch {
            context.stderr((error.localizedDescription) + "\n")
            return 1
        }
    }

    public func initializeIOSSystem(home: URL) {
        home.path.withCString { pad_ios_system_initialize($0) }
    }

    public var registeredNames: [String] {
        Array(Set(commands.keys)).sorted()
    }

    private func listCommands(context: CommandContext) {
        let extras = ["git", "scp", "ssh", "sshfs", "umount", "python3", "pip3", "mosh", "brew", "claude"]
        let names = (Self.blinkCommands + extras + ["help"]).sorted()
        context.stdout(names.joined(separator: "  ") + "\n")
    }

    private func registerBuiltins() {
        register(PWDCommand())
        register(CDCommand())
        register(LSCommand())
        register(CatCommand())
        register(MkdirCommand())
        register(TouchCommand())
        register(RMCommand())
        register(CPCommand())
        register(MVCommand())
        register(EchoCommand())
        register(EnvCommand())
        register(WhoamiCommand())
        register(UnameCommand())
        register(DateCommand())
        register(GrepCommand())
        register(HeadCommand())
        register(WCCommand())
        register(SetenvCommand())
        register(SSHCommand())
        register(SCPCommand())
        register(GitCommand())
        register(SSHFSCommand())
        register(UmountCommand())
        register(PythonCommand())
        register(PipCommand())
        register(BrewCommand())
        register(ClaudeCommand())
    }

    private func tokenize(_ line: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var quote: Character?
        for ch in line {
            if let q = quote {
                if ch == q {
                    quote = nil
                } else {
                    current.append(ch)
                }
                continue
            }
            if ch == "\"" || ch == "'" {
                quote = ch
                continue
            }
            if ch.isWhitespace {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
                continue
            }
            current.append(ch)
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }
}
