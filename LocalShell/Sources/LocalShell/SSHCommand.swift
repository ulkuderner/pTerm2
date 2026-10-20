import Foundation
import SSHClient

/// Interactive `ssh` is started by the app’s session manager. From the local
/// shell this command records the request so the UI can open a terminal.
public struct SSHLaunchRequest: Equatable, Sendable {
    public var host: SSHHost
    public var password: String?
}

public enum SSHLaunchMailbox {
    public static var pending: SSHLaunchRequest?
}

struct SSHCommand: ShellCommand {
    let name = "ssh"
    var aliases: [String] { ["mosh"] }

    func run(arguments: [String], context: inout CommandContext) throws -> Int32 {
        var port = 22
        var identity: String?
        var userHost: String?
        var i = 0
        var remoteCommand = ""
        while i < arguments.count {
            let arg = arguments[i]
            if arg == "-p", i + 1 < arguments.count {
                port = Int(arguments[i + 1]) ?? 22
                i += 2
                continue
            }
            if arg == "-i", i + 1 < arguments.count {
                identity = arguments[i + 1]
                i += 2
                continue
            }
            if arg == "--" {
                remoteCommand = arguments.dropFirst(i + 1).joined(separator: " ")
                break
            }
            if !arg.hasPrefix("-") {
                userHost = arg
                if i + 1 < arguments.count {
                    remoteCommand = arguments.dropFirst(i + 1).joined(separator: " ")
                }
                break
            }
            i += 1
        }
        guard let userHost else {
            throw ShellError.usage("ssh [-p port] [-i identity] user@host [command]")
        }
        let parts = userHost.split(separator: "@", maxSplits: 1)
        let user: String
        let hostName: String
        if parts.count == 2 {
            user = String(parts[0])
            hostName = String(parts[1])
        } else {
            user = NSUserName().isEmpty ? "mobile" : NSUserName()
            hostName = userHost
        }
        var host = SSHHost(name: hostName, hostname: hostName, port: port, username: user)
        if !remoteCommand.isEmpty {
            host.remoteCommand = remoteCommand
        }
        if name == "mosh" {
            host.useMosh = true
            if host.wantsTmuxControl {
                context.stderr(String(localized: "Shell.MoshTmux",
                                      defaultValue: "mosh cannot carry tmux control mode; connecting over SSH instead.\n",
                                      comment: "Warning when the user asks for mosh with a tmux -CC command"))
                host.useMosh = false
            }
        }
        _ = identity
        SSHLaunchMailbox.pending = SSHLaunchRequest(host: host, password: nil)
        context.stdout(String(localized: "Shell.SSHOpening",
                              defaultValue: "Opening SSH session to \(user)@\(hostName)…\n",
                              comment: "Local-shell confirmation that an ssh command is handing off to the terminal. %1$@ is the user, %2$@ is the host."))
        return 0
    }
}
