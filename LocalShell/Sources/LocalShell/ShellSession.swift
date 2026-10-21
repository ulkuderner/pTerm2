import Foundation
import PadSystem

public final class ShellSession: @unchecked Sendable {
    public let registry = CommandRegistry()
    public private(set) var context: CommandContext
    public var output: ((String) -> Void)?
    private var claudeSession: ClaudeCodeSession?

    public var claudeActive: Bool { claudeSession != nil }

    public func beginClaude() -> String {
        guard let auth = ClaudeAuth.load(context: context) else {
            return String(localized: "Shell.Claude.MissingToken",
                          defaultValue: "claude needs the Claude login in the iPad keychain.\n",
                          comment: "Shown when the built-in claude command has no API or OAuth token")
        }
        claudeSession = ClaudeCodeSession(shell: self, auth: auth)
        return String(localized: "Shell.Claude.Banner",
                      defaultValue: "Claude Code\nAsk for a change in this sandbox. exit returns to the shell.\n",
                      comment: "Banner when a Claude Code session starts in the built-in shell")
    }

    public func claudeTurn(_ text: String, emit: (String) -> Void = { _ in }) -> String {
        claudeSession?.turn(text, emit: emit) ?? ""
    }

    public func endClaude() {
        claudeSession = nil
    }

    public init(home: URL, root: URL? = nil) {
        let documents = home
        let jail = root ?? home
        context = CommandContext(
            home: documents,
            workingDirectory: documents,
            environment: [
                "HOME": documents.path,
                "PATH": "/usr/bin:/bin:\(documents.appendingPathComponent("Library/bin").path)",
                "SHELL": "/bin/zsh",
                "TERM": "xterm-256color"
            ],
            stdout: { _ in },
            stderr: { _ in },
            root: jail
        )
        context.stdout = { [weak self] text in self?.output?(text) }
        context.stderr = { [weak self] text in self?.output?(text) }
        registry.initializeIOSSystem(home: documents)
        try? FileManager.default.createDirectory(at: documents.appendingPathComponent("Library/bin"),
                                                 withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: documents.appendingPathComponent("mnt"),
                                                 withIntermediateDirectories: true)
    }

    public func run(_ line: String) -> Int32 {
        registry.run(line, context: &context)
    }

    public func run(arguments: [String]) -> Int32 {
        registry.run(arguments: arguments, context: &context)
    }

    public func useCurrentDirectory() {
        useDirectory(FileManager.default.currentDirectoryPath)
    }

    public func useDirectory(_ path: String) {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let chosen = URL(fileURLWithPath: trimmed.isEmpty ? context.home.path : trimmed, isDirectory: true)
        context.workingDirectory = confine(chosen, to: context.root)
    }

    /// Completes the last token of a builtin command line. One match fills the
    /// token. Several matches extend the shared prefix, or list the names when
    /// the prefix is already complete.
    public func complete(line: String) -> (line: String, matches: [String]) {
        let (prefix, token) = splitLastToken(line)
        let commandPosition = prefix.trimmingCharacters(in: .whitespaces).isEmpty && !token.contains("/")
        let found = commandPosition ? commandMatches(token) : fileMatches(token)
        guard !found.isEmpty else {
            return (line, [])
        }
        if found.count == 1 {
            let chosen = found[0]
            let gap = chosen.hasSuffix("/") ? "" : " "
            return (prefix + chosen + gap, [])
        }
        let shared = commonPrefix(found)
        if shared.count > token.count {
            return (prefix + shared, [])
        }
        return (line, found)
    }

    private func splitLastToken(_ line: String) -> (String, String) {
        guard let space = line.lastIndex(where: { $0.isWhitespace }) else {
            return ("", line)
        }
        let next = line.index(after: space)
        return (String(line[..<next]), String(line[next...]))
    }

    private func commandMatches(_ token: String) -> [String] {
        Array(Set(registry.registeredNames + ["help", "exit"])).filter { $0.hasPrefix(token) }.sorted()
    }

    private func fileMatches(_ token: String) -> [String] {
        let relative = token.hasPrefix("~/") ? String(token.dropFirst(2)) : token
        let directory: URL
        let partial: String
        let stem: String
        if relative.isEmpty || relative.hasSuffix("/") {
            directory = resolve(token.isEmpty ? "." : token, relativeTo: context)
            partial = ""
            stem = token.hasSuffix("/") || token == "~" ? (token.hasSuffix("/") ? token : "~/") : relative
        } else {
            let parent = (relative as NSString).deletingLastPathComponent
            partial = (relative as NSString).lastPathComponent
            if parent.isEmpty || parent == "." {
                directory = context.workingDirectory
                stem = token.hasPrefix("~/") ? "~/" : ""
            } else {
                let parentToken = token.hasPrefix("~/") ? "~/" + parent : parent
                directory = resolve(parentToken, relativeTo: context)
                stem = parentToken + "/"
            }
        }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { name in
            name.hasPrefix(partial) && (partial.hasPrefix(".") || !name.hasPrefix("."))
        }.sorted().map { name in
            var isDirectory: ObjCBool = false
            let full = directory.appendingPathComponent(name).path
            if FileManager.default.fileExists(atPath: full, isDirectory: &isDirectory), isDirectory.boolValue {
                return stem + name + "/"
            }
            return stem + name
        }
    }

    private func commonPrefix(_ names: [String]) -> String {
        guard var prefix = names.first else {
            return ""
        }
        for name in names.dropFirst() {
            while !name.hasPrefix(prefix) {
                prefix.removeLast()
                if prefix.isEmpty {
                    return ""
                }
            }
        }
        return prefix
    }

    public func prompt() -> String {
        let path = context.workingDirectory.path
        let home = context.home.path
        let short = path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
        return "\(short) % "
    }

    public var iosSystemReady: Bool {
        pad_ios_system_ready() != 0
    }
}

public enum NativeBackends {
    public static var iosSystem: Bool { pad_ios_system_ready() != 0 }
    public static var python: Bool { pad_python3_ready() != 0 }
}
