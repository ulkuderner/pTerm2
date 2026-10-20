import SwiftUI
import SSHClient

struct HostListView: View {
    @Environment(AppModel.self) private var model
    @State private var editing: SSHHost?
    @State private var creating = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.hosts) { host in
                    Button {
                        model.connect(host, password: nil)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(host.name)
                                .font(.headline)
                            Text("\(host.username)@\(host.hostname):\(host.port)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(host.remoteCommand)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(String(localized: "Pad.Host.Edit",
                                      defaultValue: "Edit",
                                      comment: "Swipe action to edit a saved SSH host")) {
                            editing = host
                        }
                        Button(role: .destructive) {
                            model.delete(host: host)
                        } label: {
                            Text(String(localized: "Pad.Host.Delete",
                                        defaultValue: "Delete",
                                        comment: "Swipe action to delete a saved SSH host"))
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "Pad.Hosts.Title",
                                    defaultValue: "Hosts",
                                    comment: "Navigation title of the host list"))
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        creating = true
                    } label: {
                        Text(String(localized: "Pad.Hosts.Add",
                                    defaultValue: "Add Host",
                                    comment: "Toolbar button that opens the new-host editor"))
                    }
                }
            }
            .sheet(item: $editing) { host in
                HostEditorView(host: host)
            }
            .sheet(isPresented: $creating) {
                HostEditorView(host: SSHHost(name: "", hostname: "", username: ""))
            }
        }
    }
}
