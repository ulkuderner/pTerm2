import XCTest
@testable import iTerm2Pad
import SSHClient

final class HostStoreTests: XCTestCase {
    func testUpsertAndDelete() {
        let suite = "HostStoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("defaults")
            return
        }
        defaults.removePersistentDomain(forName: suite)
        let original = UserDefaults.standard.data(forKey: HostStore.hostsKey)
        defer {
            if let original {
                UserDefaults.standard.set(original, forKey: HostStore.hostsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: HostStore.hostsKey)
            }
        }
        UserDefaults.standard.removeObject(forKey: HostStore.hostsKey)
        let store = HostStore()
        let host = SSHHost(name: "lab", hostname: "lab.example", username: "me")
        store.upsert(host)
        XCTAssertEqual(store.hosts().count, 1)
        XCTAssertEqual(store.hosts().first?.hostname, "lab.example")
        store.delete(host)
        XCTAssertTrue(store.hosts().isEmpty)
    }
}
