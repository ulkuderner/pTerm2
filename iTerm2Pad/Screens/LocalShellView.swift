import SwiftTerm
import SwiftUI
import UIKit

@Observable
final class ShellWorkspace {
    struct Node: Identifiable {
        let id: UUID
        var kind: Kind

        enum Kind {
            case leaf(UUID)
            case beside([Node])
            case stacked([Node])
        }
    }

    private(set) var root: Node
    var focused: UUID
    private var sessions: [UUID: ZshSession] = [:]
    private var hosts: [UUID: PadTerminalHost] = [:]

    init() {
        let pane = UUID()
        let session = ZshSession()
        focused = pane
        root = Node(id: pane, kind: .leaf(pane))
        let host = PadTerminalHost(frame: .zero)
        sessions = [pane: session]
        hosts = [pane: host]
        connect(session, to: host)
        session.onExit = { [weak self] in
            self?.close(pane)
        }
    }

    func hostsSnapshot() -> [UUID: PadTerminalHost] {
        hosts
    }

    func session(for pane: UUID) -> ZshSession? {
        sessions[pane]
    }

    func host(for pane: UUID) -> PadTerminalHost? {
        hosts[pane]
    }

    func focus(_ pane: UUID) {
        focused = pane
    }

    /// Command-D puts the new shell to the right. Command-Shift-D puts it below.
    func split(_ pane: UUID, beside: Bool, program: String? = nil, missingNotice: String? = nil) {
        let added = UUID()
        let session = ZshSession()
        session.launchProgram = program
        session.missingNotice = missingNotice
        session.onExit = { [weak self] in
            self?.close(added)
        }
        let host = PadTerminalHost(frame: .zero)
        sessions[added] = session
        hosts[added] = host
        connect(session, to: host)
        guard let updated = root.replacing(pane, beside: beside, newPane: added) else {
            return
        }
        root = updated
        focused = added
    }

    func splitFocused(beside: Bool) {
        split(focused, beside: beside)
    }

    func open(_ agent: AgentTool) {
        split(focused, beside: true, program: agent.executable(), missingNotice: agent.missingNotice())
    }

    /// Ctrl-D closes the pane. A lone remaining sibling expands into the free space.
    func close(_ pane: UUID) {
        guard sessions[pane] != nil else {
            return
        }
        let neighbor = root.sibling(of: pane)
        let session = sessions.removeValue(forKey: pane)
        session?.onExit = nil
        session?.stop()
        hosts[pane]?.removeFromSuperview()
        hosts.removeValue(forKey: pane)
        if let updated = root.removing(pane) {
            root = updated
            if focused == pane {
                focused = neighbor ?? updated.firstLeaf() ?? pane
            }
            return
        }
        let fresh = UUID()
        let replacement = ZshSession()
        focused = fresh
        root = Node(id: fresh, kind: .leaf(fresh))
        let host = PadTerminalHost(frame: .zero)
        sessions = [fresh: replacement]
        hosts = [fresh: host]
        connect(replacement, to: host)
        replacement.onExit = { [weak self] in
            self?.close(fresh)
        }
    }

    private func connect(_ session: ZshSession, to host: PadTerminalHost) {
        host.terminal.terminalDelegate = host
        host.onBytes = { [weak session] data in
            session?.send(data)
        }
        host.onResize = { [weak session] columns, rows in
            session?.resize(columns: columns, rows: rows)
        }
        session.onOutput = { [weak host] data in
            host?.terminal.feed(byteArray: ArraySlice(data))
        }
        session.start()
    }

    func stopAll() {
        for session in sessions.values {
            session.onExit = nil
            session.stop()
        }
    }
}

