import Foundation

public enum TmuxLineKind: Equatable, Sendable {
    case wait
    case line
    case exit
}

public struct TmuxParsedLine: Equatable, Sendable {
    public var kind: TmuxLineKind
    public var text: String
    public var raw: Data

    public init(kind: TmuxLineKind, text: String, raw: Data) {
        self.kind = kind
        self.text = text
        self.raw = raw
    }
}

/// Line tokenizer for tmux control mode, matching `VT100TmuxParser`.
/// Control mode is entered by the DCS sequence `ESC P 1000 p`.
public final class TmuxLineParser: @unchecked Sendable {
    public var serverMayOmitEndGuardBeforeExit: Bool = true

    private var inResponseBlock = false
    private var recoveryMode: Bool
    private var currentCommandID: String?
    private var currentCommandNumber: String?
    private var line = Data()

    public init(recoveryMode: Bool = false) {
        self.recoveryMode = recoveryMode
    }

    public func feed(_ data: Data) -> [TmuxParsedLine] {
        var results: [TmuxParsedLine] = []
        var i = data.startIndex
        while i < data.endIndex {
            let byte = data[i]
            if byte == 0x0d {
                i = data.index(after: i)
                continue
            }
            if byte == 0x0a {
                if let parsed = finishLine() {
                    results.append(parsed)
                    if parsed.kind == .exit {
                        return results
                    }
                }
            } else {
                line.append(byte)
            }
            i = data.index(after: i)
        }
        return results
    }

    public func consumeDCSPreamble(_ data: Data) -> Data {
        // Strip a leading ESC P 1000 p (7-bit DCS hook) if present.
        let hook: [UInt8] = [0x1b, 0x50, 0x31, 0x30, 0x30, 0x30, 0x70]
        if data.starts(with: hook) {
            return data.dropFirst(hook.count)
        }
        return data
    }

    private func finishLine() -> TmuxParsedLine? {
        let raw = line
        line = Data()
        let command = String(data: raw, encoding: .utf8)
            ?? String(decoding: raw, as: UTF8.self)

        if recoveryMode {
            recoveryMode = false
            if !command.hasPrefix("%begin") && !command.hasPrefix("%exit") {
                return TmuxParsedLine(kind: .wait, text: "", raw: raw)
            }
        }

        var kind: TmuxLineKind = .line
        if inResponseBlock {
            if serverMayOmitEndGuardBeforeExit && command.hasPrefix("%exit") {
                kind = .exit
                inResponseBlock = false
            } else if command.hasPrefix("%end ") || command.hasPrefix("%error ") {
                let parts = command.split(separator: " ")
                if parts.count >= 3,
                   currentCommandID == String(parts[1]),
                   currentCommandNumber == String(parts[2]) {
                    inResponseBlock = false
                }
            }
        } else {
            if command.hasPrefix("%begin") {
                let parts = command.split(separator: " ")
                if parts.count >= 3 {
                    currentCommandID = String(parts[1])
                    currentCommandNumber = String(parts[2])
                    inResponseBlock = true
                }
            } else if command.hasPrefix("%exit") {
                kind = .exit
            }
        }
        return TmuxParsedLine(kind: kind, text: command, raw: raw)
    }
}
