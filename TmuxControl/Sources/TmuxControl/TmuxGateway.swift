import Foundation

/// Command queue and notification dispatch for tmux control mode.
/// Mirrors the AppKit-free core of `TmuxGateway`.
public final class TmuxGateway: @unchecked Sendable {
    public var acceptNotifications = true
    public var serverEncodesAllKeys = false
    public var tmuxVersion: String?

    private let parser = TmuxLineParser()
    private var nextCommandID = 1
    private var nextCommandNumber = 0
    private var current: (command: TmuxPendingCommand, body: String)?
    private var queue: [(TmuxPendingCommand, (TmuxCommandResult) -> Void)] = []
    private var outgoing: ((String) -> Void)?
    public var onNotification: ((TmuxNotification) -> Void)?

    public init() {}

    public func attach(writer: @escaping (String) -> Void) {
        outgoing = writer
    }

    public func markServerModern() {
        parser.serverMayOmitEndGuardBeforeExit = false
    }

    public func ingest(_ data: Data) {
        let payload = parser.consumeDCSPreamble(data)
        for line in parser.feed(payload) {
            handle(line)
        }
    }

    public func send(_ command: String,
                     tolerateErrors: Bool = false,
                     completion: @escaping (TmuxCommandResult) -> Void) {
        let pending = TmuxPendingCommand(
            id: nextCommandID,
            number: nextCommandNumber,
            text: command,
            tolerateErrors: tolerateErrors
        )
        nextCommandID += 1
        nextCommandNumber += 1
        queue.append((pending, completion))
        flush()
    }

    public func sendFireAndForget(_ command: String) {
        send(command, tolerateErrors: true) { _ in }
    }

    public func refreshClient(columns: Int, rows: Int) {
        sendFireAndForget("refresh-client -C \(columns),\(rows)")
    }

    public func refreshClient(window: Int, columns: Int, rows: Int) {
        sendFireAndForget("refresh-client -C @\(window):\(columns)x\(rows)")
    }

    public func optInToNewLayouts() {
        sendFireAndForget("refresh-client -f new-layouts")
    }

    public func sendKeyName(_ name: String, toPane pane: Int) {
        let escaped = name.replacingOccurrences(of: "'", with: "'\\''")
        sendFireAndForget("send -t %\(pane) '\(escaped)'")
    }

