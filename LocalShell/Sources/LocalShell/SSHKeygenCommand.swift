import CryptoKit
import Foundation
import Security
import SSHClient

/// Ed25519 keys in OpenSSH format. libssh2 in this app reads that format.
/// The private key also goes into the same Keychain the Keys screen lists.
enum SSHIdentities {
    static let service = "com.caglar.pTerm2.ssh-keys"
    static let defaultsKey = "NoSyncSSHIdentities"

    static func privateKey(path explicit: String?, context: CommandContext) -> String? {
        if var path = explicit, !path.isEmpty {
            if path.hasSuffix(".pub") {
                path = String(path.dropLast(4))
            }
            let url = resolve(path, relativeTo: context)
            if let text = try? String(contentsOf: url, encoding: .utf8), text.contains("PRIVATE KEY") {
                return text
            }
            return nil
        }
        let ssh = context.home.appendingPathComponent(".ssh")
        for name in ["id_ed25519", "id_rsa", "id_ecdsa"] {
            let url = ssh.appendingPathComponent(name)
            if let text = try? String(contentsOf: url, encoding: .utf8), text.contains("PRIVATE KEY") {
                return text
            }
        }
        return keychainPEMs().first
    }

    static func keychainPEMs() -> [String] {
        identities().compactMap { pem(for: $0) }
    }

    static func identities() -> [SSHIdentity] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let list = try? JSONDecoder().decode([SSHIdentity].self, from: data) else {
            return []
        }
        return list
    }

    static func pem(for identity: SSHIdentity) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: identity.id.uuidString,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func store(name: String, comment: String, pem: String) throws {
        let identity = SSHIdentity(name: name, comment: comment)
        let data = Data(pem.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: identity.id.uuidString,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecAttrSynchronizable as String] = kCFBooleanFalse
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw ShellError.failed("keychain write failed (\(status))")
        }
        var list = identities()
        list.append(identity)
        if let encoded = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(encoded, forKey: defaultsKey)
        }
        NotificationCenter.default.post(name: .ptermSSHKeysChanged, object: nil)
    }
}

enum SSHEd25519 {
    static func generate(comment: String) -> (privateKey: String, publicLine: String, fingerprint: String) {
        let key = Curve25519.Signing.PrivateKey()
        let seed = key.rawRepresentation
        let pub = key.publicKey.rawRepresentation
        let secret = seed + pub
        let publicBlob = sshString(Data("ssh-ed25519".utf8)) + sshString(pub)
        var body = Data()
        let check = UInt32.random(in: .min ... .max)
        body.append(uint32(check))
        body.append(uint32(check))
        body.append(sshString(Data("ssh-ed25519".utf8)))
        body.append(sshString(pub))
        body.append(sshString(secret))
        body.append(sshString(Data(comment.utf8)))
        var pad: UInt8 = 1
        while body.count % 8 != 0 {
            body.append(pad)
            pad += 1
        }
        var packet = Data("openssh-key-v1\0".utf8)
        packet.append(sshString(Data("none".utf8)))
        packet.append(sshString(Data("none".utf8)))
        packet.append(sshString(Data()))
        packet.append(uint32(1))
        packet.append(sshString(publicBlob))
        packet.append(sshString(body))
        let encoded = Self.wrap(packet.base64EncodedString())
        let privateKey = "-----BEGIN OPENSSH PRIVATE KEY-----\n\(encoded)\n-----END OPENSSH PRIVATE KEY-----\n"
        let publicLine = "ssh-ed25519 \(publicBlob.base64EncodedString()) \(comment)"
        let digest = SHA256.hash(data: publicBlob)
        let fingerprint = "SHA256:" + Data(digest).base64EncodedString().replacingOccurrences(of: "=", with: "")
        return (privateKey, publicLine, fingerprint)
    }

    private static func wrap(_ text: String) -> String {
        var lines: [String] = []
        var rest = text
        while !rest.isEmpty {
            let end = rest.index(rest.startIndex, offsetBy: 70, limitedBy: rest.endIndex) ?? rest.endIndex
            lines.append(String(rest[..<end]))
            rest = String(rest[end...])
        }
        return lines.joined(separator: "\n")
    }

    private static func uint32(_ value: UInt32) -> Data {
        var big = value.bigEndian
        return Data(bytes: &big, count: 4)
    }

    private static func sshString(_ data: Data) -> Data {
        uint32(UInt32(data.count)) + data
    }
}

struct SSHKeygenCommand: ShellCommand {
    let name = "ssh-keygen"

