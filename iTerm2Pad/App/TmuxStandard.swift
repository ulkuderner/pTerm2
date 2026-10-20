import Foundation

/// The tmux standard from git.profelis.com.tr/caglar/.tmux (gpakosz, with the
/// local overrides). It is copied to the remote account and sourced so the
/// prefix shortcuts match that config. Panes start a login zsh.
enum TmuxStandard {
    static let remoteDirectory = "$HOME/.pterm2"

    static func launchCommand(remoteCommand: String) -> String {
        let conf64 = Data(relocated(load(resource: "tmux", ext: "conf")).utf8).base64EncodedString()
        let local64 = Data(relocated(load(resource: "tmux.conf", ext: "local") + zshShell).utf8).base64EncodedString()
        let tmux = withConfigFile(remoteCommand)
        return """
        mkdir -p \(remoteDirectory) && printf '%s' '\(conf64)' | base64 -d > \(remoteDirectory)/.tmux.conf && printf '%s' '\(local64)' | base64 -d > \(remoteDirectory)/.tmux.conf.local && \(tmux)
        """
    }

    static func sourceCommand() -> String {
        "source-file ~/.pterm2/.tmux.conf"
    }

    private static let zshShell = """

# pTerm2: each pane is a login zsh, so oh-my-zsh loads when the account has it.
set -g default-command "command -v zsh >/dev/null 2>&1 && exec zsh -l || exec ${SHELL:-/bin/sh} -l"
"""

    private static func withConfigFile(_ command: String) -> String {
        guard !command.contains("-f ") else {
            return command
        }
        return command.replacingOccurrences(of: "tmux ", with: "tmux -f \"$HOME/.pterm2/.tmux.conf\" ")
    }

    private static func relocated(_ text: String) -> String {
        text
            .replacingOccurrences(of: "~/.tmux.conf.local", with: "~/.pterm2/.tmux.conf.local")
            .replacingOccurrences(of: "~/.tmux.conf", with: "~/.pterm2/.tmux.conf")
    }

    private static func load(resource: String, ext: String) -> String {
        let url = Bundle.main.url(forResource: resource, withExtension: ext, subdirectory: "tmux")
            ?? Bundle.main.url(forResource: resource, withExtension: ext)
        guard let url, let text = try? String(contentsOf: url, encoding: .utf8) else {
            return ""
        }
        return text
    }
}
