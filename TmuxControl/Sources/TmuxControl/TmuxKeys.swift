import Foundation

/// Named keys for `send-keys` on tmux 3.2+. Older servers use the byte path.
public enum TmuxKeyName {
    public static func name(for characters: String, modifiers: TmuxKeyModifiers) -> String? {
        if modifiers.contains(.control), characters.count == 1, let scalar = characters.unicodeScalars.first {
            let value = scalar.value
            if value >= 64 && value <= 95 {
                return "C-\(Character(UnicodeScalar(value)!))"
            }
            if value >= 97 && value <= 122 {
                return "C-\(Character(UnicodeScalar(value - 32)!))"
            }
        }
        switch characters {
        case "\u{1b}":
            return "Escape"
        case "\t":
            return "Tab"
        case "\r", "\n":
            return "Enter"
        case "\u{7f}":
            return "BSpace"
        default:
            break
        }
        return nil
    }

    public static func namedSpecial(_ key: Special) -> String {
        switch key {
        case .up: return "Up"
        case .down: return "Down"
        case .left: return "Left"
        case .right: return "Right"
        case .home: return "Home"
        case .end: return "End"
        case .pageUp: return "PPage"
        case .pageDown: return "NPage"
        case .delete: return "DC"
        case .escape: return "Escape"
        case .tab: return "Tab"
        case .enter: return "Enter"
        case .f(let n): return "F\(n)"
        }
    }

    public enum Special: Equatable, Sendable {
        case up, down, left, right
        case home, end, pageUp, pageDown, delete
        case escape, tab, enter
        case f(Int)
    }
}

public struct TmuxKeyModifiers: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let control = TmuxKeyModifiers(rawValue: 1 << 0)
    public static let option = TmuxKeyModifiers(rawValue: 1 << 1)
    public static let shift = TmuxKeyModifiers(rawValue: 1 << 2)
}
