import SwiftUI
import LocalShell

struct LocalShellView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var session: ShellSession?
    @State private var buffer = ""
    @State private var line = ""
    @FocusState private var commandFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    Text(buffer)
                        .font(.body.monospaced())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .textSelection(.enabled)
                    Color.clear
                        .frame(height: 1)
                        .id(Self.bottomID)
                }
                .scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    commandBar
                }
                .onChange(of: buffer) { _, _ in
                    followBottom(with: proxy)
                }
            }
            .background(Color(.systemBackground))
            .navigationTitle(String(localized: "Pad.Shell.Title",
                                    defaultValue: "Shell",
                                    comment: "Navigation title of the local shell"))
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if session == nil {
                    let shell = ShellSession(home: model.documents)
                    shell.output = { text in
                        buffer.append(text)
                    }
                    let banner = String(localized: "Pad.Shell.Banner",
                                        defaultValue: "pTerm2 local shell. Type help for commands. python3, pip3, git, scp, and sshfs are available.\n",
                                        comment: "First line printed when the local shell opens")
                    buffer.append(banner)
                    session = shell
                }
                commandFocused = true
            }
        }
    }

    private var commandBar: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(session?.prompt() ?? "$ ")
                .font(.body.monospaced())
                .foregroundStyle(.secondary)
            TextField(String(localized: "Pad.Shell.Command",
                             defaultValue: "Command",
                             comment: "Placeholder in the local-shell input field"),
                      text: $line)
                .font(.body.monospaced())
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($commandFocused)
                .submitLabel(.go)
                .onSubmit {
                    runLine()
                }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 44)
        .background(.bar)
    }

    private func followBottom(with proxy: ScrollViewProxy) {
        if reduceMotion {
            proxy.scrollTo(Self.bottomID, anchor: .bottom)
        } else {
            withAnimation(.spring(response: 0.4, dampingFraction: 1)) {
                proxy.scrollTo(Self.bottomID, anchor: .bottom)
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
        commandFocused = true
        model.consumePendingSSHLaunch()
    }

    private static let bottomID = "shell-bottom"
}
