import XCTest

final class PreparationUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }
    private func setEndpoint(_ value: String) {
        // Use the launch argument defaults domain for deterministic fixtures.
        // Deleting characters from a tapped URL can leave a suffix when iOS
        // places the insertion point in the middle of the existing value.
        app.terminate()
        app.launchArguments = ["-serverURL", value, "-serverToken", ""]
        app.launch()
        let field = app.textFields["serverEndpoint"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        XCTAssertEqual(field.value as? String, value)
        field.tap()
    }
    func testBothSidesOfPrepareButtonHandleTapAndDismissKeyboard() {
        setEndpoint("http://invalid.example")
        let button = app.buttons["prepareDetection"]
        XCTAssertTrue(button.waitForExistence(timeout: 3))
        for x in [0.1, 0.9] {
            button.coordinate(withNormalizedOffset: CGVector(dx: x, dy: 0.5)).tap()
            let alert = app.alerts["탐지 준비 확인"]
            XCTAssertTrue(alert.waitForExistence(timeout: 5), "Full button width must handle taps and show validation feedback")
            XCTAssertTrue(alert.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "HTTPS")).firstMatch.exists)
            alert.buttons["확인"].tap()
        }
        XCTAssertFalse(app.keyboards.firstMatch.exists)
    }
    func testValidServerRequiresKeyBeforeOpeningSystemBroadcast() {
        setEndpoint("https://reelproof-evidence.vercel.app")
        app.buttons["prepareDetection"].tap()
        // No secret or live API call: no active/recording state before a key and
        // the real extension's status signal. Preparing is not detecting.
        XCTAssertTrue(app.alerts["탐지 준비 확인"].waitForExistence(timeout: 5))
        let visible = app.alerts.staticTexts.allElementsBoundByIndex.map { $0.label }.joined(separator: "\n")
        XCTAssertTrue(visible.contains("접근 키"), visible)
        XCTAssertFalse(app.otherElements["broadcastControls"].exists)
        XCTAssertFalse(app.staticTexts["detectionActive"].exists)
    }
    func testContentLinkEntryRejectsInvalidURLWithoutNetwork() {
        let entry = app.buttons["openContentLink"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        entry.tap()
        let field = app.textFields["contentURL"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("http://invalid.example")
        app.buttons["verifyContentLink"].tap()
        XCTAssertTrue(app.staticTexts["contentLinkStatus"].label.contains("HTTPS"))
    }

}
