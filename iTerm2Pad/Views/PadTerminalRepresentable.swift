import SwiftTerm
import SwiftUI
import UIKit

struct PadTerminalRepresentable: UIViewRepresentable {
    var onSend: (Data) -> Void
    var onSize: (Int, Int) -> Void
    var onSplitVertical: () -> Void
    var onSplitHorizontal: () -> Void
    var feed: Data?

    func makeCoordinator() -> Coordinator {
        Coordinator(onSend: onSend, onSize: onSize)
    }

    func makeUIView(context: Context) -> PadTerminalHost {
        let host = PadTerminalHost(frame: .zero)
        host.terminal.terminalDelegate = context.coordinator
        host.onSplitVertical = onSplitVertical
        host.onSplitHorizontal = onSplitHorizontal
        host.applyCurrentTheme()
        context.coordinator.terminal = host.terminal
        context.coordinator.observeTheme(host)
        host.terminal.becomeFirstResponder()
        return host
    }

    func updateUIView(_ uiView: PadTerminalHost, context: Context) {
        context.coordinator.onSend = onSend
        context.coordinator.onSize = onSize
        uiView.onSplitVertical = onSplitVertical
        uiView.onSplitHorizontal = onSplitHorizontal
        if let feed, !feed.isEmpty {
            context.coordinator.feedNew(feed, into: uiView.terminal)
        }
    }

    final class Coordinator: NSObject, TerminalViewDelegate {
        var onSend: (Data) -> Void
        var onSize: (Int, Int) -> Void
        weak var terminal: TerminalView?
        var fedCount = 0

        func feedNew(_ data: Data, into terminal: TerminalView) {
            if data.count < fedCount {
                fedCount = 0
            }
            guard data.count > fedCount else { return }
            let delta = data.subdata(in: fedCount..<data.count)
            fedCount = data.count
            terminal.feed(byteArray: ArraySlice(delta))
        }
        private var themeObserver: NSObjectProtocol?

        init(onSend: @escaping (Data) -> Void, onSize: @escaping (Int, Int) -> Void) {
            self.onSend = onSend
            self.onSize = onSize
        }

        func observeTheme(_ host: PadTerminalHost) {
            themeObserver = NotificationCenter.default.addObserver(
                forName: .terminalThemeChanged,
                object: nil,
                queue: .main
            ) { [weak host] _ in
                host?.applyCurrentTheme()
            }
        }

        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            onSend(Data(data))
        }

        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            onSize(newCols, newRows)
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