private extension ShellWorkspace.Node {
    func replacing(_ target: UUID, beside: Bool, newPane: UUID) -> ShellWorkspace.Node? {
        switch kind {
        case .leaf(let pane):
            guard pane == target else {
                return nil
            }
            let current = ShellWorkspace.Node(id: pane, kind: .leaf(pane))
            let added = ShellWorkspace.Node(id: newPane, kind: .leaf(newPane))
            return ShellWorkspace.Node(id: UUID(), kind: beside ? .beside([current, added]) : .stacked([current, added]))
        case .beside(let children):
            return replacingChildren(children, beside: beside, target: target, newPane: newPane, stacked: false)
        case .stacked(let children):
            return replacingChildren(children, beside: beside, target: target, newPane: newPane, stacked: true)
        }
    }

    func removing(_ target: UUID) -> ShellWorkspace.Node? {
        switch kind {
        case .leaf(let pane):
            return pane == target ? nil : self
        case .beside(let children):
            return collapsing(children, target: target, stacked: false)
        case .stacked(let children):
            return collapsing(children, target: target, stacked: true)
        }
    }

    func sibling(of target: UUID) -> UUID? {
        switch kind {
        case .leaf:
            return nil
        case .beside(let children), .stacked(let children):
            guard let index = children.firstIndex(where: { $0.contains(target) }) else {
                return nil
            }
            if case .leaf(let pane) = children[index].kind, pane == target {
                guard children.count > 1 else {
                    return nil
                }
                let neighbor = index > 0 ? children[index - 1] : children[index + 1]
                return neighbor.firstLeaf()
            }
            return children[index].sibling(of: target)
        }
    }

    func firstLeaf() -> UUID? {
        switch kind {
        case .leaf(let pane):
            return pane
        case .beside(let children), .stacked(let children):
            for child in children {
                if let pane = child.firstLeaf() {
                    return pane
                }
            }
            return nil
        }
    }

    private func contains(_ target: UUID) -> Bool {
        switch kind {
        case .leaf(let pane):
            return pane == target
        case .beside(let children), .stacked(let children):
            return children.contains { $0.contains(target) }
        }
    }

    private func collapsing(_ children: [ShellWorkspace.Node], target: UUID, stacked: Bool) -> ShellWorkspace.Node? {
        let kept = children.compactMap { $0.removing(target) }
        if kept.isEmpty {
            return nil
        }
        if kept.count == 1 {
            return kept[0]
        }
        return ShellWorkspace.Node(id: id, kind: stacked ? .stacked(kept) : .beside(kept))
    }

    private func replacingChildren(_ children: [ShellWorkspace.Node],
                                   beside: Bool,
                                   target: UUID,
                                   newPane: UUID,
                                   stacked: Bool) -> ShellWorkspace.Node? {
        for index in children.indices {
            if let updated = children[index].replacing(target, beside: beside, newPane: newPane) {
                var copy = children
                copy[index] = updated
                return ShellWorkspace.Node(id: id, kind: stacked ? .stacked(copy) : .beside(copy))
            }
        }
        return nil
    }
}

struct LocalShellView: View {
    @State private var workspace = ShellWorkspace()
    @State private var showingThemes = false

    var body: some View {
        NavigationStack {
            ShellCanvasRepresentable(workspace: workspace)
                .background(Color.black)
                .navigationTitle(String(localized: "Pad.Shell.Title",
                                        defaultValue: "Shell",
                                        comment: "Navigation title of the local shell"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(Color.black, for: .navigationBar)
                .toolbarColorScheme(.dark, for: .navigationBar)
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Menu {
                            ForEach(AgentTool.all) { agent in
                                Button(agent.title, systemImage: agent.symbol) {
                                    workspace.open(agent)
                                }
                            }
                        } label: {
                            Label(String(localized: "Pad.Agent.Menu",
                                         defaultValue: "Agents",
                                         comment: "Toolbar menu that opens Claude, OpenAI, or Gemini"),
                                  systemImage: "sparkles")
                        }
                        Button {
                            showingThemes = true
                        } label: {
                            Label(String(localized: "Pad.Theme.Title",
                                         defaultValue: "Themes",
                                         comment: "Title of the terminal theme gallery"),
                                  systemImage: "paintpalette")
                        }
                    }
                }
                .modifier(TerminalKeyboardToggle())
                .sheet(isPresented: $showingThemes) {
                    NavigationStack {
                        ThemeGallery()
                            .toolbar {
                                ToolbarItem(placement: .confirmationAction) {
                                    Button(String(localized: "Pad.Theme.Done",
                                                  defaultValue: "Done",
                                                  comment: "Closes the theme gallery")) {
                                        showingThemes = false
                                    }
                                }
                            }
                    }
                    .modifier(PadFormSheet())
                }
                .onDisappear {
                    workspace.stopAll()
                }
        }
    }
}

