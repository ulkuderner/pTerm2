import Foundation

/// Coding agents launched inside a terminal pane. OpenAI’s installed CLI is Codex.
struct AgentTool: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let binaries: [String]
    let symbol: String
    var builtin = false

    static let claude = AgentTool(
        id: "claude",
        title: "Claude",
        detail: "Claude Code",
        binaries: ["claude"],
        symbol: "sparkles",
        builtin: true
    )

    static let openai = AgentTool(
        id: "openai",
        title: "OpenAI",
        detail: "Codex",
        binaries: ["codex", "openai"],
        symbol: "circle.hexagongrid"
    )

    static let gemini = AgentTool(
        id: "gemini",
        title: "Gemini",
        detail: "Gemini CLI",
        binaries: ["gemini"],
        symbol: "wand.and.stars"
    )

    static let all = [claude, openai, gemini]

    func executable() -> String? {
        let home = NSHomeDirectory()
        let directories = [
            "\(home)/.local/bin",
            "\(home)/opt/homebrew/bin",
            "\(home)/Library/bin"
        ]
        for name in binaries {
            for directory in directories {
                let path = "\(directory)/\(name)"
                if FileManager.default.isExecutableFile(atPath: path) {
                    return path
                }
            }
        }
        return nil
    }

    func missingNotice() -> String {
        String(format: String(localized: "Pad.Agent.Missing",
                              defaultValue: "%@ is not installed for this shell.",
                              comment: "Pane message when an agent command cannot be found. The argument is the agent name."),
               title)
    }
}
