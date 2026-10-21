import Foundation

struct ClaudeAuth {
    let token: String
    let apiKey: Bool

    static func load(context: CommandContext) -> ClaudeAuth? {
        if let key = context.environment["ANTHROPIC_API_KEY"], key.hasPrefix("sk-ant-api") {
            return ClaudeAuth(token: key, apiKey: true)
        }
        if let token = context.environment["CLAUDE_CODE_OAUTH_TOKEN"], !token.isEmpty {
            ClaudeKeychain.save(token)
            return ClaudeAuth(token: token, apiKey: false)
        }
        _ = ClaudeKeychain.importFile(at: context.home)
        guard let stored = ClaudeKeychain.load() else {
            return nil
        }
        return parse(stored)
    }

    static func parse(_ raw: String) -> ClaudeAuth? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{"),
           let data = trimmed.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let oauth = json["claudeAiOauth"] as? [String: Any],
           let access = oauth["accessToken"] as? String,
           !access.isEmpty {
            return ClaudeAuth(token: access, apiKey: false)
        }
        guard !trimmed.isEmpty else {
            return nil
        }
        return ClaudeAuth(token: trimmed, apiKey: trimmed.hasPrefix("sk-ant-api"))
    }
}

func claudeRequest(auth: ClaudeAuth, body: [String: Any]) throws -> [String: Any] {
    var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
    request.httpMethod = "POST"
    request.timeoutInterval = 60
    request.setValue("application/json", forHTTPHeaderField: "content-type")
    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
    if auth.apiKey {
        request.setValue(auth.token, forHTTPHeaderField: "x-api-key")
    } else {
        request.setValue("Bearer \(auth.token)", forHTTPHeaderField: "authorization")
        request.setValue("oauth-2025-04-20,claude-code-20250219", forHTTPHeaderField: "anthropic-beta")
    }
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    let semaphore = DispatchSemaphore(value: 0)
    var outcome: Result<(Data, HTTPURLResponse), Error>?
    URLSession.shared.dataTask(with: request) { data, response, error in
        if let error {
            outcome = .failure(error)
        } else if let data, let response = response as? HTTPURLResponse {
            outcome = .success((data, response))
        } else {
            outcome = .failure(ShellError.failed("claude received an empty response"))
        }
        semaphore.signal()
    }.resume()
    semaphore.wait()
    let (data, response) = try outcome?.get() ?? { throw ShellError.failed("claude received an empty response") }()
    let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    if response.statusCode != 200 {
        let detail = json["error"] as? [String: Any]
        let message = detail?["message"] as? String ?? detail?["type"] as? String ?? "request failed"
        throw ShellError.failed("claude \(response.statusCode): \(message)")
    }
    return json
}

final class ClaudeCodeSession {
    private unowned let shell: ShellSession
    private let auth: ClaudeAuth
    private var messages: [[String: Any]] = []
    private var model = "claude-sonnet-4-6"
    private var announcedFallback = false

    init(shell: ShellSession, auth: ClaudeAuth) {
        self.shell = shell
        self.auth = auth
    }

    func turn(_ text: String, emit: (String) -> Void) -> String {
        messages.append(["role": "user", "content": text])
        for _ in 0..<8 {
            let response: [String: Any]
            do {
                response = try request()
            } catch {
                return error.localizedDescription
            }
            if announcedFallback {
                emit("Sonnet is rate limited. This session continues with Haiku.\n")
                announcedFallback = false
            }
            let content = response["content"] as? [[String: Any]] ?? []
            messages.append(["role": "assistant", "content": stored(content)])
            let spoken = content.compactMap { block -> String? in
                guard block["type"] as? String == "text" else { return nil }
                return block["text"] as? String
            }.joined(separator: "\n")
            let tools = content.filter { $0["type"] as? String == "tool_use" }
            if tools.isEmpty {
                return spoken.isEmpty ? "claude returned no text" : spoken
            }
            if !spoken.isEmpty {
                emit(spoken.hasSuffix("\n") ? spoken : spoken + "\n")
            }
            var results: [[String: Any]] = []
            for tool in tools {
                let name = tool["name"] as? String ?? ""
                let id = tool["id"] as? String ?? ""
                let input = tool["input"] as? [String: Any] ?? [:]
                emit(headline(name, input))
                let output = perform(name, input: input, emit: emit)
                results.append([
                    "type": "tool_result",
                    "tool_use_id": id,
                    "content": String(output.prefix(12_000))
                ])
            }
            messages.append(["role": "user", "content": results])
        }
        return "claude stopped after too many tool rounds"
    }

