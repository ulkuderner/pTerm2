import XCTest

final class PadFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLocalShellAndTabs() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["Hosts"].waitForExistence(timeout: 10))

        openTab("Shell", in: app)
        let field = app.textFields["Command"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))

        field.tap()
        field.typeText("help\n")
        XCTAssertTrue(output(in: app, containing: "nslookup").waitForExistence(timeout: 5))

        field.tap()
        field.typeText("git init\n")
        XCTAssertTrue(output(in: app, containing: "Initialized empty Git repository").waitForExistence(timeout: 5))

        field.tap()
        field.typeText("python3 -c \"print(42)\"\n")
        XCTAssertTrue(output(in: app, containing: "42").waitForExistence(timeout: 5))

        openTab("Settings", in: app)
        XCTAssertTrue(app.staticTexts["libssh2"].waitForExistence(timeout: 5))
        XCTAssertTrue(output(in: app, containing: "download_frameworks.sh").waitForExistence(timeout: 5))

        openTab("Keys", in: app)
        XCTAssertTrue(app.buttons["Import Key"].waitForExistence(timeout: 5))

        openTab("Hosts", in: app)
        let addHost = app.navigationBars.buttons["Add Host"]
        if addHost.exists {
            addHost.tap()
        } else {
            app.buttons["Add Host"].firstMatch.tap()
        }
        XCTAssertTrue(app.navigationBars["New Host"].waitForExistence(timeout: 5))
    }

    private func openTab(_ title: String, in app: XCUIApplication) {
        let candidates = [
            app.tabBars.buttons[title],
            app.buttons[title],
            app.staticTexts[title],
            app.cells[title]
        ]
        if let match = candidates.first(where: { $0.exists }) {
            match.tap()
            return
        }
        let labeled = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", title)).firstMatch
        XCTAssertTrue(labeled.waitForExistence(timeout: 3), "Missing \(title)")
        labeled.tap()
    }

    private func output(in app: XCUIApplication, containing needle: String) -> XCUIElement {
        app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", needle)).firstMatch
    }
}
