import SwiftTerm
import UIKit

/// Hosts a SwiftTerm view and keeps the tmux split shortcuts above the
/// terminal’s own key handling.
final class PadTerminalHost: UIView {
    let terminal = TerminalView(frame: .zero)
    var onSplitVertical: (() -> Void)?
    var onSplitHorizontal: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        terminal.frame = bounds
        terminal.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(terminal)
        backgroundColor = .black
    }

    required init?(coder: NSCoder) {
        it_fatalError("PadTerminalHost is built in code")
    }

    override var canBecomeFirstResponder: Bool { true }

    override var keyCommands: [UIKeyCommand]? {
        let vertical = UIKeyCommand(input: "d", modifierFlags: .command, action: #selector(splitVertical))
        vertical.wantsPriorityOverSystemBehavior = true
        let horizontal = UIKeyCommand(input: "d", modifierFlags: [.command, .shift], action: #selector(splitHorizontal))
        horizontal.wantsPriorityOverSystemBehavior = true
        return [vertical, horizontal]
    }

    @objc private func splitVertical() {
        onSplitVertical?()
    }

    @objc private func splitHorizontal() {
        onSplitHorizontal?()
    }

    func applyCurrentTheme() {
        TerminalTheme.current.apply(to: terminal)
    }
}
