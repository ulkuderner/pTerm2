import Foundation

public enum TmuxNotification: Equatable, Sendable {
    case output(pane: Int, data: Data, latency: Double?)
    case layoutChange(window: Int, layout: String, visibleLayout: String?, zoomed: Bool?)
    case windowAdd(window: Int)
    case windowClose(window: Int)
    case windowRenamed(window: Int, name: String)
    case sessionChanged(name: String, sessionID: Int)
    case sessionRenamed(name: String)
    case sessionsChanged
    case windowPaneChanged(window: Int, pane: Int)
    case sessionWindowChanged(window: Int)
    case pause(pane: Int)
    case exit(reason: String?)
    case unhandled(String)
}

public enum TmuxCommandResult: Sendable {
    case success(String)
    case failure(String)
}

public struct TmuxPendingCommand: Sendable {
    public let id: Int
    public let number: Int
    public let text: String
    public let tolerateErrors: Bool

    public init(id: Int, number: Int, text: String, tolerateErrors: Bool = false) {
        self.id = id
        self.number = number
        self.text = text
        self.tolerateErrors = tolerateErrors
    }
}
