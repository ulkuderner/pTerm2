import SwiftUI
import SSHClient

struct KeysView: View {
    @Environment(AppModel.self) private var model
    @State private var showingImporter = false
    @State private var newName = ""
    @State private var newPEM = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.identities) { identity in
                    VStack(alignment: .leading) {
                        Text(identity.name)
                        if !identity.comment.isEmpty {
                            Text(identity.comment)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            model.delete(identity: identity)
                        } label: {
                            Text(String(localized: "Pad.Keys.Delete",
                                        defaultValue: "Delete",
                                        comment: "Swipe action that removes an SSH identity from the Keychain"))
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "Pad.Keys.Title",
                                    defaultValue: "Keys",
                                    comment: "Navigation title of the SSH identity list"))
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingImporter = true
                    } label: {
                        Text(String(localized: "Pad.Keys.Add",
                                    defaultValue: "Import Key",
                                    comment: "Toolbar button that opens the PEM import sheet"))
                    }
                }
            }
            .sheet(isPresented: $showingImporter) {
                NavigationStack {
                    Form {
                        TextField(String(localized: "Pad.Keys.Name",
                                         defaultValue: "Name",
                                         comment: "Label for the imported key’s display name"),
                                  text: $newName)
                        TextField(String(localized: "Pad.Keys.PEM",
                                         defaultValue: "PEM",
                                         comment: "Label for the pasted private-key PEM field"),
                                  text: $newPEM,
                                  axis: .vertical)
                        .font(.system(.footnote, design: .monospaced))
                        .lineLimit(8...16)
                    }
                    .navigationTitle(String(localized: "Pad.Keys.ImportTitle",
                                            defaultValue: "Import Identity",
                                            comment: "Title of the PEM import sheet"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(String(localized: "Pad.Host.Cancel",
                                          defaultValue: "Cancel",
                                          comment: "Cancel host editor")) {
                                showingImporter = false
                            }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button(String(localized: "Pad.Keys.Save",
                                          defaultValue: "Save",
                                          comment: "Saves a pasted PEM into the Keychain")) {
                                model.importKey(named: newName, pem: newPEM)
                                newName = ""
                                newPEM = ""
                                showingImporter = false
                            }
                            .disabled(newName.isEmpty || newPEM.isEmpty)
                        }
                    }
                }
                .modifier(PadFormSheet())
            }
        }
    }
}
