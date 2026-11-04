import XCTest

/// Smoke tests for the main flows. Each test launches the app on the fake
/// device from `UIFixture`, so no Pulsetto and no Bluetooth are needed.
@MainActor
final class SessionFlowUITests: XCTestCase {
    private let wait: TimeInterval = 10

    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ state: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiState", state]
        app.launch()
        return app
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    private func waitFor(_ el: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(el.waitForExistence(timeout: wait), "missing \(el)", file: file, line: line)
    }

    func testStartPauseResumeStop() {
        let app = launch("idle")
        let start = element(app, "session.start")
        waitFor(start)
        start.tap()

        let pauseResume = element(app, "session.pauseResume")
        waitFor(pauseResume)
        XCTAssertEqual(pauseResume.label, "Pause session")

        pauseResume.tap()
        XCTAssertTrue(app.buttons["Resume session"].waitForExistence(timeout: wait))

        pauseResume.tap()
        XCTAssertTrue(app.buttons["Pause session"].waitForExistence(timeout: wait))

        element(app, "session.stop").tap()
        waitFor(element(app, "session.start"))
    }

    func testChangeModeFromSheet() {
        let app = launch("idle")
        let hero = element(app, "idle.modeHero")
        waitFor(hero)
        XCTAssertTrue(hero.label.hasPrefix("Stress"), hero.label)

        hero.tap()
        let sleep = app.buttons["Sleep"].firstMatch
        waitFor(sleep)
        sleep.tap()

        let switched = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label BEGINSWITH 'Sleep'"),
            object: element(app, "idle.modeHero")
        )
        XCTAssertEqual(XCTWaiter().wait(for: [switched], timeout: wait), .completed)
    }

    func testIntensityAdjusts() {
        let app = launch("idle")
        let intensity = element(app, "session.intensity")
        waitFor(intensity)
        let before = intensity.value as? String
        // The row is one adjustable element. The plus button is at its right end.
        intensity.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        let after = element(app, "session.intensity").value as? String
        XCTAssertNotEqual(before, after)
    }

    func testAddMinuteWhileRunning() {
        let app = launch("running")
        let clock = element(app, "session.clock")
        waitFor(clock)
        let minutes = { (label: String) in Int(label.prefix { $0.isNumber }) ?? -1 }
        let before = minutes(clock.label)

        app.buttons["Add one minute"].tap()

        XCTAssertEqual(minutes(element(app, "session.clock").label), before + 1)
    }

    func testBluetoothOffBlocksStart() {
        let app = launch("bluetoothOff")
        let start = element(app, "session.start")
        waitFor(start)
        XCTAssertFalse(start.isEnabled)
        XCTAssertTrue(app.staticTexts["Turn on Bluetooth in Control Center."].exists)
    }

    func testHistoryAndSettingsOpen() {
        let app = launch("idle")
        waitFor(element(app, "session.start"))

        app.buttons["History"].tap()
        waitFor(app.staticTexts["This week"])
        app.buttons["Done"].firstMatch.tap()

        app.buttons["Settings"].tap()
        waitFor(app.staticTexts["Tapper"])
    }
}
