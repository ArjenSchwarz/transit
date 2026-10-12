import XCTest

final class BackupRecoveryUITests: XCTestCase {
    @MainActor
    func testRecoveryCompletionOffersCopyWhileEditingIsLocked() throws {
        let app = XCUIApplication()
        app.launchEnvironment["TRANSIT_PERSISTENCE_MODE"] = "ui-test"
        app.launchEnvironment["TRANSIT_UI_TEST_SCENARIO"] = "backupCompletion"
        app.launch()
        XCTAssertTrue(app.staticTexts["backup.completionTitle"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["backup.restartGuidance"].exists)
        let save = app.buttons["backup.saveRecovery"].firstMatch
        XCTAssertTrue(save.isEnabled)
        XCTAssertTrue(save.isHittable)
        XCTAssertFalse(app.buttons["dashboard.addButton"].exists)
        // Files owns its remote picker controls, which this runtime does not expose through the
        // application's accessibility tree. Copy/save/cancellation there require separate validation.
    }
}
