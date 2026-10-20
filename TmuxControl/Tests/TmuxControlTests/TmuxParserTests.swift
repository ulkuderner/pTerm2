import XCTest
@testable import TmuxControl

final class TmuxParserTests: XCTestCase {
    func testStripsDCSHook() {
        let parser = TmuxLineParser()
        let hook = Data([0x1b, 0x50, 0x31, 0x30, 0x30, 0x30, 0x70])
        let rest = parser.consumeDCSPreamble(hook + Data("%session-changed 0 main\n".utf8))
        XCTAssertEqual(String(data: rest, encoding: .utf8), "%session-changed 0 main\n")
    }

    func testExitUnhooks() {
        let parser = TmuxLineParser()
        let lines = parser.feed(Data("%exit\n".utf8))
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].kind, .exit)
    }

    func testBeginEndBlock() {
        let parser = TmuxLineParser()
        var lines = parser.feed(Data("%begin 1 0\nhello\n%end 1 0\n".utf8))
        XCTAssertEqual(lines.map(\.text), ["%begin 1 0", "hello", "%end 1 0"])
        XCTAssertTrue(lines.allSatisfy { $0.kind == .line })
        lines = parser.feed(Data("%output %0 hi\n".utf8))
        XCTAssertEqual(lines.first?.text, "%output %0 hi")
    }

    func testExitInsideBlockOnOldServer() {
        let parser = TmuxLineParser()
        parser.serverMayOmitEndGuardBeforeExit = true
        let lines = parser.feed(Data("%begin 1 0\n%exit\n".utf8))
        XCTAssertEqual(lines.last?.kind, .exit)
    }

    func testExitInsideBlockOnModernServerIsData() {
        let parser = TmuxLineParser()
        parser.serverMayOmitEndGuardBeforeExit = false
        let lines = parser.feed(Data("%begin 1 0\n%exit\n%end 1 0\n".utf8))
        XCTAssertEqual(lines.map(\.kind), [.line, .line, .line])
        XCTAssertEqual(lines[1].text, "%exit")
    }

    func testDecodeOctalEscape() {
        let encoded = Data(#"hello\015world"#.utf8)
        let decoded = TmuxEscapedOutput.decode(encoded)
        XCTAssertEqual(decoded, Data("hello\rworld".utf8))
    }

    func testGatewayOutputNotification() {
        let gateway = TmuxGateway()
        var seen: [TmuxNotification] = []
        gateway.onNotification = { seen.append($0) }
        gateway.ingest(Data("%output %3 hello\\015\n".utf8))
        guard case .output(let pane, let data, _) = seen.first else {
            XCTFail("expected output")
            return
        }
        XCTAssertEqual(pane, 3)
        XCTAssertEqual(data, Data("hello\r".utf8))
    }

    func testGatewayCommandRoundTrip() {
        let gateway = TmuxGateway()
        var written: [String] = []
        gateway.attach { written.append($0) }
        var result: TmuxCommandResult?
        gateway.send("list-windows") { result = $0 }
        XCTAssertEqual(written, ["list-windows\n"])
        gateway.ingest(Data("%begin 1 0\n@0 main\n%end 1 0\n".utf8))
        guard case .success(let body) = result else {
            XCTFail("expected success")
            return
        }
        XCTAssertEqual(body, "@0 main")
    }

    func testPaneKeyMode() {
        XCTAssertEqual(TmuxPaneKeyMode.mode(for: "VT10x")?.modifyOtherKeys, 0)
        XCTAssertEqual(TmuxPaneKeyMode.mode(for: "Ext 2")?.modifyOtherKeys, 2)
        XCTAssertEqual(TmuxPaneKeyMode.mode(for: "Kitty 1")?.kittyFlags, 1)
        XCTAssertNil(TmuxPaneKeyMode.mode(for: "nope"))
    }

    func testStateParser() {
        let line = "pane_id=%4\tcursor_x=10\tcursor_y=3\twrap_flag=1\tpane_key_mode=Ext 1"
        let state = TmuxStateParser.parsedState(from: line, forPane: 4)
        XCTAssertEqual(state.paneID, 4)
        XCTAssertEqual(state.cursorX, 10)
        XCTAssertEqual(state.cursorY, 3)
        XCTAssertTrue(state.wrap)
        XCTAssertEqual(state.paneKeyMode, "Ext 1")
    }
}
