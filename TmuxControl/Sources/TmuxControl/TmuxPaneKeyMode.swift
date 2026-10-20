import Foundation

/// Parses tmux’s `#{pane_key_mode}` format variable.
public struct TmuxPaneKeyMode: Equatable, Sendable {
    public let modifyOtherKeys: Int
    public let kittyFlags: Int

    public init(modifyOtherKeys: Int, kittyFlags: Int) {
        self.modifyOtherKeys = modifyOtherKeys
        self.kittyFlags = kittyFlags
    }

    public static func mode(for string: String?) -> TmuxPaneKeyMode? {
        guard let string, !string.isEmpty else {
            return nil
        }
        switch string {
        case "VT10x":
            return TmuxPaneKeyMode(modifyOtherKeys: 0, kittyFlags: 0)
        case "Ext 1":
            return TmuxPaneKeyMode(modifyOtherKeys: 1, kittyFlags: 0)
        case "Ext 2":
            return TmuxPaneKeyMode(modifyOtherKeys: 2, kittyFlags: 0)
        default:
            break
        }
        guard let flags = kittyFlags(in: string) else {
            return nil
        }
        return TmuxPaneKeyMode(modifyOtherKeys: -1, kittyFlags: flags)
    }

    private static func kittyFlags(in string: String) -> Int? {
        let prefix = "Kitty "
        guard string.hasPrefix(prefix) else {
            return nil
        }
        let digits = string.dropFirst(prefix.count)
        guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }) else {
            return nil
        }
        guard let flags = Int(digits), flags <= 0b11111 else {
            return nil
        }
        return flags
    }
}
