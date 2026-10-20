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

final class PadTerminalHost: UIView {
    let terminal = TerminalView(frame: .zero)
    var onSplitVertical: (() -> Void)?
    var onSplitHorizontal: (() -> Void)?
    private var chromeObserver: NSObjectProtocol?
    private var builtinAccessory: UIView?

    override init(frame: CGRect) {
        super.init(frame: frame)
        terminal.frame = bounds
        terminal.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(terminal)
        backgroundColor = .black
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
    }

    required init?(coder: NSCoder) {
        it_fatalError("PadTerminalHost is built in code")
    }

    func applyCurrentTheme() {
        TerminalFont.apply(to: terminal)
        TerminalTheme.current.apply(to: terminal)
    }

    func applyKeyboardBar() {
        if builtinAccessory == nil {
            builtinAccessory = terminal.inputAccessoryView
        }
        terminal.inputAccessoryView = TerminalChrome.showKeys ? builtinAccessory : nil
        terminal.reloadInputViews()
    }

    func handleSplit(_ presses: Set<UIPress>) -> Bool {
        for press in presses {
            guard let key = press.key, key.modifierFlags.contains(.command) else {
                continue
            }
            if key.charactersIgnoringModifiers.lowercased() == "d" {
                if key.modifierFlags.contains(.shift) {
                    onSplitHorizontal?()
                } else {
                    onSplitVertical?()
                }
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
        guard let original, let hooked else {
            return
        }
        method_exchangeImplementations(original, hooked)
    }
}

extension TerminalView {
    @objc func pad_pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var view: UIView? = self
        while let current = view {
            if let host = current as? PadTerminalHost, host.handleSplit(presses) {
                return
            }
            view = current.superview
        }
        pad_pressesBegan(presses, with: event)
    }
}
