import Foundation
import PadSSH

public struct SSHIdentity: Equatable, Sendable, Identifiable, Codable {
    public var id: UUID
    public var name: String
    public var comment: String

    public init(id: UUID = UUID(), name: String, comment: String = "") {
        self.id = id
        self.name = name
        self.comment = comment
    }
}

public struct SSHHost: Equatable, Sendable, Identifiable, Codable {
    public var id: UUID
    public var name: String
    public var hostname: String
    public var port: Int
    public var username: String
    public var identityID: UUID?
    public var remoteCommand: String
    public var useMosh: Bool

    public init(id: UUID = UUID(),
                name: String,
                hostname: String,
                port: Int = 22,
                username: String,
                identityID: UUID? = nil,
                remoteCommand: String = "tmux -CC new -A -s main",
                useMosh: Bool = false) {
        self.id = id
        self.name = name
        self.hostname = hostname
        self.port = port
        self.username = username
        self.identityID = identityID
        self.remoteCommand = remoteCommand
        self.useMosh = useMosh
    }

    public var wantsTmuxControl: Bool {
        remoteCommand.contains("tmux") && remoteCommand.contains("-CC")
    }
}

public enum SSHClientError: Error, Equatable, LocalizedError {
    case backendMissing
    case connectFailed(String)
    case channelFailed
    case notConnected

    public var errorDescription: String? {
        switch self {
        case .backendMissing:
            return String(localized: "SSH.BackendMissing",
                          defaultValue: "libssh2 is not installed. Run tools/download_frameworks.sh and rebuild.",
                          comment: "Error when the optional libssh2 framework is not linked")
        case .connectFailed(let message):
            return message
        case .channelFailed:
            return String(localized: "SSH.ChannelFailed",
                          defaultValue: "The SSH channel could not be opened.",
                          comment: "Error when libssh2 cannot open a shell or exec channel")
        case .notConnected:
            return String(localized: "SSH.NotConnected",
                          defaultValue: "The SSH session is not connected.",
                          comment: "Error when I/O is attempted on a closed session")
        }
    }
}

public final class SSHSession: @unchecked Sendable {
    private var handle: OpaquePointer?
    public private(set) var connected = false

    public init() {}

    deinit {
        disconnect()
    }

    public static var backendReady: Bool {
        pad_ssh_backend_ready() != 0
    }

    public func connect(host: SSHHost,
                        privateKeyPEM: String?,
                        password: String?) throws {
        var err = [CChar](repeating: 0, count: 512)
        let session = privateKeyPEM.withCStringOptional { keyPtr in
            password.withCStringOptional { passPtr in
                host.hostname.withCString { hostPtr in
                    host.username.withCString { userPtr in
                        pad_ssh_connect(hostPtr,
                                        Int32(host.port),
                                        userPtr,
                                        keyPtr,
                                        passPtr,
                                        &err,
                                        err.count)
                    }
                }
            }
        }
        guard let session else {
            if !Self.backendReady {
                throw SSHClientError.backendMissing
            }
            let message = String(cString: err)
            throw SSHClientError.connectFailed(message.isEmpty ? "connect failed" : message)
        }
        handle = session
        connected = true
    }

    public func startShell(columns: Int, rows: Int) throws {
        guard let handle else {
            throw SSHClientError.notConnected
        }
        if pad_ssh_open_shell(handle, Int32(columns), Int32(rows)) != 0 {
            throw SSHClientError.channelFailed
        }
    }

    public func exec(_ command: String, columns: Int, rows: Int) throws {
        guard let handle else {
            throw SSHClientError.notConnected
        }
        let rc = command.withCString { pad_ssh_exec(handle, $0, Int32(columns), Int32(rows)) }
        if rc != 0 {
            throw SSHClientError.channelFailed
        }
    }

    /// tmux -CC must not have a pty. A pty turns the control stream into a cooked terminal.
    public func execControl(_ command: String) throws {
        guard let handle else {
            throw SSHClientError.notConnected
        }
        let rc = command.withCString { pad_ssh_exec_control(handle, $0) }
        if rc != 0 {
            throw SSHClientError.channelFailed
        }
    }