    public func sendLiteral(_ string: String, toPane pane: Int) {
        let escaped = string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "'\\''")
        sendFireAndForget("send -lt %\(pane) '\(escaped)'")
    }

    public func sendBytes(_ data: Data, toPane pane: Int) {
        let hex = data.map { String(format: "0x%02x", $0) }.joined(separator: " ")
        sendFireAndForget("send -H -t %\(pane) \(hex)")
    }

    public func capturePane(_ pane: Int, history: Int, alternate: Bool, completion: @escaping (TmuxCommandResult) -> Void) {
        let alt = alternate ? " -a" : ""
        send("capture-pane -peqJ\(alt) -t %\(pane) -S -\(history)", completion: completion)
    }

    public func listPanes(completion: @escaping (TmuxCommandResult) -> Void) {
        send("list-panes -F \"\(TmuxStateParser.format)\"", completion: completion)
    }

    public func listWindows(completion: @escaping (TmuxCommandResult) -> Void) {
        send("list-windows -F \"#{window_id} #{window_name} #{window_layout}\"", completion: completion)
    }

    public func newWindow() {
        sendFireAndForget("new-window")
    }

    public func splitWindow(horizontal: Bool, target pane: Int) {
        let flag = horizontal ? "-h" : "-v"
        sendFireAndForget("split-window \(flag) -c \"#{pane_current_path}\" -t %\(pane)")
    }

    public func selectPane(_ pane: Int) {
        sendFireAndForget("select-pane -t %\(pane)")
    }

    public func selectWindow(_ window: Int) {
        sendFireAndForget("select-window -t @\(window)")
    }

    public func detach() {
        sendFireAndForget("detach")
    }

    public func displayVersion(completion: @escaping (TmuxCommandResult) -> Void) {
        send("display-message -p \"#{version}\"", completion: completion)
    }

    private func flush() {
        guard current == nil, let next = queue.first, let outgoing else {
            return
        }
        current = (next.0, "")
        outgoing(next.0.text + "\n")
    }

    private func handle(_ line: TmuxParsedLine) {
        switch line.kind {
        case .wait:
            return
        case .exit:
            finishCurrent(error: false)
            onNotification?(.exit(reason: line.text))
            return
        case .line:
            break
        }
        let command = line.text
        if let current {
            let end = "%end \(current.command.id) \(current.command.number)"
            let error = "%error \(current.command.id) \(current.command.number)"
            if command.hasPrefix(end) {
                finishCurrent(error: false)
                return
            }
            if command.hasPrefix(error) {
                finishCurrent(error: true)
                return
            }
            let begin = "%begin \(current.command.id) \(current.command.number)"
            if command.hasPrefix(begin) {
                return
            }
            if !self.current!.body.isEmpty {
                self.current!.body.append("\n")
            }
            self.current!.body.append(command)
            return
        }
        guard acceptNotifications || command.hasPrefix("%session-changed") || command.hasPrefix("%exit") else {
            return
        }
        if let notification = parseNotification(command, raw: line.raw) {
            onNotification?(notification)
        }
    }

    private func finishCurrent(error: Bool) {
        guard let current else {
            return
        }
        let result: TmuxCommandResult = error
            ? .failure(current.body)
            : .success(current.body)
        if !queue.isEmpty {
            let completion = queue.removeFirst().1
            completion(result)
        }
        self.current = nil
        flush()
    }

    private func parseNotification(_ command: String, raw: Data) -> TmuxNotification? {
        if command.hasPrefix("%output ") {
            return parseOutput(raw, extended: false)
        }
        if command.hasPrefix("%extended-output ") {
            return parseOutput(raw, extended: true)
        }
        if command.hasPrefix("%layout-change ") {
            return parseLayoutChange(command)
        }
        if command.hasPrefix("%window-add") {
            return parseWindowID(command, prefix: "%window-add").map { .windowAdd(window: $0) }
        }
        if command.hasPrefix("%window-close") || command.hasPrefix("%unlinked-window-close") {
            return parseWindowID(command, prefix: command.split(separator: " ").first.map(String.init) ?? "").map {
                .windowClose(window: $0)
            }
        }
        if command.hasPrefix("%window-renamed") || command.hasPrefix("%unlinked-window-renamed") {
            return parseWindowRenamed(command)
        }
        if command.hasPrefix("%session-changed") {
            return parseSessionChanged(command)
        }
        if command.hasPrefix("%session-renamed") {
            let name = command.split(separator: " ", maxSplits: 1).dropFirst().first.map(String.init) ?? ""
            return .sessionRenamed(name: name)
        }
        if command.hasPrefix("%sessions-changed") {
            return .sessionsChanged
        }
        if command.hasPrefix("%window-pane-changed") {
            return parseWindowPaneChanged(command)
        }
        if command.hasPrefix("%session-window-changed") {
            return parseWindowID(command, prefix: "%session-window-changed").map {
                .sessionWindowChanged(window: $0)
            }
        }
        if command.hasPrefix("%pause") {
            if let pane = parsePercentID(command, prefix: "%pause") {
                return .pause(pane: pane)
            }
        }
        if command.hasPrefix("%exit") {
            return .exit(reason: command)
        }
        if command.hasPrefix("%noop")
            || command.hasPrefix("%continue")
            || command.hasPrefix("%unlinked-window-add")
            || command.hasPrefix("%pane-mode-changed")
            || command.hasPrefix("%client-")
            || command.hasPrefix("%subscription-changed")
            || command.hasPrefix("%paste-buffer-changed") {
            return .unhandled(command)
        }
        return .unhandled(command)
    }

    private func parseOutput(_ raw: Data, extended: Bool) -> TmuxNotification? {
        guard let nulTerminated = String(data: raw + Data([0]), encoding: .isoLatin1) else {
            return nil
        }
        let bytes = Array(nulTerminated.utf8)
        guard let firstSpace = bytes.firstIndex(of: 0x20) else {
            return nil
        }
        var i = firstSpace + 1
        guard i < bytes.count, bytes[i] == 0x25 else {
            return nil
        }
        i += 1
        var pane = 0
        while i < bytes.count, bytes[i] >= 0x30, bytes[i] <= 0x39 {
            pane = pane * 10 + Int(bytes[i] - 0x30)
            i += 1
        }
        guard i < bytes.count, bytes[i] == 0x20 else {
            return nil
        }
        i += 1
        var latency: Double?
        if extended {
            let start = i
            while i < bytes.count, bytes[i] != 0x20, bytes[i] != 0 {
                i += 1
            }
            let token = String(bytes: bytes[start..<i], encoding: .ascii)
            latency = token.flatMap(Double.init)
            if i < bytes.count, bytes[i] == 0x20 {
                i += 1
            }
            if let colon = bytes[i...].firstIndex(of: 0x3a) {
                i = colon + 1
                if i < bytes.count, bytes[i] == 0x20 {
                    i += 1
                }
            }
        }
        let payload = Data(bytes[i...].prefix { $0 != 0 })
        return .output(pane: pane, data: TmuxEscapedOutput.decode(payload), latency: latency)
    }

    private func parseLayoutChange(_ command: String) -> TmuxNotification? {
        let rest = command.dropFirst("%layout-change ".count)
        guard rest.first == "@" else {
            return nil
        }
        let parts = rest.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: false)
        guard let first = parts.first, let window = Int(first.dropFirst()) else {
            return nil
        }
        let layout = parts.count > 1 ? String(parts[1]) : ""
        let visible = parts.count > 2 ? String(parts[2]) : nil
        let zoomed = parts.count > 3 ? parts[3].contains("Z") : nil
        return .layoutChange(window: window, layout: layout, visibleLayout: visible, zoomed: zoomed)
    }

    private func parseWindowID(_ command: String, prefix: String) -> Int? {
        let rest = command.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        guard rest.hasPrefix("@") else {
            return Int(rest)
        }
        return Int(rest.dropFirst())
    }

    private func parsePercentID(_ command: String, prefix: String) -> Int? {
        let rest = command.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        guard rest.hasPrefix("%") else {
            return Int(rest)
        }
        return Int(rest.dropFirst())
    }

    private func parseWindowRenamed(_ command: String) -> TmuxNotification? {
        let parts = command.split(separator: " ", maxSplits: 2)
        guard parts.count >= 3, let window = Int(parts[1].dropFirst()) else {
            return nil
        }
        return .windowRenamed(window: window, name: String(parts[2]))
    }

    private func parseSessionChanged(_ command: String) -> TmuxNotification? {
        let parts = command.split(separator: " ")
        guard parts.count >= 3, let sessionID = Int(parts[1]) else {
            return nil
        }
        return .sessionChanged(name: String(parts[2]), sessionID: sessionID)
    }

    private func parseWindowPaneChanged(_ command: String) -> TmuxNotification? {
        let parts = command.split(separator: " ")
        guard parts.count >= 3,
              let window = Int(parts[1].dropFirst()),
              let pane = Int(parts[2].dropFirst()) else {
            return nil
        }
        return .windowPaneChanged(window: window, pane: pane)
    }
}