private struct ShellCanvasRepresentable: UIViewRepresentable {
    var workspace: ShellWorkspace

    func makeUIView(context: Context) -> ShellCanvas {
        let canvas = ShellCanvas()
        canvas.sync(workspace)
        return canvas
    }

    func updateUIView(_ canvas: ShellCanvas, context: Context) {
        canvas.sync(workspace)
    }
}

/// One stable view owns every pane. Closing a split only removes that pane,
/// so the others stay in the window and keep the keyboard.
final class ShellCanvas: UIView {
    private var root: ShellWorkspace.Node?
    private var hosts: [UUID: PadTerminalHost] = [:]
    private var focusedPane: UUID?
    private var pendingFocus = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        clipsToBounds = true
    }

    required init?(coder: NSCoder) {
        it_fatalError("ShellCanvas is built in code")
    }

    func sync(_ workspace: ShellWorkspace) {
        root = workspace.root
        focusedPane = workspace.focused
        hosts = workspace.hostsSnapshot()
        let alive = Set(hosts.keys)
        for case let host as PadTerminalHost in subviews {
            if let pane = host.pane, !alive.contains(pane) {
                host.removeFromSuperview()
            }
        }
        for (pane, host) in hosts {
            host.pane = pane
            host.onClose = { [weak workspace] in workspace?.close(pane) }
            host.onSplitVertical = { [weak workspace] in workspace?.split(pane, beside: true) }
            host.onSplitHorizontal = { [weak workspace] in workspace?.split(pane, beside: false) }
            host.terminal.onFocus = { [weak workspace, weak host] in
                workspace?.focus(pane)
                host?.claimKeyboard()
            }
            host.terminal.layer.borderWidth = pane == focusedPane ? 2 : 0
            host.terminal.layer.borderColor = UIColor.tintColor.cgColor
        }
        if !hosts.values.contains(where: { $0.terminal.isFirstResponder }) {
            pendingFocus = true
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 2, bounds.height > 2, let root else {
            return
        }
        layout(root, in: bounds)
        guard pendingFocus, let focusedPane, let host = hosts[focusedPane], window != nil else {
            return
        }
        pendingFocus = false
        host.claimKeyboard()
    }

    private func layout(_ node: ShellWorkspace.Node, in rect: CGRect) {
        switch node.kind {
        case .leaf(let pane):
            guard let host = hosts[pane] else {
                return
            }
            if host.superview !== self {
                addSubview(host)
            }
            host.frame = rect.integral
        case .beside(let children):
            layout(children, in: rect, stacked: false)
        case .stacked(let children):
            layout(children, in: rect, stacked: true)
        }
    }

    private func layout(_ children: [ShellWorkspace.Node], in rect: CGRect, stacked: Bool) {
        guard !children.isEmpty else {
            return
        }
        let gaps = CGFloat(children.count - 1)
        var origin = stacked ? rect.minY : rect.minX
        let span = stacked ? rect.height : rect.width
        let share = (span - gaps) / CGFloat(children.count)
        for (index, child) in children.enumerated() {
            let remaining = (stacked ? rect.maxY : rect.maxX) - origin
            let length = index == children.count - 1 ? remaining : share
            let piece = stacked
                ? CGRect(x: rect.minX, y: origin, width: rect.width, height: length)
                : CGRect(x: origin, y: rect.minY, width: length, height: rect.height)
            layout(child, in: piece)
            origin += length + 1
        }
    }
}
