import Foundation
import SSHClient

public struct SSHFSMount: Equatable, Sendable, Codable, Identifiable {
    public var id: UUID
    public var name: String
    public var hostname: String
    public var port: Int
    public var username: String
    public var remotePath: String
    public var identityID: UUID?

    public init(id: UUID = UUID(),
                name: String,
                hostname: String,
                port: Int,
                username: String,
                remotePath: String,
                identityID: UUID? = nil) {
        self.id = id
        self.name = name
        self.hostname = hostname
        self.port = port
        self.username = username
        self.remotePath = remotePath
        self.identityID = identityID
    }
}

public enum SSHFSMountStore {
    public static let suiteName = "group.com.googlecode.iterm2.pad"
    public static let mountsKey = "NoSyncSSHFSMounts"

    public static func load() -> [SSHFSMount] {
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        guard let data = defaults.data(forKey: mountsKey),
              let mounts = try? JSONDecoder().decode([SSHFSMount].self, from: data) else {
            return []
        }
        return mounts
    }

    public static func save(_ mounts: [SSHFSMount]) {
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        if let data = try? JSONEncoder().encode(mounts) {
            defaults.set(data, forKey: mountsKey)
        }
    }
}

struct SSHFSCommand: ShellCommand {
    let name = "sshfs"

    func run(arguments: [String], context: inout CommandContext) throws -> Int32 {
        guard let spec = arguments.first else {
            throw ShellError.usage("sshfs user@host:path [name]")
        }
        let parts = spec.split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else {
            throw ShellError.usage("sshfs user@host:path [name]")
        }
        let userHost = String(parts[0])
        let remotePath = String(parts[1])
        let uh = userHost.split(separator: "@", maxSplits: 1)
        guard uh.count == 2 else {
            throw ShellError.usage("sshfs user@host:path [name]")
        }
        let name = arguments.count > 1 ? arguments[1] : String(uh[1])
        var mounts = SSHFSMountStore.load()
        mounts.removeAll { $0.name == name }
        mounts.append(SSHFSMount(name: name,
                                 hostname: String(uh[1]),
                                 port: 22,
                                 username: String(uh[0]),
                                 remotePath: remotePath))
        SSHFSMountStore.save(mounts)
        let mountDir = context.home.appendingPathComponent("mnt").appendingPathComponent(name)
        try FileManager.default.createDirectory(at: mountDir, withIntermediateDirectories: true)
        context.stdout(String(localized: "Shell.SSHFSMounted",
                              defaultValue: "Mounted \(spec) at \(mountDir.path). It also appears in Files.\n",
                              comment: "Confirmation after sshfs registers a File Provider domain. %1$@ is user@host:path, %2$@ is the local path."))
        return 0
    }
}

struct UmountCommand: ShellCommand {
    let name = "umount"
    var aliases: [String] { ["unmount"] }

    func run(arguments: [String], context: inout CommandContext) throws -> Int32 {
        guard let name = arguments.first else {
            throw ShellError.usage("umount name")
        }
        var mounts = SSHFSMountStore.load()
        mounts.removeAll { $0.name == name || $0.name == URL(fileURLWithPath: name).lastPathComponent }
        SSHFSMountStore.save(mounts)
        context.stdout(String(localized: "Shell.SSHFSUnmounted",
                              defaultValue: "Unmounted \(name).\n",
                              comment: "Confirmation after umount. %1$@ is the mount name."))
        return 0
    }
}
