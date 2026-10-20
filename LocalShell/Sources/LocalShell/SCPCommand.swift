import Foundation
import SSHClient

struct SCPCommand: ShellCommand {
    let name = "scp"
    var aliases: [String] { ["sftp"] }

    func run(arguments: [String], context: inout CommandContext) throws -> Int32 {
        var port = 22
        var identityPath: String?
        var recursive = false
        var rest: [String] = []
        var i = 0
        while i < arguments.count {
            let arg = arguments[i]
            if arg == "-P" || arg == "-p", i + 1 < arguments.count, Int(arguments[i + 1]) != nil && arg == "-P" {
                port = Int(arguments[i + 1]) ?? 22
                i += 2
                continue
            }
            if arg == "-i", i + 1 < arguments.count {
                identityPath = arguments[i + 1]
                i += 2
                continue
            }
            if arg == "-r" {
                recursive = true
                i += 1
                continue
            }
            if arg == "-p" {
                i += 1
                continue
            }
            rest.append(arg)
            i += 1
        }
        guard rest.count == 2 else {
            throw ShellError.usage("scp [-r] [-P port] [-i identity] source dest")
        }
        let source = rest[0]
        let dest = rest[1]
        let sending = source.contains(":") ? false : dest.contains(":")
        let remoteSpec = sending ? dest : source
        let localSpec = sending ? source : dest
        let remote = try parseRemote(remoteSpec, defaultPort: port)
        var host = remote.host
        host.port = port
        let key = identityPath.flatMap { try? String(contentsOf: resolve($0, relativeTo: context), encoding: .utf8) }
        let localURL = resolve(localSpec, relativeTo: context)
        if sending {
            try SSHSession.scpSend(host: host,
                                   privateKeyPEM: key,
                                   password: nil,
                                   localPath: localURL.path,
                                   remotePath: remote.path,
                                   recursive: recursive)
        } else {
            try SSHSession.scpReceive(host: host,
                                      privateKeyPEM: key,
                                      password: nil,
                                      remotePath: remote.path,
                                      localPath: localURL.path,
                                      recursive: recursive)
        }
        context.stdout(String(localized: "Shell.SCPDone",
                              defaultValue: "Copied.\n",
                              comment: "Local-shell confirmation after scp finishes"))
        return 0
    }

    private func parseRemote(_ spec: String, defaultPort: Int) throws -> (host: SSHHost, path: String) {
        let parts = spec.split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else {
            throw ShellError.usage("remote path must be user@host:path")
        }
        let userHost = String(parts[0])
        let path = String(parts[1])
        let uh = userHost.split(separator: "@", maxSplits: 1)
        let user: String
        let hostname: String
        if uh.count == 2 {
            user = String(uh[0])
            hostname = String(uh[1])
        } else {
            user = NSUserName().isEmpty ? "mobile" : NSUserName()
            hostname = userHost
        }
        return (SSHHost(name: hostname, hostname: hostname, port: defaultPort, username: user), path)
    }
}
