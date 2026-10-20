import XCTest
@testable import SSHClient

final class SSHClientTests: XCTestCase {
    func testTmuxCommandDetection() {
        let host = SSHHost(name: "box", hostname: "example.com", username: "me")
        XCTAssertTrue(host.wantsTmuxControl)
        let plain = SSHHost(name: "box",
                            hostname: "example.com",
                            username: "me",
                            remoteCommand: "")
        XCTAssertFalse(plain.wantsTmuxControl)
    }

    func testConnectWithoutBackendReportsMissing() {
        let session = SSHSession()
        let host = SSHHost(name: "box", hostname: "127.0.0.1", username: "me")
        if SSHSession.backendReady {
            return
        }
        XCTAssertThrowsError(try session.connect(host: host, privateKeyPEM: nil, password: "x")) { error in
            XCTAssertEqual(error as? SSHClientError, .backendMissing)
        }
    }
}
