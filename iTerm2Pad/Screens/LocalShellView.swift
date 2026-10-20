import SwiftUI
import LocalShell

struct LocalShellView: View {
    @Environment(AppModel.self) private var model
    @State private var session: ShellSession?
    @State private var buffer = ""
    @State private var line = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    Text(buffer)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .textSelection(.enabled)
                }
                HStack {
                    Text(session?.prompt() ?? "$ ")
                        .font(.system(.body, design: .monospaced))
                    TextField(String(localized: "Pad.Shell.Command",
                                     defaultValue: "Command",
                                     comment: "Placeholder in the local-shell input field"),
                              text: $line)
                        .font(.system(.body, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit {
                            runLine()
                        }
                }
                .padding()
            }
            .navigationTitle(String(localized: "Pad.Shell.Title",
                                    defaultValue: "Shell",
                                    comment: "Navigation title of the local shell"))
            .onAppear {
                if session == nil {
                    let shell = ShellSession(home: model.documents)
                    shell.output = { text in
                        buffer.append(text)
                    }
                    let banner = String(localized: "Pad.Shell.Banner",
                                        defaultValue: "iTerm2 Pad local shell. Type help for commands. python3, pip3, git, scp, and sshfs are available.\n",
                                        comment: "First line printed when the local shell opens")
                    buffer.append(banner)
                    session = shell
                }
            }
        }
    }

    private func runLine() {
        guard let session else {
            return
        }
        buffer.append(session.prompt() + line + "\n")
        _ = session.run(line)
        line = ""
        model.consumePendingSSHLaunch()
    }
}
