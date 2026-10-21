import Foundation
import Security

/// Claude login stored in the iPad keychain. The item is allowed to sync
/// through iCloud Keychain, so a record written on the Mac can appear here.
public enum ClaudeKeychain {
    public static let service = "Claude Code-credentials"
    public static let account = "claude"
    public static var lastStatus: OSStatus = errSecSuccess

    public static func load() -> String? {
        read(account: account) ?? read(account: nil)
    }

    /// Moves a one-time token file into the keychain and removes the file.
    public static func importFile(at home: URL) -> Bool {
        let file = home.appendingPathComponent("Library/pterm/claude.token")
        guard let raw = try? String(contentsOf: file, encoding: .utf8) else {
            return load() != nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, save(trimmed) else {
            return load() != nil
        }
        try? FileManager.default.removeItem(at: file)
        return load() != nil
    }

    @discardableResult
    public static func save(_ secret: String) -> Bool {
        let query = base(account: account)
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = Data(secret.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        add[kSecAttrSynchronizable as String] = kCFBooleanTrue
        add[kSecAttrLabel as String] = "pTerm Claude"
        lastStatus = SecItemAdd(add as CFDictionary, nil)
        return lastStatus == errSecSuccess
    }

    private static func read(account: String?) -> String? {
        var query = base(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data,
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func base(account: String?) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]
        if let account {
            query[kSecAttrAccount as String] = account
        }
        return query
    }
}
