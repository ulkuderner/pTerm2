import XCTest
import TmuxControl

final class TmuxGatewayAppTests: XCTestCase {
    func testLayoutChangeNotification() {
        let gateway = TmuxGateway()
        var seen: [TmuxNotification] = []
        gateway.onNotification = { seen.append($0) }
        gateway.ingest(Data("%layout-change @3 d1fd,80x24,0,0,0\n".utf8))
        guard case .layoutChange(let window, let layout, _, _) = seen.first else {
            XCTFail("expected layout-change")
            return
        }
        XCTAssertEqual(window, 3)
        XCTAssertTrue(layout.contains("80x24"))
        XCTAssertNotNil(TmuxLayoutParser.parsedLayout(from: layout))
    }
}
