import XCTest

@MainActor
final class TransitUITests: XCTestCase {
    private enum Scenario: String {
        case empty
        case board
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testEmptyStateAndNoProjectPrompt() {
        let app = launchApp(scenario: .empty)

        XCTAssertTrue(app.staticTexts["No tasks yet. Tap + to create one."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No tasks in In Progress"].exists)

        app.buttons["dashboard.addButton"].tap()
        XCTAssertTrue(app.alerts["Create a Project First"].waitForExistence(timeout: 3))
        app.alerts["Create a Project First"].buttons["OK"].tap()

        app.buttons["dashboard.settingsButton"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No projects yet. Tap + to create your first project."].exists)
    }

    func testNavigationAndSheetPresentationFlow() {
        let app = launchApp(scenario: .board)
        XCTAssertTrue(app.navigationBars["Transit"].waitForExistence(timeout: 5))

        XCTAssertEqual(app.segmentedControls["dashboard.segmentedControl"].value as? String, "inProgress")

        app.buttons["dashboard.addButton"].tap()
        XCTAssertTrue(app.navigationBars["New Task"].waitForExistence(timeout: 3))
        app.buttons["addTask.cancelButton"].tap()
        XCTAssertFalse(app.navigationBars["New Task"].waitForExistence(timeout: 1))

        app.staticTexts["Ship Active"].tap()
        XCTAssertTrue(app.otherElements["taskDetail.sheet"].waitForExistence(timeout: 3))
        app.swipeDown()
    }

    func testFilterBadgeAbandonedCardAndColumnEmptyState() {
        let app = launchApp(scenario: .board)

        tapSegment(prefix: "Done", in: app)

        XCTAssertTrue(app.staticTexts["Old Abandoned"].waitForExistence(timeout: 5))

        app.buttons["dashboard.filterButton"].tap()
        XCTAssertTrue(app.staticTexts["Projects"].waitForExistence(timeout: 3))
        app.buttons["Beta"].tap()
        app.buttons["dashboard.filterButton"].tap()

        XCTAssertEqual(app.buttons["dashboard.filterButton"].value as? String, "1")
    }

    private func launchApp(scenario: Scenario) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TRANSIT_UI_TEST_SCENARIO"] = scenario.rawValue
        app.launchEnvironment["TRANSIT_UI_FORCE_SINGLE_COLUMN"] = "1"
        app.launch()
        return app
    }

    private func tapSegment(prefix: String, in app: XCUIApplication) {
        let segmentButton = app.segmentedControls.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", prefix))
            .firstMatch
        XCTAssertTrue(segmentButton.waitForExistence(timeout: 3))
        segmentButton.tap()
    }
}
