import Darwin
import Foundation
import SwiftTerm
import UIKit

/// Screen themes. The 16 entries are the ANSI palette, dark colors first.
struct TerminalTheme: Identifiable, Equatable, CaseIterable {
    static let storageKey = "TerminalTheme"

    let id: String
    let title: String
    let foreground: UIColor
    let background: UIColor
    let cursor: UIColor
    let palette: [Color]

    static let linux = TerminalTheme(
        id: "linux",
        title: "Linux",
        foreground: ui(170, 170, 170),
        background: .black,
        cursor: ui(85, 255, 85),
        palette: [
            c(0, 0, 0), c(170, 0, 0), c(0, 170, 0), c(170, 85, 0),
            c(0, 0, 170), c(170, 0, 170), c(0, 170, 170), c(170, 170, 170),
            c(85, 85, 85), c(255, 85, 85), c(85, 255, 85), c(255, 255, 85),
            c(85, 85, 255), c(255, 85, 255), c(85, 255, 255), c(255, 255, 255)
        ]
    )

    static let vga = TerminalTheme(
        id: "vga",
        title: "VGA",
        foreground: .white,
        background: .black,
        cursor: .white,
        palette: linux.palette
    )

    static let tango = TerminalTheme(
        id: "tango",
        title: "Tango",
        foreground: ui(211, 215, 207),
        background: ui(46, 52, 54),
        cursor: ui(252, 233, 79),
        palette: [
            c(46, 52, 54), c(204, 0, 0), c(78, 154, 6), c(196, 160, 0),
            c(52, 101, 164), c(117, 80, 123), c(6, 152, 154), c(211, 215, 207),
            c(85, 87, 83), c(239, 41, 41), c(138, 226, 52), c(252, 233, 79),
            c(114, 159, 207), c(173, 127, 168), c(52, 226, 226), c(238, 238, 236)
        ]
    )

    static let solarized = TerminalTheme(
        id: "solarized",
        title: "Solarized",
        foreground: ui(131, 148, 150),
        background: ui(0, 43, 54),
        cursor: ui(133, 153, 0),
        palette: [
            c(7, 54, 66), c(220, 50, 47), c(133, 153, 0), c(181, 137, 0),
            c(38, 139, 210), c(211, 54, 130), c(42, 161, 152), c(238, 232, 213),
            c(0, 43, 54), c(203, 75, 22), c(88, 110, 117), c(101, 123, 131),
            c(131, 148, 150), c(108, 113, 196), c(147, 161, 161), c(253, 246, 227)
        ]
    )

    static let dracula = TerminalTheme(
        id: "dracula",
        title: "Dracula",
        foreground: ui(248, 248, 242),
        background: ui(40, 42, 54),
        cursor: ui(248, 248, 242),
        palette: [
            c(33, 34, 44), c(255, 85, 85), c(80, 250, 123), c(241, 250, 140),
            c(189, 147, 249), c(255, 121, 198), c(139, 233, 253), c(248, 248, 242),
            c(98, 114, 164), c(255, 110, 110), c(105, 255, 148), c(255, 255, 165),
            c(214, 172, 255), c(255, 146, 223), c(164, 255, 255), c(255, 255, 255)
        ]
    )

    static let nord = TerminalTheme(
        id: "nord",
        title: "Nord",
        foreground: ui(216, 222, 233),
        background: ui(46, 52, 64),
        cursor: ui(216, 222, 233),
        palette: [
            c(59, 66, 82), c(191, 97, 106), c(163, 190, 140), c(235, 203, 139),
            c(129, 161, 193), c(180, 142, 173), c(136, 192, 208), c(229, 233, 240),
            c(76, 86, 106), c(191, 97, 106), c(163, 190, 140), c(235, 203, 139),
            c(129, 161, 193), c(180, 142, 173), c(143, 188, 187), c(236, 239, 244)
        ]
    )

    static let tokyo = TerminalTheme(
        id: "tokyo",
        title: "Tokyo Night",
        foreground: ui(192, 202, 245),
        background: ui(26, 27, 38),
        cursor: ui(192, 202, 245),
        palette: [
            c(21, 22, 30), c(247, 118, 142), c(158, 206, 106), c(224, 175, 104),
            c(122, 162, 247), c(187, 154, 247), c(125, 207, 255), c(169, 177, 214),
            c(65, 72, 104), c(247, 118, 142), c(158, 206, 106), c(224, 175, 104),
            c(122, 162, 247), c(187, 154, 247), c(125, 207, 255), c(192, 202, 245)
        ]
    )

