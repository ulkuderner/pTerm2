import SwiftUI
import SSHClient
import LocalShell

struct SettingsView: View {
    @State private var themeID = TerminalTheme.current.id

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "Pad.Settings.Theme",
                               defaultValue: "Theme",
                               comment: "Settings section heading for the terminal color theme")) {
                    Picker(String(localized: "Pad.Settings.Theme",
                                  defaultValue: "Theme",
                                  comment: "Settings section heading for the terminal color theme"),
                           selection: $themeID) {
                        ForEach(TerminalTheme.allCases) { theme in
                            Text(theme.title).tag(theme.id)
                        }
                    }
                    .onChange(of: themeID) { _, newValue in
                        TerminalTheme.current = TerminalTheme.allCases.first { $0.id == newValue } ?? .linux
                    }
                }
                Section(String(localized: "Pad.Settings.Backends",
                               defaultValue: "Backends",
                               comment: "Settings section heading for optional native frameworks")) {
                    LabeledContent(String(localized: "Pad.Settings.LibSSH2",
                                          defaultValue: "libssh2",
                                          comment: "Settings row for whether libssh2 is linked")) {
                        Text(SSHSession.backendReady
                             ? String(localized: "Pad.Settings.Ready",
                                      defaultValue: "Ready",
                                      comment: "Value shown when an optional framework is linked")
                             : String(localized: "Pad.Settings.Download",
                                      defaultValue: "Run download_frameworks.sh",
                                      comment: "Value shown when an optional framework is missing"))
                    }
                    LabeledContent("ios_system") {
                        Text(NativeBackends.iosSystem
                             ? String(localized: "Pad.Settings.Ready",
                                      defaultValue: "Ready",
                                      comment: "Value shown when an optional framework is linked")
                             : String(localized: "Pad.Settings.Download",
                                      defaultValue: "Run download_frameworks.sh",
                                      comment: "Value shown when an optional framework is missing"))
                    }
                    LabeledContent("python3") {
                        Text(NativeBackends.python
                             ? String(localized: "Pad.Settings.Ready",
                                      defaultValue: "Ready",
                                      comment: "Value shown when an optional framework is linked")
                             : String(localized: "Pad.Settings.Download",
                                      defaultValue: "Run download_frameworks.sh",
                                      comment: "Value shown when an optional framework is missing"))
                    }
                }
                Section(String(localized: "Pad.Settings.About",
                               defaultValue: "About",
                               comment: "Settings section heading for license")) {
                    Text(String(localized: "Pad.Settings.License",
                                defaultValue: "pTerm2 is GPL-3. Local commands come from ios_system (BSD). The terminal grid is SwiftTerm (MIT).",
                                comment: "Short license summary on the settings screen"))
                }
            }
            .navigationTitle(String(localized: "Pad.Settings.Title",
                                    defaultValue: "Settings",
                                    comment: "Navigation title of the settings screen"))
        }
    }
}
