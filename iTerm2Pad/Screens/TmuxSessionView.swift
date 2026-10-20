import SwiftUI
import TmuxControl

struct TmuxSessionView: View {
    var session: LiveSession
    @State private var selectedWindow: Int?
    @State private var selectedPane: Int?
    @State private var feeds: [Int: Data] = [:]
    @State private var windowsTick = 0

    var body: some View {
        VStack(spacing: 0) {
            windowBar
            if let window = currentWindow, let layout = window.layout {
                TmuxSplitView(
                    node: layout,
                    feeds: feeds,
                    selectedPane: selectedPane,
                    onSelect: { selectedPane = $0 },
                    onSendText: { text, pane in
                        session.sendTmuxText(text, pane: pane)
                    },
                    onSize: { cols, rows in
                        session.resize(columns: cols, rows: rows)
                    }
                )
            } else {
                ContentUnavailableView {
                    Text(String(localized: "Pad.Tmux.Waiting",
                                defaultValue: "Waiting for tmux layout",
                                comment: "Placeholder while the first %layout-change has not arrived"))
                }
            }
            KeyboardAccessory(
                onKey: { special in
                    if let pane = selectedPane {
                        session.sendTmuxKey(TmuxKeyName.namedSpecial(special), pane: pane)
                    }
                },
                onControlC: {
                    if let pane = selectedPane {
                        session.sendTmuxKey("C-C", pane: pane)
                    }
                }
            )
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("h") { movePane("select-pane -L") }
                Button("j") { movePane("select-pane -D") }
                Button("k") { movePane("select-pane -U") }
                Button("l") { movePane("select-pane -R") }
                Button(String(localized: "Pad.Tmux.SplitVKey",
                              defaultValue: "−",
                              comment: "prefix - splits the pane with a horizontal line, matching the embedded tmux standard")) {
                    if let pane = selectedPane {
                        session.tmux.gateway.splitWindow(horizontal: false, target: pane)
                    }
                }
                Button(String(localized: "Pad.Tmux.SplitHKey",
                              defaultValue: "_",
                              comment: "prefix _ splits the pane with a vertical line, matching the embedded tmux standard")) {
                    if let pane = selectedPane {
                        session.tmux.gateway.splitWindow(horizontal: true, target: pane)
                    }
                }
                Button(String(localized: "Pad.Tmux.Detach",
                              defaultValue: "Detach",
                              comment: "Detaches from the tmux session")) {
                    session.tmux.gateway.detach()
                }
            }
        }
        .onAppear {
            session.tmux.onWindowsChanged = {
                windowsTick += 1
                if selectedWindow == nil {
                    selectedWindow = session.tmux.windows.first?.id
                    selectedPane = session.tmux.windows.first?.layout?.windowPanes().first
                }
            }
            session.tmux.onPaneOutput = { pane, data in
                feeds[pane] = data
            }
            for window in session.tmux.windows {
                for pane in window.layout?.windowPanes() ?? [] {
                    session.tmux.captureHistory(for: pane) { data in
                        feeds[pane] = data
                    }
                }
            }
        }
        .id(windowsTick)
    }

    private func movePane(_ command: String) {
        session.tmux.gateway.sendFireAndForget(command)
    }

    private var currentWindow: TmuxWindow? {
        if let selectedWindow {
            return session.tmux.windows.first { $0.id == selectedWindow }
        }
        return session.tmux.windows.first
    }

    private var windowBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(session.tmux.windows) { window in
                    Button(window.name.isEmpty ? "@\(window.id)" : window.name) {
                        selectedWindow = window.id
                        selectedPane = window.layout?.windowPanes().first
                    }
                    .buttonStyle(.bordered)
                    .tint(window.id == selectedWindow ? .accentColor : .secondary)
                }
            }
            .padding(8)
        }
    }

}

struct TmuxSplitView: View {
    var node: TmuxLayoutNode
    var feeds: [Int: Data]
    var selectedPane: Int?
    var onSelect: (Int) -> Void
    var onSendText: (String, Int) -> Void
    var onSize: (Int, Int) -> Void

    var body: some View {
        switch node.type {
        case .leaf:
            paneView(node)
        case .hSplit:
            VStack(spacing: 1) {
                ForEach(Array(node.children.enumerated()), id: \.offset) { _, child in
                    TmuxSplitView(node: child,
                                  feeds: feeds,
                                  selectedPane: selectedPane,
                                  onSelect: onSelect,
                                  onSendText: onSendText,
                                  onSize: onSize)
                }
            }
        case .vSplit:
            HStack(spacing: 1) {
                ForEach(Array(node.children.enumerated()), id: \.offset) { _, child in
                    TmuxSplitView(node: child,
                                  feeds: feeds,
                                  selectedPane: selectedPane,
                                  onSelect: onSelect,
                                  onSendText: onSendText,
                                  onSize: onSize)
                }
            }
        }
    }

    @ViewBuilder
    private func paneView(_ node: TmuxLayoutNode) -> some View {
        let pane = node.windowPane ?? 0
        PadTerminalRepresentable(
            onSend: { data in
                if let text = String(data: data, encoding: .utf8) {
                    onSendText(text, pane)
                }
            },
            onSize: onSize,
            feed: feeds[pane]
        )
        .overlay {
            RoundedRectangle(cornerRadius: 2)
                .stroke(pane == selectedPane ? Color.accentColor : Color.clear, lineWidth: 2)
        }
        .onTapGesture {
            onSelect(pane)
        }
    }
}
