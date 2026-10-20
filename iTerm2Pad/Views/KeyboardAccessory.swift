import SwiftUI
import TmuxControl

struct TerminalKeyboardToggle: ViewModifier {
    @State private var shown = TerminalChrome.showKeys

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(shown
                           ? String(localized: "Pad.Key.Hide",
                                    defaultValue: "Hide Keys",
                                    comment: "Hides the Esc and arrow bar under the terminal")
                           : String(localized: "Pad.Key.Show",
                                    defaultValue: "Show Keys",
                                    comment: "Shows the Esc and arrow bar under the terminal")) {
                        TerminalChrome.showKeys.toggle()
                        shown = TerminalChrome.showKeys
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: TerminalChrome.changed)) { _ in
                shown = TerminalChrome.showKeys
            }
    }
}

struct OptionalKeyboardAccessory: View {
    var onKey: (TmuxKeyName.Special) -> Void
    var onControlC: () -> Void
    @State private var shown = TerminalChrome.showKeys

    var body: some View {
        Group {
            if shown {
                KeyboardAccessory(onKey: onKey, onControlC: onControlC)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: TerminalChrome.changed)) { _ in
            shown = TerminalChrome.showKeys
        }
    }
}

struct KeyboardAccessory: View {
    var onKey: (TmuxKeyName.Special) -> Void
    var onControlC: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                key(String(localized: "Pad.Key.Esc", defaultValue: "Esc", comment: "Escape key on the terminal accessory bar")) {
                    onKey(.escape)
                }
                key("Ctrl-C", action: onControlC)
                key(String(localized: "Pad.Key.Tab", defaultValue: "Tab", comment: "Tab key on the terminal accessory bar")) {
                    onKey(.tab)
                }
                key("↑") { onKey(.up) }
                key("↓") { onKey(.down) }
                key("←") { onKey(.left) }
                key("→") { onKey(.right) }
                key(String(localized: "Pad.Key.Home", defaultValue: "Home", comment: "Home key on the terminal accessory bar")) {
                    onKey(.home)
                }
                key(String(localized: "Pad.Key.End", defaultValue: "End", comment: "End key on the terminal accessory bar")) {
                    onKey(.end)
                }
            }
            .padding(.horizontal, 8)
        }
        .frame(minHeight: 44)
        .background(.bar)
    }

    private func key(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(.footnote, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
        }
        .buttonStyle(.bordered)
        .frame(minHeight: 44)
    }
}
