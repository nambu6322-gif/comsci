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
    func testValidServerShowsControlsOrQRKeyInstructionsWhenSharingIsMissing() {
        setEndpoint("https://reelproof-evidence.vercel.app")
        app.buttons["prepareDetection"].tap()
        // No secret, live API call or simulator entitlement grants are required.
        // Missing shared rights now direct users to QR pairing with an app key.
        let ready = NSPredicate { [self] _, _ in
            app.alerts["탐지 준비 확인"].exists || app.otherElements["broadcastControls"].exists
        }
        let expectation = XCTNSPredicateExpectation(predicate: ready, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
        if app.alerts["탐지 준비 확인"].exists {
            let visible = app.alerts.staticTexts.allElementsBoundByIndex.map { $0.label }.joined(separator: "\n")
            XCTAssertTrue(visible.contains("QR"), visible)
            XCTAssertTrue(visible.contains("접근 키"), visible)
        } else {
            XCTAssertTrue(app.otherElements["broadcastControls"].exists)
        }
    }
}
