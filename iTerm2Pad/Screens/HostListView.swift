import SwiftUI
import SSHClient

struct HostListView: View {
    @Environment(AppModel.self) private var model
    @State private var editing: SSHHost?
    @State private var creating = false

    var body: some View {
        NavigationStack {
            Group {
                if model.hosts.isEmpty {
                    ContentUnavailableView {
                        Text(String(localized: "Pad.Hosts.EmptyTitle",
                                    defaultValue: "No Hosts",
                                    comment: "Empty-state title when no SSH hosts are saved"))
                    } description: {
                        Text(String(localized: "Pad.Hosts.EmptyDetail",
                                    defaultValue: "Add a machine to open an SSH session. The default remote command is tmux control mode.",
                                    comment: "Empty-state explanation on the host list"))
                    } actions: {
                        Button(String(localized: "Pad.Hosts.Add",
                                      defaultValue: "Add Host",
                                      comment: "Toolbar button that opens the new-host editor")) {
                            creating = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(model.hosts) { host in
                            Button {
                                model.connect(host, password: nil)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(host.name)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text("\(host.username)@\(host.hostname):\(host.port)")
                                        .font(.subheadline.monospaced())
                                        .foregroundStyle(.secondary)
                                    Text(host.remoteCommand)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                }
                                .padding(.vertical, 4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing) {
                                Button(String(localized: "Pad.Host.Edit",
                                              defaultValue: "Edit",
                                              comment: "Swipe action to edit a saved SSH host")) {
                                    editing = host
                                }
                                .tint(.accentColor)
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
                }
            }
            .navigationTitle(String(localized: "Pad.Hosts.Title",
                                    defaultValue: "Hosts",
                                    comment: "Navigation title of the host list"))
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(String(localized: "Pad.Hosts.Add",
                                  defaultValue: "Add Host",
                                  comment: "Toolbar button that opens the new-host editor")) {
                        creating = true
                    }
                }
            }
            .sheet(item: $editing) { host in
                HostEditorView(host: host)
                    .modifier(PadFormSheet())
            }
            .sheet(isPresented: $creating) {
                HostEditorView(host: SSHHost(name: "", hostname: "", username: ""))
                    .modifier(PadFormSheet())
            }
        }
    }
}
