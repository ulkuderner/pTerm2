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
    private var lastFreshShell = Date.distantPast

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
        if Date().timeIntervalSince(lastFreshShell) < 1 {
            return
        }
        lastFreshShell = Date()
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
            if CommandLine.arguments.contains("-pterm-log") {
                let url = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("pterm-screen.log")
                if FileManager.default.fileExists(atPath: url.path),
                   let handle = try? FileHandle(forWritingTo: url) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    try? handle.close()
                } else {
                    try? data.write(to: url)
                }
            }
            guard let host, let text = String(data: data, encoding: .utf8) else {
                return
            }
            let current = host.terminal.accessibilityLabel ?? ""
            let combined = (current + text).suffix(4000)
            host.terminal.accessibilityLabel = String(combined)
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
                .onAppear {
                    if CommandLine.arguments.contains("-pterm-split") {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            workspace.splitFocused(beside: true)
                        }
                    }
                }
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
    private var splitFractions: [UUID: [CGFloat]] = [:]
    private var dividers: [String: SplitDivider] = [:]

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .opaqueSeparator
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
        for pane in chromes.keys where !alive.contains(pane) {
            chromes[pane]?.removeFromSuperview()
            chromes[pane] = nil
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
            let chrome = self.chrome(for: pane)
            let selected = pane == focusedPane
            let split = hosts.count > 1
            let heavy = traitCollection.accessibilityContrast == .high
            let apply = {
                chrome.apply(selected: selected, split: split, heavy: heavy)
            }
            if UIAccessibility.isReduceMotionEnabled {
                apply()
            } else {
                UIView.animate(withDuration: 0.2,
                               delay: 0,
                               options: [.allowUserInteraction, .beginFromCurrentState],
                               animations: apply)
            }
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
            if let chrome = chromes[pane] {
                chrome.frame = host.frame
                bringSubviewToFront(chrome)
            }
        case .beside(let children):
            layout(children, in: rect, stacked: false, parent: node.id)
        case .stacked(let children):
            layout(children, in: rect, stacked: true, parent: node.id)
        }
    }

    private func layout(_ children: [ShellWorkspace.Node], in rect: CGRect, stacked: Bool, parent: UUID) {
        guard !children.isEmpty else {
            return
        }
        var fractions = splitFractions[parent] ?? Array(repeating: 1, count: children.count)
        if fractions.count != children.count {
            fractions = Array(repeating: 1, count: children.count)
            splitFractions[parent] = fractions
        }
        let total = max(fractions.reduce(0, +), 0.001)
        let gaps = CGFloat(children.count - 1) * Self.separatorGap
        let span = max((stacked ? rect.height : rect.width) - gaps, 1)
        var origin = stacked ? rect.minY : rect.minX
        var frames: [CGRect] = []
        for (index, child) in children.enumerated() {
            let length = index == children.count - 1
                ? max((stacked ? rect.maxY : rect.maxX) - origin, 1)
                : span * fractions[index] / total
            let piece = stacked
                ? CGRect(x: rect.minX, y: origin, width: rect.width, height: length)
                : CGRect(x: origin, y: rect.minY, width: length, height: rect.height)
            frames.append(piece)
            layout(child, in: piece)
            origin += length + Self.separatorGap
        }
        var live = Set<String>()
        for index in 0..<(children.count - 1) {
            let key = "\(parent.uuidString)-\(index)"
            live.insert(key)
            let divider = self.divider(key)
            let gap = Self.separatorGap
            divider.frame = stacked
                ? CGRect(x: rect.minX, y: frames[index].maxY, width: rect.width, height: gap)
                : CGRect(x: frames[index].maxX, y: rect.minY, width: gap, height: rect.height)
            divider.stacked = stacked
            divider.accessibilityIdentifier = "PaneDivider"
            let capturedSpan = span
            divider.onDrag = { [weak self] translation in
                self?.resizeSplit(parent: parent, index: index, translation: translation, span: capturedSpan)
            }
            bringSubviewToFront(divider)
        }
        for (key, divider) in dividers where key.hasPrefix(parent.uuidString) && !live.contains(key) {
            divider.removeFromSuperview()
            dividers[key] = nil
        }
    }

    private func resizeSplit(parent: UUID, index: Int, translation: CGFloat, span: CGFloat) {
        guard var fractions = splitFractions[parent], index + 1 < fractions.count else {
            return
        }
        if dragBasis[parent] == nil {
            dragBasis[parent] = fractions
        }
        guard let basis = dragBasis[parent] else {
            return
        }
        let total = basis.reduce(0, +)
        let delta = translation / span * total
        let minimum = total * 80 / max(span, 1)
        var leading = basis[index] + delta
        var trailing = basis[index + 1] - delta
        if leading < minimum {
            trailing -= minimum - leading
            leading = minimum
        }
        if trailing < minimum {
            leading -= minimum - trailing
            trailing = minimum
        }
        fractions[index] = leading
        fractions[index + 1] = trailing
        splitFractions[parent] = fractions
        setNeedsLayout()
    }

    private var dragBasis: [UUID: [CGFloat]] = [:]

    private func divider(_ key: String) -> SplitDivider {
        if let divider = dividers[key] {
            return divider
        }
        let divider = SplitDivider(frame: .zero)
        divider.onEnd = { [weak self] in
            self?.dragBasis.removeAll()
        }
        dividers[key] = divider
        addSubview(divider)
        return divider
    }

    private var chromes: [UUID: PaneChrome] = [:]

    private static let separatorGap: CGFloat = 11

    private func chrome(for pane: UUID) -> PaneChrome {
        if let chrome = chromes[pane] {
            return chrome
        }
        let chrome = PaneChrome(frame: .zero)
        chromes[pane] = chrome
        addSubview(chrome)
        return chrome
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        let heavy = traitCollection.accessibilityContrast == .high
        let split = hosts.count > 1
        for (pane, chrome) in chromes {
            chrome.apply(selected: pane == focusedPane, split: split, heavy: heavy)
        }
    }
}

