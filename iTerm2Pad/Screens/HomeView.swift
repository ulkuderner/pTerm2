import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.tab) {
            HostListView()
                .tabItem {
                    Text(AppModel.Tab.hosts.title)
                }
                .tag(AppModel.Tab.hosts)
            LocalShellView()
                .tabItem {
                    Text(AppModel.Tab.shell.title)
                }
                .tag(AppModel.Tab.shell)
            KeysView()
                .tabItem {
                    Text(AppModel.Tab.keys.title)
                }
                .tag(AppModel.Tab.keys)
            SettingsView()
                .tabItem {
                    Text(AppModel.Tab.settings.title)
                }
                .tag(AppModel.Tab.settings)
        }
        .fullScreenCover(item: sessionBinding) { session in
            SessionContainerView(session: session)
        }
        .alert(String(localized: "Pad.Error.Title",
                      defaultValue: "Something went wrong",
                      comment: "Alert title for a recoverable connection or keychain error"),
               isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
               ),
               actions: {
            Button(String(localized: "Pad.Error.OK",
                          defaultValue: "OK",
                          comment: "Dismiss button on the error alert"),
                   role: .cancel) {
                model.errorMessage = nil
            }
        }, message: {
            Text(model.errorMessage ?? "")
        })
        .onChange(of: model.tab) { _, _ in
            model.consumePendingSSHLaunch()
        }
    }

    private var sessionBinding: Binding<LiveSession?> {
        Binding(
            get: { model.activeSession },
            set: { newValue in
                if newValue == nil {
                    model.activeSession?.close()
                }
                model.activeSession = newValue
            }
        )
    }
}

extension LiveSession: Identifiable {
    var id: UUID { host.id }
}