    private func stored(_ content: [[String: Any]]) -> [[String: Any]] {
        content.map { block in
            var clean: [String: Any] = ["type": block["type"] as? String ?? "text"]
            if let text = block["text"] { clean["text"] = text }
            if let id = block["id"] { clean["id"] = id }
            if let name = block["name"] { clean["name"] = name }
            if let input = block["input"] { clean["input"] = input }
            return clean
        }
    }

    private func request() throws -> [String: Any] {
        do {
            return try claudeRequest(auth: auth, body: requestBody())
        } catch {
            let text = error.localizedDescription
            guard text.contains("429"), model != "claude-haiku-4-5" else {
                throw error
            }
            model = "claude-haiku-4-5"
            announcedFallback = true
            return try claudeRequest(auth: auth, body: requestBody())
        }
    }

    private func requestBody() -> [String: Any] {
        let directory = shell.context.workingDirectory.path
        let system = """
        You are Claude Code inside pTerm2 on an iPad. The terminal is a built-in sandbox shell.
        Working directory: \(directory)
        Use the bash, read, write, and edit tools to inspect and change files inside this directory tree.
        bash runs the built-in commands (ls, python3, git, and the rest). Do not invent their output.
        Reply in the user's language. When the task is finished, answer in plain text and stop calling tools.
        """
        return [
            "model": model,
            "max_tokens": 4096,
            "system": system,
            "tools": Self.tools,
            "messages": messages
        ]
    }

    private func headline(_ name: String, _ input: [String: Any]) -> String {
        switch name {
        case "bash":
            return "bash: \(input["command"] as? String ?? "")\n"
        case "read":
            return "read \(input["path"] as? String ?? "")\n"
        case "write":
            return "write \(input["path"] as? String ?? "")\n"
        case "edit":
            return "edit \(input["path"] as? String ?? "")\n"
        default:
            return "\(name)\n"
        }
    }

    private func perform(_ name: String, input: [String: Any], emit: (String) -> Void) -> String {
        switch name {
        case "bash":
            let command = input["command"] as? String ?? ""
            let saved = shell.output
            var captured = ""
            shell.output = { text in
                captured += text
                saved?(text)
            }
            let code = shell.run(command)
            shell.output = saved
            if captured.isEmpty {
                emit("(no output)\n")
            }
            return "exit \(code)\n\(captured)"
        case "read":
            return readFile(input["path"] as? String ?? "")
        case "write":
            return writeFile(input["path"] as? String ?? "", input["content"] as? String ?? "")
        case "edit":
            return editFile(input["path"] as? String ?? "",
                            input["old"] as? String ?? "",
                            input["new"] as? String ?? "")
        default:
            return "unknown tool \(name)"
        }
    }

