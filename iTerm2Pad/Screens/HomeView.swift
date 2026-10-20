import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            if #available(iOS 18.0, *) {
                PadSidebar(model: model)
            } else {
                PadTabs(model: model)
            }
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

@available(iOS 18.0, *)
private struct PadSidebar: View {
    @Bindable var model: AppModel

    var body: some View {
        TabView(selection: $model.tab) {
            Tab(AppModel.Tab.hosts.title, systemImage: "server.rack", value: AppModel.Tab.hosts) {
                HostListView()
            }
            Tab(AppModel.Tab.shell.title, systemImage: "terminal", value: AppModel.Tab.shell) {
                LocalShellView()
            }
            Tab(AppModel.Tab.keys.title, systemImage: "key.fill", value: AppModel.Tab.keys) {
                KeysView()
            }
            Tab(AppModel.Tab.settings.title, systemImage: "gearshape.fill", value: AppModel.Tab.settings) {
                SettingsView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}

private struct PadTabs: View {
    @Bindable var model: AppModel

    var body: some View {
        TabView(selection: $model.tab) {
            HostListView()
                .tabItem { Text(AppModel.Tab.hosts.title) }
                .tag(AppModel.Tab.hosts)
            LocalShellView()
                .tabItem { Text(AppModel.Tab.shell.title) }
                .tag(AppModel.Tab.shell)
            KeysView()
                .tabItem { Text(AppModel.Tab.keys.title) }
                .tag(AppModel.Tab.keys)
            SettingsView()
                .tabItem { Text(AppModel.Tab.settings.title) }
                .tag(AppModel.Tab.settings)
        }
    }
}

struct PadFormSheet: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content
                .presentationSizing(.form)
                .presentationDragIndicator(.visible)
        } else {
            content
                .presentationDragIndicator(.visible)
        }
    }
}

extension LiveSession: Identifiable {
    var id: UUID { host.id }
}
