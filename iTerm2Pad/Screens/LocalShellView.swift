import SwiftTerm
import SwiftUI
import UIKit

struct LocalShellView: View {
    var body: some View {
        NavigationStack {
            ZshTerminalRepresentable()
                .background(Color.black)
                .navigationTitle(String(localized: "Pad.Shell.Title",
                                        defaultValue: "Shell",
                                        comment: "Navigation title of the local shell"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(Color.black, for: .navigationBar)
                .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}

private struct ZshTerminalRepresentable: UIViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> PadTerminalHost {
        let host = PadTerminalHost(frame: .zero)
        host.terminal.terminalDelegate = context.coordinator
        host.applyCurrentTheme()
        host.onSplitVertical = { TmuxSplits.split(verticalDivider: true) }
        host.onSplitHorizontal = { TmuxSplits.split(verticalDivider: false) }
        context.coordinator.attach(host)
        context.coordinator.session.start()
        host.terminal.becomeFirstResponder()
        return host
    }

    func updateUIView(_ uiView: PadTerminalHost, context: Context) {}

    static func dismantleUIView(_ uiView: PadTerminalHost, coordinator: Coordinator) {
        coordinator.session.stop()
    }

    final class Coordinator: NSObject, TerminalViewDelegate {
        let session = ZshSession()
        private var themeObserver: NSObjectProtocol?

        func attach(_ host: PadTerminalHost) {
            session.onOutput = { [weak host] data in
                host?.terminal.feed(byteArray: ArraySlice(data))
            }
            themeObserver = NotificationCenter.default.addObserver(
                forName: .terminalThemeChanged,
                object: nil,
                queue: .main
            ) { [weak host] _ in
                host?.applyCurrentTheme()
            }
        }

        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            session.send(Data(data))
        }

        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            session.resize(columns: newCols, rows: newRows)
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
    }
}
