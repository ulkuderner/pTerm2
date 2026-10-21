import CoreText
import ObjectiveC
import SwiftTerm
import UIKit

enum TerminalChrome {
    static let keysKey = "ShowKeyboardAccessory"
    static let changed = Notification.Name("pTerm2.keyboardAccessoryChanged")

    static var showKeys: Bool {
        get {
            if UserDefaults.standard.object(forKey: keysKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: keysKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: keysKey)
            NotificationCenter.default.post(name: changed, object: newValue)
        }
    }
}

enum TerminalFont {
    private static let files = [
        "MesloLGS NF Regular",
        "MesloLGS NF Bold",
        "MesloLGS NF Italic",
        "MesloLGS NF Bold Italic"
    ]

    static func install() {
        for name in files {
            let url = Bundle.main.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts")
                ?? Bundle.main.url(forResource: name, withExtension: "ttf")
            guard let url else {
                continue
            }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    static func apply(to view: TerminalView, size: CGFloat = 15) {
        install()
        guard let normal = face("MesloLGS NF Regular", size),
              let bold = face("MesloLGS NF Bold", size),
              let italic = face("MesloLGS NF Italic", size),
              let boldItalic = face("MesloLGS NF Bold Italic", size) else {
            return
        }
        view.setFonts(normal: normal, bold: bold, italic: italic, boldItalic: boldItalic)
    }

    private static func face(_ resource: String, _ size: CGFloat) -> UIFont? {
        let url = Bundle.main.url(forResource: resource, withExtension: "ttf", subdirectory: "Fonts")
            ?? Bundle.main.url(forResource: resource, withExtension: "ttf")
        guard let url,
              let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let descriptor = descriptors.first else {
            return nil
        }
        return UIFont(descriptor: descriptor as UIFontDescriptor, size: size)
    }
}

final class FocusTerminalView: TerminalView {
    var onFocus: (() -> Void)?
    var onSubmit: (() -> Void)?

    override var keyCommands: [UIKeyCommand]? {
        var commands = super.keyCommands ?? []
        commands.append(UIKeyCommand(input: "\r", modifierFlags: [], action: #selector(padSubmitLine)))
        commands.append(UIKeyCommand(input: "\n", modifierFlags: [], action: #selector(padSubmitLine)))
        return commands
    }

    @objc func padSubmitLine() {
        onSubmit?()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        onFocus?()
        if !isFirstResponder {
            _ = becomeFirstResponder()
            reloadInputViews()
        }
        super.touchesBegan(touches, with: event)
    }
}

final class PadTerminalHost: UIView, TerminalViewDelegate {
    let terminal = FocusTerminalView(frame: .zero)
    var pane: UUID?
    var onBytes: ((Data) -> Void)?
    var onResize: ((Int, Int) -> Void)?
    var onSplitVertical: (() -> Void)?
    var onSplitHorizontal: (() -> Void)?
    var onClose: (() -> Void)?
    private var chromeObserver: NSObjectProtocol?
    private var themeObserver: NSObjectProtocol?
    private var builtinAccessory: UIView?

    override init(frame: CGRect) {
        super.init(frame: frame)
        terminal.frame = bounds
        terminal.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(terminal)
        backgroundColor = .black
        terminal.terminalDelegate = self
        terminal.optionAsMetaKey = false
        terminal.allowMouseReporting = false
        isAccessibilityElement = false
        terminal.isAccessibilityElement = true
        terminal.accessibilityIdentifier = "TerminalPane"
        terminal.onSubmit = { [weak self] in
            self?.submitLine()
        }
        TerminalSplitShortcut.install()
        builtinAccessory = terminal.inputAccessoryView
        applyCurrentTheme()
        applyKeyboardBar()
        chromeObserver = NotificationCenter.default.addObserver(
            forName: TerminalChrome.changed,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applyKeyboardBar()
        }
        themeObserver = NotificationCenter.default.addObserver(
            forName: .terminalThemeChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applyCurrentTheme()
        }
    }

    /// Takes the hardware keyboard back after another pane has left the window.
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if CommandLine.arguments.contains("-pterm-uitest") {
            terminal.getTerminal().setCursorStyle(.steadyBlock)
        }
    }

    func claimKeyboard() {
        guard window != nil, !terminal.isFirstResponder else {
            return
        }
        if terminal.becomeFirstResponder() {
            terminal.reloadInputViews()
        }
    }

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        if data.count == 1, data.first == 0x04 {
            onClose?()
            return
        }
        onBytes?(Data(data))
    }

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        guard newCols > 0, newRows > 0 else {
            return
        }
        onResize?(newCols, newRows)
    }

    func setTerminalTitle(source: TerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func scrolled(source: TerminalView, position: Double) {}
    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {}
    func clipboardCopy(source: TerminalView, content: Data) {
        UIPasteboard.general.string = String(data: content, encoding: .utf8)
    }
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    func bell(source: TerminalView) {}
    func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}

    required init?(coder: NSCoder) {
        it_fatalError("PadTerminalHost is built in code")
    }

    func applyCurrentTheme() {
        TerminalFont.apply(to: terminal)
        TerminalTheme.current.apply(to: terminal)
        terminal.optionAsMetaKey = false
        terminal.allowMouseReporting = false
    }

    func applyKeyboardBar() {
        if builtinAccessory == nil {
            builtinAccessory = terminal.inputAccessoryView
        }
        terminal.inputAccessoryView = TerminalChrome.showKeys ? builtinAccessory : nil
        terminal.reloadInputViews()
    }

    private var lastSubmit = Date.distantPast

    private func submitLine() {
        let now = Date()
        if now.timeIntervalSince(lastSubmit) < 0.05 {
            return
        }
        lastSubmit = now
        onBytes?(Data("\r".utf8))
    }

    func handleKey(_ presses: Set<UIPress>) -> Bool {
        for press in presses {
            guard let key = press.key else {
                continue
            }
            let flags = key.modifierFlags
            let plain = key.charactersIgnoringModifiers.lowercased()
            let isD = key.keyCode == .keyboardD || plain == "d"
            if flags.contains(.command), isD {
                if flags.contains(.shift) {
                    onSplitHorizontal?()
                } else {
                    onSplitVertical?()
                }
                return true
            }
            if flags.contains(.command), !flags.contains(.control), plain == "c" {
                terminal.copy(nil)
                return true
            }
            if flags.contains(.command), !flags.contains(.control), plain == "v" {
                terminal.paste(nil)
                return true
            }
            if key.keyCode == .keyboardReturn || key.characters == "\r" || key.characters == "\n" {
                submitLine()
                return true
            }
            let isControlD = key.characters == "\u{4}" || (flags.contains(.control) && isD && !flags.contains(.command))
            if isControlD, let onClose {
                onClose()
                return true
            }
        }
        return false
    }
}

private enum TerminalSplitShortcut {
    static var installed = false

    static func install() {
        guard !installed else {
            return
        }
        installed = true
        let original = class_getInstanceMethod(TerminalView.self, #selector(UIResponder.pressesBegan(_:with:)))
        let hooked = class_getInstanceMethod(TerminalView.self, #selector(TerminalView.pad_pressesBegan(_:with:)))
        if let original, let hooked {
            method_exchangeImplementations(original, hooked)
        }
        let erase = class_getInstanceMethod(TerminalView.self, #selector(UIKeyInput.deleteBackward))
        let eraseHook = class_getInstanceMethod(TerminalView.self, #selector(TerminalView.pad_deleteBackward))
        if let erase, let eraseHook {
            method_exchangeImplementations(erase, eraseHook)
        }
    }
}

extension TerminalView {
    /// Software-keyboard delete reaches here with an empty local buffer. Send erase and do not insert a space.
    @objc func pad_deleteBackward() {
        send([0x7f])
    }

    @objc func pad_pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var view: UIView? = self
        while let current = view {
            if let host = current as? PadTerminalHost, host.handleKey(presses) {
                return
            }
            view = current.superview
        }
        pad_pressesBegan(presses, with: event)
    }
}
