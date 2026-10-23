import SwiftUI
import TmuxControl
import UIKit

struct TmuxSessionView: View {
    var session: LiveSession
    @State private var selectedWindow: Int?
    @State private var selectedPane: Int?
    @State private var seenPanes: Set<Int> = []
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
                    },
                    onSplitVertical: { pane in
                        session.tmux.gateway.splitWindow(horizontal: true, target: pane)
                    },
                    onSplitHorizontal: { pane in
                        session.tmux.gateway.splitWindow(horizontal: false, target: pane)
                    }
                )
            } else {
                ContentUnavailableView {
                    Text(String(localized: "Pad.Tmux.Waiting",
                                defaultValue: "Waiting for tmux layout",
                                comment: "Placeholder while the first %layout-change has not arrived"))
                }
            }
            OptionalKeyboardAccessory(
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
        .modifier(TerminalKeyboardToggle())
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
                let panes = Set(session.tmux.windows.flatMap { $0.layout?.windowPanes() ?? [] })
                let added = panes.subtracting(seenPanes)
                seenPanes = panes
                if selectedWindow == nil {
                    selectedWindow = session.tmux.windows.first?.id
                }
                if selectedPane == nil || (selectedPane.map { !panes.contains($0) } ?? true) {
                    selectedPane = panes.max()
                } else if let newest = added.max() {
                    selectedPane = newest
                }
            }
            session.tmux.onPaneOutput = { pane, data in
                feeds[pane, default: Data()].append(data)
            }
            for window in session.tmux.windows {
                for pane in window.layout?.windowPanes() ?? [] {
                    session.tmux.captureHistory(for: pane) { data in
                        feeds[pane] = data
                    }
                }
            }
        }
        .background(Color.clear.opacity(windowsTick < 0 ? 1 : 0))
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
    var onSplitVertical: (Int) -> Void
    var onSplitHorizontal: (Int) -> Void
    var inSplit = false

    var body: some View {
        switch node.type {
        case .leaf:
            paneView(node)
        case .hSplit:
            GeometryReader { geo in
                let total = max(node.children.map { $0.height ?? 1 }.reduce(0, +), 1)
                VStack(spacing: 3) {
                    ForEach(Array(node.children.enumerated()), id: \.offset) { _, child in
                        splitChild(child)
                            .frame(height: geo.size.height * CGFloat(child.height ?? 1) / CGFloat(total))
                    }
                }
                .background(Color(uiColor: .opaqueSeparator))
            }
        case .vSplit:
            GeometryReader { geo in
                let total = max(node.children.map { $0.width ?? 1 }.reduce(0, +), 1)
                HStack(spacing: 3) {
                    ForEach(Array(node.children.enumerated()), id: \.offset) { _, child in
                        splitChild(child)
                            .frame(width: geo.size.width * CGFloat(child.width ?? 1) / CGFloat(total))
                    }
                }
                .background(Color(uiColor: .opaqueSeparator))
            }
        }
    }

    private func splitChild(_ child: TmuxLayoutNode) -> some View {
        TmuxSplitView(node: child,
                      feeds: feeds,
                      selectedPane: selectedPane,
                      onSelect: onSelect,
                      onSendText: onSendText,
                      onSize: onSize,
                      onSplitVertical: onSplitVertical,
                      onSplitHorizontal: onSplitHorizontal,
                      inSplit: true)
    }

    @ViewBuilder
    private func paneView(_ node: TmuxLayoutNode) -> some View {
        let pane = node.windowPane ?? 0
        let selected = pane == selectedPane
        let heavy = UIAccessibility.isDarkerSystemColorsEnabled
        PadTerminalRepresentable(
            onSend: { data in
                if let text = String(data: data, encoding: .utf8) {
                    onSendText(text, pane)
                }
            },
            onSize: onSize,
            onSplitVertical: { onSplitVertical(pane) },
            onSplitHorizontal: { onSplitHorizontal(pane) },
            feed: feeds[pane]
        )
        .overlay {
            ZStack {
                if inSplit && !selected {
                    Color.black.opacity(heavy ? 0.42 : 0.26)
                }
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(inSplit && selected ? Color.accentColor : Color.clear,
                                  lineWidth: heavy ? 3 : 2)
            }
            .allowsHitTesting(false)
        }
        .animation(UIAccessibility.isReduceMotionEnabled ? nil : .easeOut(duration: 0.2), value: selected)
        .onTapGesture {
            onSelect(pane)
        }
    }
}
