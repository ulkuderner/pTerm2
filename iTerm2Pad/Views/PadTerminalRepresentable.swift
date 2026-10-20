import SwiftUI
import SwiftTerm
import UIKit

struct PadTerminalRepresentable: UIViewRepresentable {
    var onSend: (Data) -> Void
    var onSize: (Int, Int) -> Void
    var feed: Data?

    func makeCoordinator() -> Coordinator {
        Coordinator(onSend: onSend, onSize: onSize)
    }

    func makeUIView(context: Context) -> TerminalView {
        let view = TerminalView(frame: .zero)
        view.terminalDelegate = context.coordinator
        view.backgroundColor = .black
        context.coordinator.terminal = view
        return view
    }

    func updateUIView(_ uiView: TerminalView, context: Context) {
        context.coordinator.onSend = onSend
        context.coordinator.onSize = onSize
        if let feed, !feed.isEmpty {
            uiView.feed(byteArray: ArraySlice(feed))
        }
    }

    final class Coordinator: NSObject, TerminalViewDelegate {
        var onSend: (Data) -> Void
        var onSize: (Int, Int) -> Void
        weak var terminal: TerminalView?

        init(onSend: @escaping (Data) -> Void, onSize: @escaping (Int, Int) -> Void) {
            self.onSend = onSend
            self.onSize = onSize
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