    func run(arguments: [String], context: inout CommandContext) throws -> Int32 {
        if arguments.contains("-l") || arguments.contains("-L") {
            return list(context: &context)
        }
        var type = "ed25519"
        var file = "~/.ssh/id_ed25519"
        var comment = defaultComment()
        var index = 0
        while index < arguments.count {
            let word = arguments[index]
            if word == "-t", index + 1 < arguments.count {
                type = arguments[index + 1]
                index += 2
                continue
            }
            if word == "-f", index + 1 < arguments.count {
                file = arguments[index + 1]
                index += 2
                continue
            }
            if word == "-C", index + 1 < arguments.count {
                comment = arguments[index + 1]
                index += 2
                continue
            }
            if word == "-N", index + 1 < arguments.count {
                index += 2
                continue
            }
            if word == "-q" {
                index += 1
                continue
            }
            index += 1
        }
        guard type == "ed25519" else {
            throw ShellError.usage("ssh-keygen -t ed25519 [-f file] [-C comment]")
        }
        let privateURL = resolve(expandHome(file, context: context), relativeTo: context)
        if FileManager.default.fileExists(atPath: privateURL.path) {
            context.stdout("\(privateURL.path) already exists\n")
            if let line = try? String(contentsOf: publicURL(for: privateURL), encoding: .utf8) {
                context.stdout(line.hasSuffix("\n") ? line : line + "\n")
            }
            return 0
        }
        let made = SSHEd25519.generate(comment: comment)
        let directory = privateURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        try made.privateKey.write(to: privateURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: privateURL.path)
        let pub = publicURL(for: privateURL)
        try (made.publicLine + "\n").write(to: pub, atomically: true, encoding: .utf8)
        try SSHIdentities.store(name: privateURL.lastPathComponent, comment: comment, pem: made.privateKey)
        context.stdout("Generating public/private ed25519 key pair.\n")
        context.stdout("Your identification has been saved in \(privateURL.path)\n")
        context.stdout("Your public key has been saved in \(pub.path)\n")
        context.stdout("The key fingerprint is:\n")
        context.stdout("256 \(made.fingerprint) \(comment) (ED25519)\n")
        context.stdout(made.publicLine + "\n")
        return 0
    }

    private func list(context: inout CommandContext) -> Int32 {
        let ssh = context.home.appendingPathComponent(".ssh")
        let pubs = ((try? FileManager.default.contentsOfDirectory(at: ssh, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "pub" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        if pubs.isEmpty && SSHIdentities.identities().isEmpty {
            context.stdout("ssh-keygen: no identities\n")
            return 0
        }
        for url in pubs {
            let line = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            context.stdout(line.hasSuffix("\n") ? line : line + "\n")
        }
        for identity in SSHIdentities.identities() {
            context.stdout("keychain \(identity.name) \(identity.comment)\n")
        }
        return 0
    }

    private func publicURL(for privateURL: URL) -> URL {
        URL(fileURLWithPath: privateURL.path + ".pub")
    }

    private func expandHome(_ path: String, context: CommandContext) -> String {
        if path == "~" {
            return context.home.path
        }
        if path.hasPrefix("~/") {
            return context.home.path + path.dropFirst(1)
        }
        return path
    }

    private func defaultComment() -> String {
        let user = ProcessInfo.processInfo.environment["USER"].flatMap { $0.isEmpty ? nil : $0 } ?? "mobile"
        var host = ProcessInfo.processInfo.hostName
        if let dot = host.firstIndex(of: ".") {
            host = String(host[..<dot])
        }
        return "\(user)@\(host)"
    }
}

struct SSHCopyIDCommand: ShellCommand {
    let name = "ssh-copy-id"

    func run(arguments: [String], context: inout CommandContext) throws -> Int32 {
        var port = 22
        var identity: String?
        var userHost: String?
        var index = 0
        while index < arguments.count {
            let word = arguments[index]
            if word == "-p", index + 1 < arguments.count {
                port = Int(arguments[index + 1]) ?? 22
                index += 2
                continue
            }
            if word == "-i", index + 1 < arguments.count {
                identity = arguments[index + 1]
                index += 2
                continue
            }
            if !word.hasPrefix("-") {
                userHost = word
                break
            }
            index += 1
        }
        guard let userHost else {
            throw ShellError.usage("ssh-copy-id [-i file] [-p port] user@host")
        }
        let publicFile: URL
        if let identity {
            let chosen = resolve(identity, relativeTo: context)
            publicFile = chosen.pathExtension == "pub" ? chosen : URL(fileURLWithPath: chosen.path + ".pub")
        } else {
            publicFile = context.home.appendingPathComponent(".ssh/id_ed25519.pub")
        }
        guard let line = try? String(contentsOf: publicFile, encoding: .utf8) else {
            throw ShellError.failed("ssh-copy-id: no public key. Run ssh-keygen first.")
        }
        let pubkey = line.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "'", with: "")
        let parts = userHost.split(separator: "@", maxSplits: 1)
        let user: String
        let hostName: String
        if parts.count == 2 {
            user = String(parts[0])
            hostName = String(parts[1])
        } else {
            user = ProcessInfo.processInfo.environment["USER"].flatMap { $0.isEmpty ? nil : $0 } ?? "mobile"
            hostName = userHost
        }
        var host = SSHHost(name: hostName, hostname: hostName, port: port, username: user)
        host.remoteCommand = "mkdir -p .ssh && chmod 700 .ssh && printf '%s\n' '\(pubkey)' >> .ssh/authorized_keys && chmod 600 .ssh/authorized_keys"
        let pem = SSHIdentities.privateKey(path: identity, context: context)
        SSHLaunchMailbox.pending = SSHLaunchRequest(host: host, privateKeyPEM: pem)
        context.stdout("ssh-copy-id: installing \(publicFile.lastPathComponent) on \(user)@\(hostName)\n")
        return 0
    }
}
