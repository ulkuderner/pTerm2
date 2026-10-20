import Foundation
import SSHClient

final class HostStore {
    static let hostsKey = "NoSyncSSHHosts"

    func hosts() -> [SSHHost] {
        guard let data = UserDefaults.standard.data(forKey: Self.hostsKey),
              let hosts = try? JSONDecoder().decode([SSHHost].self, from: data) else {
            return []
        }
        return hosts
    }

    func save(_ hosts: [SSHHost]) {
        if let data = try? JSONEncoder().encode(hosts) {
            UserDefaults.standard.set(data, forKey: Self.hostsKey)
        }
    }

    func upsert(_ host: SSHHost) {
        var hosts = hosts()
        if let index = hosts.firstIndex(where: { $0.id == host.id }) {
            hosts[index] = host
        } else {
            hosts.append(host)
        }
        save(hosts)
    }

    func delete(_ host: SSHHost) {
        var hosts = hosts()
        hosts.removeAll { $0.id == host.id }
        save(hosts)
    }
}
