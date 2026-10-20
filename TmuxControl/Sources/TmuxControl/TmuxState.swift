import Foundation

public struct TmuxPaneState: Equatable, Sendable {
    public var paneID: Int
    public var alternateOn: Int
    public var alternateSavedX: Int
    public var alternateSavedY: Int
    public var cursorX: Int
    public var cursorY: Int
    public var scrollRegionUpper: Int
    public var scrollRegionLower: Int
    public var tabstops: [Int]
    public var cursorVisible: Bool
    public var insertMode: Bool
    public var applicationCursor: Bool
    public var applicationKeypad: Bool
    public var wrap: Bool
    public var mouseStandard: Bool
    public var mouseButton: Bool
    public var mouseAny: Bool
    public var mouseUTF8: Bool
    public var mouseSGR: Bool
    public var bracketedPaste: Bool
    public var paneKeyMode: String?

    public init(paneID: Int = -1,
                alternateOn: Int = 0,
                alternateSavedX: Int = 0,
                alternateSavedY: Int = 0,
                cursorX: Int = 0,
                cursorY: Int = 0,
                scrollRegionUpper: Int = 0,
                scrollRegionLower: Int = 0,
                tabstops: [Int] = [],
                cursorVisible: Bool = true,
                insertMode: Bool = false,
                applicationCursor: Bool = false,
                applicationKeypad: Bool = false,
                wrap: Bool = true,
                mouseStandard: Bool = false,
                mouseButton: Bool = false,
                mouseAny: Bool = false,
                mouseUTF8: Bool = false,
                mouseSGR: Bool = false,
                bracketedPaste: Bool = false,
                paneKeyMode: String? = nil) {
        self.paneID = paneID
        self.alternateOn = alternateOn
        self.alternateSavedX = alternateSavedX
        self.alternateSavedY = alternateSavedY
        self.cursorX = cursorX
        self.cursorY = cursorY
        self.scrollRegionUpper = scrollRegionUpper
        self.scrollRegionLower = scrollRegionLower
        self.tabstops = tabstops
        self.cursorVisible = cursorVisible
        self.insertMode = insertMode
        self.applicationCursor = applicationCursor
        self.applicationKeypad = applicationKeypad
        self.wrap = wrap
        self.mouseStandard = mouseStandard
        self.mouseButton = mouseButton
        self.mouseAny = mouseAny
        self.mouseUTF8 = mouseUTF8
        self.mouseSGR = mouseSGR
        self.bracketedPaste = bracketedPaste
        self.paneKeyMode = paneKeyMode
    }
}

public enum TmuxStateParser {
    /// Format string for `list-panes -F`, matching the macOS client.
    public static let format: String = [
        "pane_id=#{pane_id}",
        "alternate_on=#{alternate_on}",
        "alternate_saved_x=#{alternate_saved_x}",
        "alternate_saved_y=#{alternate_saved_y}",
        "cursor_x=#{cursor_x}",
        "cursor_y=#{cursor_y}",
        "scroll_region_upper=#{scroll_region_upper}",
        "scroll_region_lower=#{scroll_region_lower}",
        "pane_tabs=#{pane_tabs}",
        "cursor_flag=#{cursor_flag}",
        "insert_flag=#{insert_flag}",
        "keypad_cursor_flag=#{keypad_cursor_flag}",
        "keypad_flag=#{keypad_flag}",
        "wrap_flag=#{wrap_flag}",
        "mouse_standard_flag=#{mouse_standard_flag}",
        "mouse_button_flag=#{mouse_button_flag}",
        "mouse_any_flag=#{mouse_any_flag}",
        "mouse_utf8_flag=#{mouse_utf8_flag}",
        "mouse_sgr_flag=#{mouse_sgr_flag}",
        "bracket_paste_flag=#{bracket_paste_flag}",
        "pane_key_mode=#{pane_key_mode}"
    ].joined(separator: "\t")

    public static func parsedState(from lines: String,
                                   forPane paneID: Int,
                                   workAroundTabBug: Bool = false) -> TmuxPaneState {
        for line in lines.split(separator: "\n", omittingEmptySubsequences: false) {
            let dict = dictionary(for: String(line), workAroundTabBug: workAroundTabBug)
            if dict.paneID == paneID {
                return dict
            }
        }
        return TmuxPaneState()
    }

    public static func dictionary(for state: String, workAroundTabBug: Bool) -> TmuxPaneState {
        var fields = state.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        if fields.count == 1 && workAroundTabBug {
            fields = state.components(separatedBy: "\\t")
        }
        var result = TmuxPaneState()
        for kvp in fields {
            guard let eq = kvp.firstIndex(of: "=") else {
                continue
            }
            let key = String(kvp[..<eq])
            let value = String(kvp[kvp.index(after: eq)...])
            if key.isEmpty {
                continue
            }
            apply(key: key, value: value, to: &result)
        }
        return result
    }

    private static func apply(key: String, value: String, to result: inout TmuxPaneState) {
        switch key {
        case "pane_id":
            if value.hasPrefix("%"), value.count > 1 {
                result.paneID = Int(value.dropFirst()) ?? -1
            } else {
                result.paneID = -1
            }
        case "alternate_on":
            result.alternateOn = Int(value) ?? 0
        case "alternate_saved_x":
            result.alternateSavedX = Int(value) ?? 0
        case "alternate_saved_y":
            result.alternateSavedY = Int(value) ?? 0
        case "cursor_x":
            result.cursorX = Int(value) ?? 0
        case "cursor_y":
            result.cursorY = Int(value) ?? 0
        case "scroll_region_upper":
            result.scrollRegionUpper = Int(value) ?? 0
        case "scroll_region_lower":
            result.scrollRegionLower = Int(value) ?? 0
        case "pane_tabs":
            result.tabstops = value.split(separator: ",").compactMap { Int($0) }
        case "cursor_flag":
            result.cursorVisible = (Int(value) ?? 1) != 0
        case "insert_flag":
            result.insertMode = (Int(value) ?? 0) != 0
        case "keypad_cursor_flag":
            result.applicationCursor = (Int(value) ?? 0) != 0
        case "keypad_flag":
            result.applicationKeypad = (Int(value) ?? 0) != 0
        case "wrap_flag":
            result.wrap = (Int(value) ?? 1) != 0
        case "mouse_standard_flag":
            result.mouseStandard = (Int(value) ?? 0) != 0
        case "mouse_button_flag":
            result.mouseButton = (Int(value) ?? 0) != 0
        case "mouse_any_flag":
            result.mouseAny = (Int(value) ?? 0) != 0
        case "mouse_utf8_flag":
            result.mouseUTF8 = (Int(value) ?? 0) != 0
        case "mouse_sgr_flag":
            result.mouseSGR = (Int(value) ?? 0) != 0
        case "bracket_paste_flag":
            result.bracketedPaste = (Int(value) ?? 0) != 0
        case "pane_key_mode":
            result.paneKeyMode = value.isEmpty ? nil : value
        default:
            break
        }
    }
}