    static let catppuccin = TerminalTheme(
        id: "catppuccin",
        title: "Catppuccin",
        foreground: ui(205, 214, 244),
        background: ui(30, 30, 46),
        cursor: ui(245, 224, 220),
        palette: [
            c(69, 71, 90), c(243, 139, 168), c(166, 227, 161), c(249, 226, 175),
            c(137, 180, 250), c(245, 194, 231), c(148, 226, 213), c(186, 194, 222),
            c(88, 91, 112), c(243, 139, 168), c(166, 227, 161), c(249, 226, 175),
            c(137, 180, 250), c(245, 194, 231), c(148, 226, 213), c(166, 173, 200)
        ]
    )

    static let one = TerminalTheme(
        id: "one",
        title: "One Dark",
        foreground: ui(171, 178, 191),
        background: ui(40, 44, 52),
        cursor: ui(82, 139, 255),
        palette: [
            c(40, 44, 52), c(224, 108, 117), c(152, 195, 121), c(229, 192, 123),
            c(97, 175, 239), c(198, 120, 221), c(86, 182, 194), c(171, 178, 191),
            c(92, 99, 112), c(224, 108, 117), c(152, 195, 121), c(229, 192, 123),
            c(97, 175, 239), c(198, 120, 221), c(86, 182, 194), c(255, 255, 255)
        ]
    )

    static let ocean = TerminalTheme(
        id: "ocean",
        title: "Ocean",
        foreground: ui(197, 228, 234),
        background: ui(12, 28, 40),
        cursor: ui(88, 196, 220),
        palette: [
            c(8, 20, 30), c(230, 92, 92), c(92, 196, 140), c(232, 196, 104),
            c(88, 168, 230), c(176, 128, 214), c(72, 196, 204), c(197, 228, 234),
            c(70, 96, 112), c(255, 128, 128), c(128, 230, 170), c(255, 220, 140),
            c(128, 196, 255), c(210, 160, 240), c(120, 230, 236), c(255, 255, 255)
        ]
    )

    static let paper = TerminalTheme(
        id: "paper",
        title: "Paper",
        foreground: ui(32, 32, 32),
        background: ui(253, 246, 227),
        cursor: ui(38, 139, 210),
        palette: [
            c(7, 54, 66), c(220, 50, 47), c(133, 153, 0), c(181, 137, 0),
            c(38, 139, 210), c(211, 54, 130), c(42, 161, 152), c(238, 232, 213),
            c(0, 43, 54), c(203, 75, 22), c(88, 110, 117), c(101, 123, 131),
            c(131, 148, 150), c(108, 113, 196), c(147, 161, 161), c(253, 246, 227)
        ]
    )

    static var allCases: [TerminalTheme] {
        [linux, dracula, nord, tokyo, catppuccin, one, ocean, solarized, tango, paper, vga]
    }

    static var current: TerminalTheme {
        get {
            let stored = UserDefaults.standard.string(forKey: storageKey) ?? linux.id
            return allCases.first { $0.id == stored } ?? .linux
        }
        set {
            UserDefaults.standard.set(newValue.id, forKey: storageKey)
            NotificationCenter.default.post(name: .terminalThemeChanged, object: newValue.id)
        }
    }

    func apply(to view: TerminalView) {
        view.installColors(palette)
        view.nativeForegroundColor = foreground
        view.nativeBackgroundColor = background
        view.backgroundColor = background
        view.caretColor = cursor
        view.allowMouseReporting = false
    }

    private static func c(_ red: Int, _ green: Int, _ blue: Int) -> Color {
        Color(red: UInt16(red) * 257, green: UInt16(green) * 257, blue: UInt16(blue) * 257)
    }

    private static func ui(_ red: Int, _ green: Int, _ blue: Int) -> UIColor {
        UIColor(red: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: 1)
    }
}

extension Notification.Name {
    static let terminalThemeChanged = Notification.Name("pTerm2.terminalThemeChanged")
}

/// Splits the tmux pane under the cursor. Command-D is a vertical divider
/// (panes side by side). Command-Shift-D is a horizontal divider (stacked).
enum TmuxSplits {
    static func split(verticalDivider: Bool) {
        let flag = verticalDivider ? "-h" : "-v"
        let binary = FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/tmux")
            ? "/opt/homebrew/bin/tmux"
            : "/usr/bin/tmux"
        let command = [binary, "split-window", flag, "-c", "#{pane_current_path}"]
        let pointers = command.map { strdup($0) }
        var argv: [UnsafeMutablePointer<CChar>?] = pointers
        argv.append(nil)
        defer { argv.forEach { free($0) } }
        var pid: pid_t = 0
        argv.withUnsafeMutableBufferPointer { buffer in
            _ = posix_spawn(&pid, binary, nil, nil, buffer.baseAddress, nil)
        }
    }
}
