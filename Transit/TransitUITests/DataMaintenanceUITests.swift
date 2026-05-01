import XCTest

/// UI tests for the Data Maintenance screen golden path: open Settings,
/// scan for duplicate display IDs, confirm the destructive reassignment alert,
/// and verify the result view renders.
///
/// Element identification uses accessibility identifiers exclusively (per
/// `rules/language-rules/swift.md`). Identifiers used here MUST stay in sync
/// with `Views/Settings/DataMaintenanceView.swift` and `SettingsView.swift`:
///   - `dataMaintenance.row` (NavigationLink in iOS Settings)
///   - `dataMaintenance.scanButton`
///   - `dataMaintenance.reassignButton`
///   - `dataMaintenance.confirmButton`
///   - `dataMaintenance.resultList`
final class DataMaintenanceUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchApp(scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TRANSIT_UI_TEST_SCENARIO"] = scenario
        app.launch()
        return app
    }

    @MainActor
    func testDataMaintenanceGoldenPath() throws {
        let app = launchApp(scenario: "duplicateDisplayIds")

        // Open Settings from the dashboard toolbar.
        let settingsButton = app.buttons["dashboard.settingsButton"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.tap()

        // Navigate to Data Maintenance via the iOS Settings list using the
        // dataMaintenance.row accessibility identifier on the NavigationLink.
        let dataMaintenanceRow = app.buttons["dataMaintenance.row"]
        XCTAssertTrue(dataMaintenanceRow.waitForExistence(timeout: 5))
        dataMaintenanceRow.tap()

        // Tap the scan button (accessibility identifier).
        let scanButton = app.buttons["dataMaintenance.scanButton"]
        XCTAssertTrue(scanButton.waitForExistence(timeout: 5))
        scanButton.tap()

        // After scan, the Reassign Losers button should appear because the
        // seeded scenario produced at least one duplicate group.
        let reassignButton = app.buttons["dataMaintenance.reassignButton"]
        XCTAssertTrue(
            reassignButton.waitForExistence(timeout: 5),
            "Reassign button should appear when scan finds at least one group"
        )
        reassignButton.tap()

        // Confirmation alert with destructive primary action.
        let confirmButton = app.buttons["dataMaintenance.confirmButton"]
        XCTAssertTrue(
            confirmButton.waitForExistence(timeout: 5),
            "Confirmation alert should appear with destructive primary button"
        )
        confirmButton.tap()

        // Result list view appears with per-group outcomes.
        let resultList = app.otherElements["dataMaintenance.resultList"]
        XCTAssertTrue(
            resultList.waitForExistence(timeout: 10),
            "Result list should appear after reassignment completes"
        )
    }
}
