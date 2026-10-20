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

    static var allCases: [TerminalTheme] { [linux, vga, tango, solarized, paper] }

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
        view.allowMouseReporting = true
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
