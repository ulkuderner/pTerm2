import Foundation
import Security
import SSHClient

/// SSH private keys live in the Keychain. Public metadata is in UserDefaults
/// under a NoSync key so a custom prefs location is not prompted.
final class KeychainStore {
    static let identitiesDefaultsKey = "NoSyncSSHIdentities"
    private let service = "com.googlecode.iterm2.pad.ssh-keys"

    func identities() -> [SSHIdentity] {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: Self.identitiesDefaultsKey),
              let list = try? JSONDecoder().decode([SSHIdentity].self, from: data) else {
            return []
        }
        return list
    }

    func saveIdentities(_ identities: [SSHIdentity]) {
        if let data = try? JSONEncoder().encode(identities) {
            UserDefaults.standard.set(data, forKey: Self.identitiesDefaultsKey)
        }
    }

    func pem(for identity: SSHIdentity) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: identity.id.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func store(identity: SSHIdentity, pem: String) throws {
        let data = Data(pem.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: identity.id.uuidString
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SSHClientError.connectFailed("Keychain write failed (\(status))")
        }
        var list = identities()
        list.removeAll { $0.id == identity.id }
        list.append(identity)
        saveIdentities(list)
    }

    func delete(_ identity: SSHIdentity) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: identity.id.uuidString
        ]
        SecItemDelete(query as CFDictionary)
        var list = identities()
        list.removeAll { $0.id == identity.id }
        saveIdentities(list)
    }

    func importPEM(named name: String, pem: String) throws -> SSHIdentity {
        let comment = pem.split(separator: "\n").first(where: { $0.contains("COMMENT") }).map(String.init) ?? ""
        let identity = SSHIdentity(name: name, comment: comment)
        try store(identity: identity, pem: pem)
        return identity
    }
}
