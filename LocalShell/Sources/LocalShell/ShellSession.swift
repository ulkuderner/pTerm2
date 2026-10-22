import Foundation
import PadSystem

public final class ShellSession: @unchecked Sendable {
    public let registry = CommandRegistry()
    public private(set) var context: CommandContext
    public var output: ((String) -> Void)?
    public var promptColumns = 80
    public var lastStatus: Int32 = 0
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
        let code = registry.run(line, context: &context)
        lastStatus = code
        return code
    }

    public func run(arguments: [String]) -> Int32 {
        let code = registry.run(arguments: arguments, context: &context)
        lastStatus = code
        return code
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
        let left = leftPrompt()
        let right = rightPrompt()
        let leftWidth = visibleCount(left)
        let rightWidth = visibleCount(right)
        let gap = promptColumns - leftWidth - rightWidth
        let first: String
        if gap >= 1 {
            first = left + String(repeating: " ", count: gap) + right
        } else {
            first = left
        }
        let mark = lastStatus == 0 ? 76 : 196
        let second = "\u{1b}[38;5;240m╰─\u{1b}[0m \u{1b}[1;38;5;\(mark)m❯\u{1b}[0m "
        return first + "\r\n" + second
    }

    private func leftPrompt() -> String {
        var parts = ["\u{1b}[38;5;255m\u{F179}"]
        parts.append(directoryText())
        if let git = gitText() {
            parts.append(git)
        }
        let body = parts.joined(separator: "\u{1b}[38;5;244m\u{E0B1}")
        return "\u{1b}[48;5;236m \(body) \u{1b}[0m\u{1b}[38;5;236m\u{E0B0}\u{1b}[0m"
    }

    private func rightPrompt() -> String {
        let status = lastStatus == 0
            ? "\u{1b}[38;5;70m✔"
            : "\u{1b}[38;5;196m\(lastStatus)"
        let clock = "\u{1b}[38;5;66m\(clockText())"
        let who = "\u{1b}[38;5;180m\(whoText())"
        let body = [status, clock, who].joined(separator: "\u{1b}[38;5;244m\u{E0B3}")
        return "\u{1b}[38;5;236m\u{E0B2}\u{1b}[48;5;236m \(body) \u{1b}[0m"
    }

    private func directoryText() -> String {
        let path = context.workingDirectory.path
        let home = context.home.path
        let short = path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
        let pieces = short.split(separator: "/", omittingEmptySubsequences: false)
        guard let leaf = pieces.last, !String(leaf).isEmpty else {
            return "\u{1b}[1;38;5;39m~"
        }
        let parents = pieces.dropLast().joined(separator: "/")
        let prefix = parents.isEmpty ? "" : parents + "/"
        return "\u{1b}[38;5;31m\(prefix)\u{1b}[1;38;5;39m\(leaf)\u{1b}[22m"
    }

    private func gitText() -> String? {
        guard let git = findGitDirectory() else {
            return nil
        }
        let head = (try? String(contentsOf: git.appendingPathComponent("HEAD"), encoding: .utf8)) ?? ""
        let trimmed = head.trimmingCharacters(in: .whitespacesAndNewlines)
        let branch: String
        if trimmed.hasPrefix("ref: refs/heads/") {
            branch = String(trimmed.dropFirst("ref: refs/heads/".count))
        } else if trimmed.count >= 7 {
            branch = String(trimmed.prefix(7))
        } else {
            return nil
        }
        return "\u{1b}[38;5;148m\u{F126} \(branch)"
    }

    private func findGitDirectory() -> URL? {
        var current = context.workingDirectory.standardizedFileURL
        let limit = context.root.standardizedFileURL.path
        while true {
            let git = current.appendingPathComponent(".git")
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: git.path, isDirectory: &isDirectory), isDirectory.boolValue {
                return git
            }
            if current.path == limit || current.path == "/" {
                return nil
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path {
                return nil
            }
            current = parent
        }
    }

    private func clockText() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date())
    }

    private func whoText() -> String {
        let user = ProcessInfo.processInfo.environment["USER"].flatMap { $0.isEmpty ? nil : $0 } ?? "mobile"
        var host = ProcessInfo.processInfo.hostName
        if let dot = host.firstIndex(of: ".") {
            host = String(host[..<dot])
        }
        if host.isEmpty {
            host = "ipad"
        }
        return "\(user)@\(host)"
    }

    private func visibleCount(_ text: String) -> Int {
        text.replacingOccurrences(of: "\u{1b}\\[[0-9;]*m", with: "", options: .regularExpression).count
    }

    public var iosSystemReady: Bool {
        pad_ios_system_ready() != 0
    }
}

public enum NativeBackends {
    public static var iosSystem: Bool { pad_ios_system_ready() != 0 }
    public static var python: Bool { pad_python3_ready() != 0 }
}
