import XCTest
@testable import LocalShell

final class CommandRegistryTests: XCTestCase {
    func testPWDAndEcho() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        var captured = ""
        var context = CommandContext(home: home, workingDirectory: home, stdout: { captured += $0 }, stderr: { captured += $0 })
        let registry = CommandRegistry()
        XCTAssertEqual(registry.run("pwd", context: &context), 0)
        XCTAssertTrue(captured.contains(home.path))
        captured = ""
        XCTAssertEqual(registry.run("echo hello world", context: &context), 0)
        XCTAssertEqual(captured, "hello world\n")
    }

    func testGitInitStatusCommit() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        var captured = ""
        var context = CommandContext(home: home, workingDirectory: home, stdout: { captured += $0 }, stderr: { captured += $0 })
        let registry = CommandRegistry()
        XCTAssertEqual(registry.run("git init", context: &context), 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: home.appendingPathComponent(".git/HEAD").path))
        XCTAssertEqual(registry.run("touch readme", context: &context), 0)
        XCTAssertEqual(registry.run("git add readme", context: &context), 0)
        XCTAssertEqual(registry.run("git commit -m first", context: &context), 0)
        captured = ""
        XCTAssertEqual(registry.run("git log", context: &context), 0)
        XCTAssertTrue(captured.contains("first"))
    }

    func testSSHFSMountRoundTrip() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        var captured = ""
        var context = CommandContext(home: home, workingDirectory: home, stdout: { captured += $0 }, stderr: { captured += $0 })
        let registry = CommandRegistry()
        XCTAssertEqual(registry.run("sshfs me@example.com:/var/www web", context: &context), 0)
        XCTAssertTrue(SSHFSMountStore.load().contains(where: { $0.name == "web" }))
        XCTAssertEqual(registry.run("umount web", context: &context), 0)
        XCTAssertFalse(SSHFSMountStore.load().contains(where: { $0.name == "web" }))
    }

    func testUnknownCommand() {
        let home = FileManager.default.temporaryDirectory
        var captured = ""
        var context = CommandContext(home: home, workingDirectory: home, stdout: { captured += $0 }, stderr: { captured += $0 })
        let registry = CommandRegistry()
        XCTAssertEqual(registry.run("definitely-not-a-command", context: &context), 127)
    }
}
