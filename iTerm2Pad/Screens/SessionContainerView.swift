import SwiftUI

struct SessionContainerView: View {
    @Environment(\.dismiss) private var dismiss
    var session: LiveSession

    var body: some View {
        NavigationStack {
            Group {
                if session.host.wantsTmuxControl {
                    TmuxSessionView(session: session)
                } else {
                    PlainTerminalView(session: session)
                }
            }
            .navigationTitle(session.host.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Pad.Session.Close",
                                  defaultValue: "Close",
                                  comment: "Closes the live SSH or tmux session")) {
                        session.close()
                        dismiss()
                    }
                }
            }
        }
    }
}
