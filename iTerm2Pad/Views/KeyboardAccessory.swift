import SwiftUI
import TmuxControl

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