/// Focus ring and dimming sit above the terminal and do not take taps.
private final class PaneChrome: UIView {
    private let dim = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        backgroundColor = .clear
        layer.cornerCurve = .continuous
        dim.backgroundColor = .black
        dim.alpha = 0
        dim.isUserInteractionEnabled = false
        addSubview(dim)
    }

    required init?(coder: NSCoder) {
        it_fatalError("PaneChrome is built in code")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        dim.frame = bounds
    }

    func apply(selected: Bool, split: Bool, heavy: Bool) {
        let marked = split && selected
        dim.alpha = split && !selected ? (heavy ? 0.42 : 0.26) : 0
        layer.borderWidth = marked ? (heavy ? 3 : 2) : 0
        layer.borderColor = UIColor.tintColor.cgColor
        layer.cornerRadius = marked ? 8 : 0
    }
}

/// Visible grabber between panes. The track is the separator; the hit area is a 44 pt control.
private final class SplitDivider: UIView {
    var stacked = false {
        didSet { setNeedsLayout() }
    }
    var onDrag: ((CGFloat) -> Void)?
    var onEnd: (() -> Void)?
    private let knob = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
        accessibilityLabel = String(localized: "Pad.Split.Divider",
                                    defaultValue: "Pane divider",
                                    comment: "Accessibility name for the control that resizes split terminal panes")
        accessibilityTraits = .adjustable
        backgroundColor = .clear
        knob.isUserInteractionEnabled = false
        knob.backgroundColor = .tertiaryLabel
        knob.layer.cornerCurve = .continuous
        addSubview(knob)
        addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(drag(_:))))
    }

    required init?(coder: NSCoder) {
        it_fatalError("SplitDivider is built in code")
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let hit = bounds.insetBy(dx: stacked ? 0 : -17, dy: stacked ? -17 : 0)
        return hit.contains(point)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let thick: CGFloat = traitCollection.accessibilityContrast == .high ? 6 : 4
        if stacked {
            knob.frame = CGRect(x: bounds.midX - 18, y: bounds.midY - thick / 2, width: 36, height: thick)
        } else {
            knob.frame = CGRect(x: bounds.midX - thick / 2, y: bounds.midY - 18, width: thick, height: 36)
        }
        knob.layer.cornerRadius = min(knob.bounds.width, knob.bounds.height) / 2
    }

    override func accessibilityIncrement() {
        onDrag?(48)
        onEnd?()
    }

    override func accessibilityDecrement() {
        onDrag?(-48)
        onEnd?()
    }

    @objc private func drag(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: superview)
        onDrag?(stacked ? translation.y : translation.x)
        if gesture.state == .ended || gesture.state == .cancelled || gesture.state == .failed {
            onEnd?()
        }
    }
}
