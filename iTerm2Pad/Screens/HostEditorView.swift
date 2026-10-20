import SwiftUI
import SSHClient

struct HostEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var host: SSHHost

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "Pad.Host.SectionConnection",
                               defaultValue: "Connection",
                               comment: "Form section for hostname, user, and port")) {
                    TextField(String(localized: "Pad.Host.Name",
                                     defaultValue: "Name",
                                     comment: "Label for the host display name field"),
                              text: $host.name)
                    TextField(String(localized: "Pad.Host.Hostname",
                                     defaultValue: "Host",
                                     comment: "Label for the SSH hostname field"),
                              text: $host.hostname)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                    TextField(String(localized: "Pad.Host.User",
                                     defaultValue: "User",
                                     comment: "Label for the SSH username field"),
                              text: $host.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                    TextField(String(localized: "Pad.Host.Port",
                                     defaultValue: "Port",
                                     comment: "Label for the SSH port field"),
                              value: $host.port,
                              format: .number)
                        .keyboardType(.numberPad)
                }
                Section(String(localized: "Pad.Host.SectionSession",
                               defaultValue: "Session",
                               comment: "Form section for the SSH key and remote command")) {
                    Picker(String(localized: "Pad.Host.Identity",
                                  defaultValue: "Identity",
                                  comment: "Picker that chooses which Keychain SSH key to use"),
                           selection: $host.identityID) {
                        Text(String(localized: "Pad.Host.IdentityNone",
                                    defaultValue: "None",
                                    comment: "Picker option meaning no SSH identity file"))
                            .tag(Optional<UUID>.none)
                        ForEach(model.identities) { identity in
                            Text(identity.name).tag(Optional.some(identity.id))
                        }
                    }
                    TextField(String(localized: "Pad.Host.RemoteCommand",
                                     defaultValue: "Remote command",
                                     comment: "Label for the command run after SSH login, typically tmux -CC"),
                              text: $host.remoteCommand)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                }
            }
            .navigationTitle(host.name.isEmpty
                             ? String(localized: "Pad.Host.New",
                                      defaultValue: "New Host",
                                      comment: "Navigation title when creating a host")
                             : host.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Pad.Host.Cancel",
                                  defaultValue: "Cancel",
                                  comment: "Cancel host editor")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Pad.Host.Save",
                                  defaultValue: "Save",
                                  comment: "Save host editor")) {
                        if host.name.isEmpty {
                            host.name = host.hostname
                        }
                        model.save(host: host)
                        dismiss()
                    }
                    .disabled(host.hostname.isEmpty || host.username.isEmpty)
                }
            }
        }
    }
}
