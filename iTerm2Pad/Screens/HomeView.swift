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
        .onReceive(NotificationCenter.default.publisher(for: .ptermSSHLaunch)) { _ in
            model.consumePendingSSHLaunch()
        }
        .onReceive(NotificationCenter.default.publisher(for: .ptermOpenLiveSession)) { note in
            if let session = note.object as? LiveSession {
                model.activeSession = session
            }
        }
        .sheet(isPresented: Binding(
            get: { model.sshPasswordPrompt != nil },
            set: { if !$0 { model.cancelSSHPassword() } }
        )) {
            SSHPasswordSheet(host: model.sshPasswordPrompt ?? "",
                             password: $model.sshPassword,
                             submit: { model.submitSSHPassword() },
                             cancel: { model.cancelSSHPassword() })
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

private struct SSHPasswordSheet: View {
    var host: String
    @Binding var password: String
    var submit: () -> Void
    var cancel: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                SecureField(String(localized: "Pad.SSH.Password",
                                   defaultValue: "Password",
                                   comment: "Password field for an ssh command typed in the shell"),
                            text: $password)
            }
            .navigationTitle(host)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Pad.SSH.Cancel",
                                  defaultValue: "Cancel",
                                  comment: "Dismiss the SSH password sheet"),
                           role: .cancel, action: cancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Pad.SSH.Connect",
                                  defaultValue: "Connect",
                                  comment: "Start the SSH session with the typed password"),
                           action: submit)
                }
            }
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
