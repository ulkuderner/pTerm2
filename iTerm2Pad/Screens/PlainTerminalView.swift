import SwiftUI
import TmuxControl

struct PlainTerminalView: View {
    var session: LiveSession
    @State private var incoming = Data()
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            PadTerminalRepresentable(
                onSend: { session.send($0) },
                onSize: { cols, rows in session.resize(columns: cols, rows: rows) },
                onSplitVertical: { TmuxSplits.split(verticalDivider: true) },
                onSplitHorizontal: { TmuxSplits.split(verticalDivider: false) },
                feed: incoming
            )
            .focused($focused)
            OptionalKeyboardAccessory(
                onKey: { special in
                    session.send(Data(byteSequence(for: special)))
                },
                onControlC: {
                    session.send(Data([0x03]))
                }
            )
        }
        .modifier(TerminalKeyboardToggle())
        .onAppear {
            focused = true
            session.onPlainOutput = { data in
                incoming = data
            }
        }
    }

    private func byteSequence(for special: TmuxKeyName.Special) -> [UInt8] {
        switch special {
        case .up: return [0x1b, 0x5b, 0x41]
        case .down: return [0x1b, 0x5b, 0x42]
        case .right: return [0x1b, 0x5b, 0x43]
        case .left: return [0x1b, 0x5b, 0x44]
        case .home: return [0x1b, 0x5b, 0x48]
        case .end: return [0x1b, 0x5b, 0x46]
        case .pageUp: return [0x1b, 0x5b, 0x35, 0x7e]
        case .pageDown: return [0x1b, 0x5b, 0x36, 0x7e]
        case .delete: return [0x1b, 0x5b, 0x33, 0x7e]
        case .escape: return [0x1b]
        case .tab: return [0x09]
        case .enter: return [0x0d]
        case .f(let n):
            return [0x1b, 0x4f, UInt8(80 + max(1, min(n, 4)) - 1)]
        }
    }
}
