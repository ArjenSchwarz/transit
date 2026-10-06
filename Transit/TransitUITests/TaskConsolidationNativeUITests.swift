import XCTest

final class TaskConsolidationNativeUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor func testSavedReasonAccountingAndOriginalNavigation() throws {
        let app = XCUIApplication()
        app.launchEnvironment["TRANSIT_PERSISTENCE_MODE"] = "ui-test"
        app.launchEnvironment["TRANSIT_UI_TEST_SCENARIO"] = "consolidationHistory"
        app.launch()
        defer { app.terminate() }
        let survivor = app.staticTexts["History Survivor"]
        XCTAssertTrue(survivor.waitForExistence(timeout: 5))
        survivor.tap()
        let reason = app.buttons["Synthetic reviewed history"]
        reveal(reason, in: app)
        XCTAssertTrue(reason.waitForExistence(timeout: 5))
        reason.tap()
        XCTAssertTrue(app.staticTexts["Applied"].waitForExistence(timeout: 5))
        let accounting = app.buttons["Preservation accounting"]
        reveal(accounting, in: app)
        XCTAssertTrue(accounting.waitForExistence(timeout: 5))
        accounting.tap()
        let retained = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@",
            "Original description remains available")).firstMatch
        reveal(retained, in: app)
        XCTAssertTrue(retained.waitForExistence(timeout: 5))
        let original = app.buttons["Original task: History Original · 00000000-0000-0000-0000-000000238102"]
        reveal(original, in: app)
        XCTAssertTrue(original.waitForExistence(timeout: 5))
        original.tap()
        let history = app.staticTexts["consolidation.history.00000000-0000-0000-0000-000000238102"]
        reveal(history, in: app)
        XCTAssertTrue(history.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Undo consolidation"].exists)
    }

    @MainActor func testRenderedReversedHistory() throws {
        let app = launchHistory("consolidationHistoryReversed")
        defer { app.terminate() }
        let reason = app.buttons["Synthetic reviewed history"]
        reveal(reason, in: app)
        XCTAssertTrue(reason.waitForExistence(timeout: 5))
        reason.tap()
        XCTAssertTrue(app.staticTexts["Reversed"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Whole reversal unavailable: already_reversed"].exists)
        XCTAssertFalse(app.buttons["Undo consolidation"].exists)
    }

    @MainActor func testRenderedUnavailableAndOverLimitHistory() throws {
        for (scenario, message) in [
            ("consolidationHistoryUnavailable", "Saved consolidation history is unavailable."),
            ("consolidationHistoryOverLimit", "Complete saved consolidation history exceeds the 16 MiB read limit.")
        ] {
            let app = launchHistory(scenario)
            let problem = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", message)).firstMatch
            reveal(problem, in: app)
            XCTAssertTrue(problem.waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["Synthetic reviewed history"].exists)
            app.terminate()
        }
    }

    @MainActor func testRenderedMissingAndAmbiguousOriginalReferences() throws {
        for scenario in ["consolidationHistoryMissing", "consolidationHistoryAmbiguous"] {
            let app = launchHistory(scenario)
            let reason = app.buttons["Synthetic reviewed history"]
            reveal(reason, in: app)
            XCTAssertTrue(reason.waitForExistence(timeout: 5))
            reason.tap()
            let unresolved = app.staticTexts["Unresolved original task: 00000000-0000-0000-0000-000000238102"]
            reveal(unresolved, in: app)
            XCTAssertTrue(unresolved.waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["Original task: History Original · 00000000-0000-0000-0000-000000238102"].exists)
            app.terminate()
        }
    }

    @MainActor private func launchHistory(_ scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TRANSIT_PERSISTENCE_MODE"] = "ui-test"
        app.launchEnvironment["TRANSIT_UI_TEST_SCENARIO"] = scenario
        app.launch()
        let survivor = app.staticTexts["History Survivor"]
        XCTAssertTrue(survivor.waitForExistence(timeout: 5))
        survivor.tap()
        return app
    }

    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 where !element.isHittable {
            #if os(macOS)
            app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -300)
            #else
            app.swipeUp()
            #endif
        }
    }
}