    public func read(maxLength: Int = 4096) -> Data {
        guard let handle else {
            return Data()
        }
        var buffer = [UInt8](repeating: 0, count: maxLength)
        let n = pad_ssh_read(handle, &buffer, buffer.count)
        if n <= 0 {
            return Data()
        }
        return Data(buffer.prefix(Int(n)))
    }

    public func write(_ data: Data) {
        guard let handle, !data.isEmpty else {
            return
        }
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else {
                return
            }
            _ = pad_ssh_write(handle, base, data.count)
        }
    }

    public func resize(columns: Int, rows: Int) {
        guard let handle else {
            return
        }
        _ = pad_ssh_resize(handle, Int32(columns), Int32(rows))
    }

    public func setReadTimeout(milliseconds: Int) {
        guard let handle else {
            return
        }
        pad_ssh_set_timeout(handle, milliseconds)
    }

    public enum SSHChunk {
        case data(Data)
        case timeout
        case closed
    }

    public func readChunk(maxLength: Int = 4096) -> SSHChunk {
        guard let handle else {
            return .closed
        }
        var buffer = [UInt8](repeating: 0, count: maxLength)
        let count = pad_ssh_read(handle, &buffer, buffer.count)
        if count > 0 {
            return .data(Data(buffer.prefix(Int(count))))
        }
        if count == -9 || count == -37 {
            return .timeout
        }
        return .closed
    }

    public func remoteBanner() -> String {
        guard let handle else {
            return ""
        }
        return String(cString: pad_ssh_banner(handle))
    }

    public func authMethods() -> String {
        guard let handle else {
            return ""
        }
        return String(cString: pad_ssh_auth_methods(handle))
    }

    public func disconnect() {
        if let handle {
            pad_ssh_disconnect(handle)
        }
        handle = nil
        connected = false
    }

    public static func scpSend(host: SSHHost,
                               privateKeyPEM: String?,
                               password: String?,
                               localPath: String,
                               remotePath: String,
                               recursive: Bool) throws {
        try scp(send: true,
                host: host,
                privateKeyPEM: privateKeyPEM,
                password: password,
                localPath: localPath,
                remotePath: remotePath,
                recursive: recursive)
    }

    public static func scpReceive(host: SSHHost,
                                  privateKeyPEM: String?,
                                  password: String?,
                                  remotePath: String,
                                  localPath: String,
                                  recursive: Bool) throws {
        try scp(send: false,
                host: host,
                privateKeyPEM: privateKeyPEM,
                password: password,
                localPath: localPath,
                remotePath: remotePath,
                recursive: recursive)
    }

    private static func scp(send: Bool,
                            host: SSHHost,
                            privateKeyPEM: String?,
                            password: String?,
                            localPath: String,
                            remotePath: String,
                            recursive: Bool) throws {
        var err = [CChar](repeating: 0, count: 512)
        let rc = privateKeyPEM.withCStringOptional { keyPtr in
            password.withCStringOptional { passPtr in
                host.hostname.withCString { hostPtr in
                    host.username.withCString { userPtr in
                        localPath.withCString { localPtr in
                            remotePath.withCString { remotePtr in
                                if send {
                                    return pad_scp_send(hostPtr,
                                                        Int32(host.port),
                                                        userPtr,
                                                        keyPtr,
                                                        passPtr,
                                                        localPtr,
                                                        remotePtr,
                                                        recursive ? 1 : 0,
                                                        &err,
                                                        err.count)
                                }
                                return pad_scp_recv(hostPtr,
                                                    Int32(host.port),
                                                    userPtr,
                                                    keyPtr,
                                                    passPtr,
                                                    remotePtr,
                                                    localPtr,
                                                    recursive ? 1 : 0,
                                                    &err,
                                                    err.count)
                            }
                        }
                    }
                }
            }
        }
        if rc != 0 {
            if !backendReady {
                throw SSHClientError.backendMissing
            }
            let message = String(cString: err)
            throw SSHClientError.connectFailed(message)
        }
    }
}

private extension Optional where Wrapped == String {
    func withCStringOptional<T>(_ body: (UnsafePointer<CChar>?) -> T) -> T {
        guard let self else {
            return body(nil)
        }
        return self.withCString { body($0) }
    }
}
