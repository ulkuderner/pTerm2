import Foundation
import PadSystem

public final class ShellSession: @unchecked Sendable {
    public let registry = CommandRegistry()
    public private(set) var context: CommandContext
    public var output: ((String) -> Void)?

    public init(home: URL) {
        let documents = home
        context = CommandContext(
            home: documents,
            workingDirectory: documents,
            environment: [
                "HOME": documents.path,
                "PATH": "/usr/bin:/bin:\(documents.appendingPathComponent("Library/bin").path)",
                "TERM": "xterm-256color"
            ],
            stdout: { _ in },
            stderr: { _ in }
        )
        context.stdout = { [weak self] text in self?.output?(text) }
        context.stderr = { [weak self] text in self?.output?(text) }
        registry.initializeIOSSystem(home: documents)
        try? FileManager.default.createDirectory(at: documents.appendingPathComponent("Library/bin"),
                                                 withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: documents.appendingPathComponent("mnt"),
                                                 withIntermediateDirectories: true)
    }

    public func run(_ line: String) -> Int32 {
        registry.run(line, context: &context)
    }

    public func prompt() -> String {
        let path = context.workingDirectory.path
        let home = context.home.path
        let short = path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
        return "\(short) $ "
    }

    public var iosSystemReady: Bool {
        pad_ios_system_ready() != 0
    }
}

public enum NativeBackends {
    public static var iosSystem: Bool { pad_ios_system_ready() != 0 }
    public static var python: Bool { pad_python3_ready() != 0 }
}
