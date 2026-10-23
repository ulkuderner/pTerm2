import Foundation
import Observation
import SwiftUI
import LocalShell
import SSHClient
import TmuxControl

@Observable
final class AppModel {
    enum Tab: String, CaseIterable, Identifiable {
        case hosts
        case shell
        case keys
        case settings

        var id: String { rawValue }

        var title: String {
            switch self {
            case .hosts:
                return String(localized: "Pad.Tab.Hosts",
                              defaultValue: "Hosts",
                              comment: "Tab title for the SSH host list")
            case .shell:
                return String(localized: "Pad.Tab.Shell",
                              defaultValue: "Shell",
                              comment: "Tab title for the local ios_system shell")
            case .keys:
                return String(localized: "Pad.Tab.Keys",
                              defaultValue: "Keys",
                              comment: "Tab title for SSH identities")
            case .settings:
                return String(localized: "Pad.Tab.Settings",
                              defaultValue: "Settings",
                              comment: "Tab title for settings")
            }
        }
    }

    var tab: Tab = .hosts
    var hosts: [SSHHost] = []
    var identities: [SSHIdentity] = []
    var activeSession: LiveSession?
    var errorMessage: String?
    var sshPassword = ""
    var sshPasswordPrompt: String?

    let hostStore = HostStore()
    let keychain = KeychainStore()
    let documents: URL
    private var keyObserver: NSObjectProtocol?

    init(documents: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]) {
        self.documents = documents
        if CommandLine.arguments.contains("-pterm-shell") {
            tab = .shell
        }
        if CommandLine.arguments.contains("-pterm-settings") {
            tab = .settings
        }
        reload()
        keyObserver = NotificationCenter.default.addObserver(
            forName: .ptermSSHKeysChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reload()
        }
    }

    func reload() {
        hosts = hostStore.hosts()
        identities = keychain.identities()
    }

    func save(host: SSHHost) {
        hostStore.upsert(host)
        reload()
    }

    func delete(host: SSHHost) {
        hostStore.delete(host)
        reload()
    }

    func importKey(named name: String, pem: String) {
        do {
            _ = try keychain.importPEM(named: name, pem: pem)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(identity: SSHIdentity) {
        keychain.delete(identity)
        reload()
    }

    func connect(_ host: SSHHost, password: String?) {
        let pem = host.identityID.flatMap { id in
            identities.first(where: { $0.id == id }).flatMap { keychain.pem(for: $0) }
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let session = LiveSession(host: host, privateKeyPEM: pem, password: password)
            do {
                try session.start()
                DispatchQueue.main.async {
                    self?.activeSession = session
                }
            } catch {
                DispatchQueue.main.async {
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func consumePendingSSHLaunch() {
        guard let pending = SSHLaunchMailbox.pending else {
            return
        }
        if pending.password == nil && pending.host.identityID == nil {
            sshPassword = ""
            sshPasswordPrompt = "\(pending.host.username)@\(pending.host.hostname)"
            return
        }
        SSHLaunchMailbox.pending = nil
        connect(pending.host, password: pending.password)
    }

    func submitSSHPassword() {
        guard let pending = SSHLaunchMailbox.pending else {
            sshPasswordPrompt = nil
            return
        }
        let password = sshPassword
        sshPassword = ""
        sshPasswordPrompt = nil
        SSHLaunchMailbox.pending = nil
        connect(pending.host, password: password)
    }

    func cancelSSHPassword() {
        sshPassword = ""
        sshPasswordPrompt = nil
        SSHLaunchMailbox.pending = nil
    }
}

@Observable
final class LiveSession {
    let host: SSHHost
    let ssh: SSHSession
    let tmux = TmuxSession()
    private let privateKeyPEM: String?
    private let password: String?
    var connected = false
    var lastError: String?
    private var reader: DispatchSourceRead?

    init(host: SSHHost, privateKeyPEM: String?, password: String?) {
        self.host = host
        self.ssh = SSHSession()
        self.privateKeyPEM = privateKeyPEM
        self.password = password
    }

    /// The shell already authenticated. This session only speaks tmux control mode.
    init(host: SSHHost, connected session: SSHSession) {
        self.host = host
        self.ssh = session
        self.privateKeyPEM = nil
        self.password = nil
    }

    func startControl(columns: Int, rows: Int) {
        tmux.attach { [weak self] command in
            self?.ssh.write(Data(command.utf8))
        }
        connected = true
        startReading()
        resize(columns: columns, rows: rows)
    }

    func start() throws {
        try ssh.connect(host: host, privateKeyPEM: privateKeyPEM, password: password)
        if host.wantsTmuxControl && !host.remoteCommand.isEmpty {
            try ssh.execControl(TmuxStandard.launchCommand(remoteCommand: host.remoteCommand))
            tmux.attach { [weak self] command in
                self?.ssh.write(Data(command.utf8))
            }
        } else if !host.remoteCommand.isEmpty && host.remoteCommand != "tmux -CC new -A -s main" {
            try ssh.exec(host.remoteCommand, columns: 80, rows: 24)
        } else {
            try ssh.startShell(columns: 80, rows: 24)
        }
        connected = true
        startReading()
    }

    func send(_ data: Data) {
        if host.wantsTmuxControl {
            return
        }
        ssh.write(data)
    }

    func sendTmuxKey(_ name: String, pane: Int) {
        tmux.sendKeyName(name, to: pane)
    }

    func sendTmuxText(_ text: String, pane: Int) {
        tmux.sendLiteral(text, to: pane)
    }

    func resize(columns: Int, rows: Int) {
        ssh.resize(columns: columns, rows: rows)
        if host.wantsTmuxControl {
            tmux.setClientSize(columns: columns, rows: rows)
        }
    }

    func close() {
        ssh.disconnect()
        connected = false
    }

    var onPlainOutput: ((Data) -> Void)?

    private func startReading() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            while let self, self.connected {
                let data = self.ssh.read()
                if data.isEmpty {
                    Thread.sleep(forTimeInterval: 0.05)
                    continue
                }
                if self.host.wantsTmuxControl {
                    self.tmux.ingest(data)
                } else {
                    DispatchQueue.main.async {
                        self.onPlainOutput?(data)
                    }
                }
            }
        }
    }
}