    private func readFile(_ path: String) -> String {
        let url = guarded(path)
        guard let url else { return "path is outside the sandbox" }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "cannot read \(path)"
        }
        return text
    }

    private func writeFile(_ path: String, _ content: String) -> String {
        guard let url = guarded(path) else { return "path is outside the sandbox" }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try content.write(to: url, atomically: true, encoding: .utf8)
            return "wrote \(url.lastPathComponent)"
        } catch {
            return error.localizedDescription
        }
    }

    private func editFile(_ path: String, _ old: String, _ new: String) -> String {
        guard let url = guarded(path) else { return "path is outside the sandbox" }
        guard var text = try? String(contentsOf: url, encoding: .utf8) else {
            return "cannot read \(path)"
        }
        guard let range = text.range(of: old) else {
            return "old text was not found"
        }
        text.replaceSubrange(range, with: new)
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return "edited \(url.lastPathComponent)"
        } catch {
            return error.localizedDescription
        }
    }

    private func guarded(_ path: String) -> URL? {
        let resolved = resolve(path, relativeTo: shell.context)
        let root = shell.context.root.standardizedFileURL.path
        let chosen = resolved.standardizedFileURL.path
        if chosen == root {
            return nil
        }
        return resolved
    }

    private static let tools: [[String: Any]] = [
        [
            "name": "bash",
            "description": "Run one shell command in the iPad sandbox and return its output.",
            "input_schema": [
                "type": "object",
                "properties": ["command": ["type": "string"]],
                "required": ["command"]
            ]
        ],
        [
            "name": "read",
            "description": "Read a UTF-8 text file inside the sandbox.",
            "input_schema": [
                "type": "object",
                "properties": ["path": ["type": "string"]],
                "required": ["path"]
            ]
        ],
        [
            "name": "write",
            "description": "Create or replace a UTF-8 text file inside the sandbox.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "path": ["type": "string"],
                    "content": ["type": "string"]
                ],
                "required": ["path", "content"]
            ]
        ],
        [
            "name": "edit",
            "description": "Replace the first exact occurrence of old text in a file.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "path": ["type": "string"],
                    "old": ["type": "string"],
                    "new": ["type": "string"]
                ],
                "required": ["path", "old", "new"]
            ]
        ]
    ]
}

struct ClaudeCommand: ShellCommand {
    let name = "claude"

    func run(arguments: [String], context: inout CommandContext) throws -> Int32 {
        if arguments.contains("--version") || arguments.contains("-v") {
            context.stdout("2.1.304 (pTerm)\n")
            return 0
        }
        if arguments.contains("-h") || arguments.contains("--help") {
            context.stdout(usage)
            return 0
        }
        let parsed = parse(arguments)
        guard !parsed.prompt.isEmpty else {
            context.stdout(usage)
            return 1
        }
        guard let auth = ClaudeAuth.load(context: context) else {
            context.stderr(String(localized: "Shell.Claude.MissingToken",
                                  defaultValue: "claude needs the Claude login in the iPad keychain.\n",
                                  comment: "Shown when the built-in claude command has no API or OAuth token"))
            return 1
        }
        do {
            let json = try claudeRequest(auth: auth, body: [
                "model": parsed.model,
                "max_tokens": 1024,
                "messages": [["role": "user", "content": parsed.prompt]]
            ])
            let blocks = json["content"] as? [[String: Any]] ?? []
            let text = blocks.compactMap { block -> String? in
                guard block["type"] as? String == "text" else { return nil }
                return block["text"] as? String
            }.joined()
            if text.isEmpty {
                throw ShellError.failed("claude returned no text")
            }
            context.stdout(text.hasSuffix("\n") ? text : text + "\n")
            return 0
        } catch {
            context.stderr(error.localizedDescription + "\n")
            return 1
        }
    }

    private var usage: String {
        String(localized: "Shell.Claude.Usage",
               defaultValue: "Usage: claude\nclaude -p TEXT\nclaude --version\n",
               comment: "Usage for the built-in claude command. Bare claude opens a session.")
    }

    private func parse(_ arguments: [String]) -> (prompt: String, model: String) {
        var model = "claude-haiku-4-5"
        var words: [String] = []
        var index = 0
        while index < arguments.count {
            let word = arguments[index]
            if word == "--model", index + 1 < arguments.count {
                model = arguments[index + 1]
                index += 2
                continue
            }
            if word == "-p" || word == "--print" {
                index += 1
                continue
            }
            if word.hasPrefix("-") {
                index += 1
                continue
            }
            words.append(word)
            index += 1
        }
        return (words.joined(separator: " "), model)
    }
}
