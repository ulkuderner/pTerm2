import Foundation

public struct TmuxWindow: Equatable, Sendable, Identifiable {
    public var id: Int
    public var name: String
    public var layout: TmuxLayoutNode?
    public var activePane: Int?

    public init(id: Int, name: String, layout: TmuxLayoutNode? = nil, activePane: Int? = nil) {
        self.id = id
        self.name = name
        self.layout = layout
        self.activePane = activePane
    }
}

/// High-level session that turns notifications into windows and pane bytes.
public final class TmuxSession: @unchecked Sendable {
    public let gateway: TmuxGateway
    public private(set) var sessionName = ""
    public private(set) var sessionID = 0
    public private(set) var windows: [TmuxWindow] = []
    public private(set) var attached = false

    public var onWindowsChanged: (() -> Void)?
    public var onPaneOutput: ((Int, Data) -> Void)?
    public var onExit: ((String?) -> Void)?

    private var pendingOutput: [Int: Data] = [:]
    private let historyLines: Int

    public init(gateway: TmuxGateway = TmuxGateway(), historyLines: Int = 1000) {
        self.gateway = gateway
        self.historyLines = historyLines
        gateway.onNotification = { [weak self] notification in
            self?.handle(notification)
        }
    }

    public func attach(writer: @escaping (String) -> Void) {
        gateway.attach(writer: writer)
        gateway.optInToNewLayouts()
        gateway.sendFireAndForget("source-file ~/.pterm2/.tmux.conf")
        gateway.displayVersion { [weak self] result in
            if case .success(let version) = result {
                self?.gateway.tmuxVersion = version.trimmingCharacters(in: .whitespacesAndNewlines)
                if let major = self?.majorVersion, major >= 2 {
                    self?.gateway.markServerModern()
                }
            }
        }
        gateway.listWindows { [weak self] result in
            self?.applyWindowList(result)
        }
    }

    public func ingest(_ data: Data) {
        gateway.ingest(data)
    }

    public func setClientSize(columns: Int, rows: Int) {
        gateway.refreshClient(columns: columns, rows: rows)
    }

    public func sendKeyName(_ name: String, to pane: Int) {
        gateway.sendKeyName(name, toPane: pane)
    }

    public func sendLiteral(_ text: String, to pane: Int) {
        gateway.sendLiteral(text, toPane: pane)
    }

    public func captureHistory(for pane: Int, completion: @escaping (Data) -> Void) {
        gateway.capturePane(pane, history: historyLines, alternate: false) { result in
            switch result {
            case .success(let text):
                completion(Data(text.utf8))
            case .failure:
                completion(Data())
            }
        }
    }

    private var majorVersion: Int? {
        guard let version = gateway.tmuxVersion else {
            return nil
        }
        let digits = version.split(separator: ".").first.flatMap { Int($0) }
        return digits
    }

    private func handle(_ notification: TmuxNotification) {
        switch notification {
        case .output(let pane, let data, _):
            if windows.contains(where: { $0.layout?.leaf(forPane: pane) != nil }) {
                onPaneOutput?(pane, data)
            } else {
                pendingOutput[pane, default: Data()].append(data)
            }
        case .layoutChange(let window, let layout, _, _):
            let parsed = TmuxLayoutParser.parsedLayout(from: layout)
            if let index = windows.firstIndex(where: { $0.id == window }) {
                windows[index].layout = parsed
            } else {
                windows.append(TmuxWindow(id: window, name: "", layout: parsed))
            }
            flushPending(in: parsed)
            onWindowsChanged?()
        case .windowAdd(let window):
            if !windows.contains(where: { $0.id == window }) {
                windows.append(TmuxWindow(id: window, name: ""))
                onWindowsChanged?()
            }
        case .windowClose(let window):
            windows.removeAll { $0.id == window }
            onWindowsChanged?()
        case .windowRenamed(let window, let name):
            if let index = windows.firstIndex(where: { $0.id == window }) {
                windows[index].name = name
                onWindowsChanged?()
            }
        case .sessionChanged(let name, let sessionID):
            sessionName = name
            self.sessionID = sessionID
            attached = true
            onWindowsChanged?()
        case .sessionRenamed(let name):
            sessionName = name
            onWindowsChanged?()
        case .exit(let reason):
            attached = false
            onExit?(reason)
        default:
            break
        }
    }

    private func applyWindowList(_ result: TmuxCommandResult) {
        guard case .success(let body) = result else {
            return
        }
        var parsed: [TmuxWindow] = []
        for line in body.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count >= 3, let id = Int(parts[0].dropFirst()) else {
                continue
            }
            let name = String(parts[1])
            let layout = TmuxLayoutParser.parsedLayout(from: String(parts[2]))
            parsed.append(TmuxWindow(id: id, name: name, layout: layout))
            flushPending(in: layout)
        }
        if !parsed.isEmpty {
            windows = parsed
            onWindowsChanged?()
        }
    }

    private func flushPending(in layout: TmuxLayoutNode?) {
        guard let layout else {
            return
        }
        for pane in layout.windowPanes() {
            if let data = pendingOutput.removeValue(forKey: pane) {
                onPaneOutput?(pane, data)
            }
        }
    }
}

