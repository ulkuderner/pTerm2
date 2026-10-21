import XCTest

final class PadFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testIPadSandboxShell() throws {
        let app = XCUIApplication()
        app.launchArguments.append("-pterm-shell")
        app.launchArguments.append("-pterm-uitest")
        app.launch()

        let pane = app.descendants(matching: .any)["TerminalPane"]
        XCTAssertTrue(pane.waitForExistence(timeout: 20))
        let appeared = waitUntil(timeout: 25) {
            let text = self.screenText(pane)
            return text.contains("➜") && text.contains(".zshrc")
        }
        XCTAssertTrue(appeared, "sandbox shell did not list .zshrc: \(screenText(pane))")
        XCTAssertFalse(screenText(pane).localizedCaseInsensitiveContains("could not start"))
        XCTAssertFalse(screenText(pane).localizedCaseInsensitiveContains("sandbox shell"))
        let listing = screenText(pane)
        XCTAssertTrue(listing.contains("Application") || listing.contains("Containers"))
        XCTAssertFalse(listing.localizedCaseInsensitiveContains("operation not permitted"))
        XCTAssertFalse(listing.localizedCaseInsensitiveContains("permission denied"))
        XCTAssertFalse(listing.localizedCaseInsensitiveContains("izin"))

        app.typeKey("q", modifierFlags: .alternate)
        XCTAssertTrue(waitUntil(timeout: 4) {
            self.screenText(pane).contains("@")
        }, "option-q did not insert @: \(screenText(pane))")

        typeLine("echo COPYMARK", in: app)
        XCTAssertTrue(waitUntil(timeout: 6) { self.screenText(pane).contains("COPYMARK") })
        pane.press(forDuration: 1.2)
        let copy = app.menuItems["Copy"].firstMatch
        if copy.waitForExistence(timeout: 3) {
            copy.tap()
            app.typeKey("v", modifierFlags: .command)
            XCTAssertTrue(waitUntil(timeout: 4) {
                self.screenText(pane).components(separatedBy: "COPYMARK").count > 2
            }, "paste did not echo the copy: \(screenText(pane))")
        }

        app.typeKey("d", modifierFlags: .command)
        let divider = app.descendants(matching: .any)["PaneDivider"]
        XCTAssertTrue(divider.waitForExistence(timeout: 5))
        let before = divider.frame
        let start = divider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
        start.press(forDuration: 0.2, thenDragTo: end)
        let after = divider.frame
        XCTAssertGreaterThan(abs(after.origin.x - before.origin.x), 2)
    }

    private func screenText(_ element: XCUIElement) -> String {
        element.label
    }

    private func typeLine(_ text: String, in app: XCUIApplication) {
        app.typeText(text + "\n")
    }

    private func typeCommand(_ text: String, in app: XCUIApplication) {
        for character in text {
            if character == " " {
                app.typeKey(XCUIKeyboardKey.space.rawValue, modifierFlags: [])
            } else {
                app.typeKey(String(character), modifierFlags: [])
            }
        }
        let ret = app.keyboards.buttons["return"]
        if ret.waitForExistence(timeout: 2) {
            ret.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        app.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [])
    }

    private func waitUntil(timeout: TimeInterval, _ predicate: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate() {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        }
        return predicate()
    }

    func testSettingsTapStaysUp() throws {
        let app = XCUIApplication()
        app.launch()

        let settings = app.buttons.matching(identifier: "gearshape.fill").firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 8), "Settings tab is missing")
        settings.tap()
        XCTAssertTrue(app.staticTexts["libssh2"].waitForExistence(timeout: 5),
                      "Settings did not appear: \(app.debugDescription)")
        XCTAssertEqual(app.state, .runningForeground)

        openTab("Shell", in: app)
        let pane = app.descendants(matching: .any)["TerminalPane"]
        XCTAssertTrue(pane.waitForExistence(timeout: 15))
        app.buttons.matching(identifier: "gearshape.fill").firstMatch.tap()
        XCTAssertTrue(app.staticTexts["libssh2"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.state, .runningForeground)
    }

    func testTypedShellCommands() throws {
        try exerciseShell(extraArguments: ["-pterm-strip-env"])
    }

    func testInProcessShellCommands() throws {
        try exerciseShell(extraArguments: ["-pterm-strip-env", "-pterm-inprocess"])
    }

    private func exerciseShell(extraArguments: [String]) throws {
        let app = XCUIApplication()
        app.launchArguments += ["-pterm-shell", "-pterm-uitest"] + extraArguments
        app.launch()

        let pane = app.descendants(matching: .any)["TerminalPane"]
        XCTAssertTrue(pane.waitForExistence(timeout: 20))
        XCTAssertTrue(waitUntil(timeout: 25) {
            let text = self.screenText(pane)
            return text.contains("~") && text.contains("expand-or-complete") && !text.contains("localhost%") && !text.contains("set-mark-command")
        }, "shell startup did not finish: \(screenText(pane))")
        RunLoop.current.run(until: Date().addingTimeInterval(2))

        pane.tap()
        typeCommand("ls", in: app)
        XCTAssertTrue(waitUntil(timeout: 12) {
            let text = self.screenText(pane)
            return text.contains("Documents") && text.contains("opt")
        }, "ls printed nothing: \(screenText(pane))")

        typeCommand("git status", in: app)
        XCTAssertTrue(waitUntil(timeout: 12) {
            self.screenText(pane).localizedCaseInsensitiveContains("not a git repository")
        }, "git status missing: \(screenText(pane))")

        typeCommand("brew --prefix", in: app)
        XCTAssertTrue(waitUntil(timeout: 12) {
            self.screenText(pane).contains("opt/homebrew")
        }, "brew prefix missing: \(screenText(pane))")

        openTab("Settings", in: app)
        XCTAssertTrue(app.staticTexts["libssh2"].waitForExistence(timeout: 5),
                      "Settings crashed after the shell was used: \(app.debugDescription)")
        openTab("Keys", in: app)
        XCTAssertTrue(app.staticTexts["Keys"].waitForExistence(timeout: 5) || app.buttons["Import Key"].waitForExistence(timeout: 2))
        XCTAssertEqual(app.state, .runningForeground)
    }

    func testLocalShellAndTabs() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["Hosts"].waitForExistence(timeout: 10))

        openTab("Shell", in: app)
        let field = app.textFields["Command"]
        if field.waitForExistence(timeout: 2) {
            field.tap()
            field.typeText("help\n")
            XCTAssertTrue(output(in: app, containing: "nslookup").waitForExistence(timeout: 5))
            field.tap()
            field.typeText("git init\n")
            XCTAssertTrue(output(in: app, containing: "Initialized empty Git repository").waitForExistence(timeout: 5))
            field.tap()
            field.typeText("python3 -c \"print(42)\"\n")
            XCTAssertTrue(output(in: app, containing: "42").waitForExistence(timeout: 5))
        }

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
        let symbols = [
            "Hosts": "server.rack",
            "Shell": "terminal",
            "Keys": "key.fill",
            "Settings": "gearshape.fill"
        ]
        if let symbol = symbols[title] {
            let button = app.buttons.matching(identifier: symbol).firstMatch
            if button.waitForExistence(timeout: 3) {
                button.tap()
                return
            }
        }
        let labeled = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", title)).firstMatch
        XCTAssertTrue(labeled.waitForExistence(timeout: 3), "Missing \(title)")
        labeled.tap()
    }

    private func output(in app: XCUIApplication, containing needle: String) -> XCUIElement {
        app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", needle)).firstMatch
    }
}
