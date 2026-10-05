import XCTest

final class TaskLinkNativeUITests: XCTestCase {
    private let targetID = "00000000-0000-0000-0000-000000173402"

    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor func testSavedRelationshipOpensExactUUIDDestination() throws {
        let app = launch(scenario: "taskLinks")
        let button = app.buttons["task-links.target.\(targetID)"]
        reveal(button, in: app)
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
        let destination = app.staticTexts["task-links.observation.\(targetID)"]
        reveal(destination, in: app)
        XCTAssertTrue(destination.waitForExistence(timeout: 5))
    }

    @MainActor func testAmbiguousDestinationIsDiagnosedWithoutArbitraryNavigation() throws {
        let app = launch(scenario: "taskLinksAmbiguous")
        let diagnostic = app.staticTexts["task-links.diagnostic.ambiguous_endpoint"]
        reveal(diagnostic, in: app)
        XCTAssertTrue(diagnostic.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["task-links.target.\(targetID)"].exists)
        XCTAssertFalse(app.staticTexts["task-links.observation.\(targetID)"].exists)
    }

    @MainActor private func launch(scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TRANSIT_PERSISTENCE_MODE"] = "ui-test"
        app.launchEnvironment["TRANSIT_UI_TEST_SCENARIO"] = scenario
        app.launch()
        let source = app.staticTexts["Linked Source"]
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        source.tap()
        return app
    }

    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 where !element.isHittable {
            app.swipeUp()
        }
    }
}
