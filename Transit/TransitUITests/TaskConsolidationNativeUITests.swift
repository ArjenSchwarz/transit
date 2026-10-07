import XCTest

final class TaskConsolidationNativeUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor func testSavedReasonAccountingAndOriginalNavigation() throws {
        let app = launchHistory("consolidationHistory")
        defer { app.terminate() }
        let reason = disclosure("Synthetic reviewed history", in: app)
        reveal(reason, in: app)
        XCTAssertTrue(reason.waitForExistence(timeout: 5))
        XCTAssertEqual(reason.label, "Synthetic reviewed history")
        activate(reason)
        let applied = historyContainer(in: app).staticTexts["Applied"]
        reveal(applied, in: app)
        XCTAssertTrue(applied.waitForExistence(timeout: 5))
        let accounting = disclosure("Preservation accounting", in: app)
        reveal(accounting, in: app)
        XCTAssertTrue(accounting.waitForExistence(timeout: 5))
        XCTAssertEqual(accounting.label, "Preservation accounting")
        activate(accounting)
        assertExpanded(accounting)
        assertRetainedExplanation(in: app)
        let changes = disclosure("Saved changes: 00000000-0000-0000-0000-000000238102", in: app)
        reveal(changes, in: app)
        XCTAssertTrue(changes.waitForExistence(timeout: 5))
        activate(changes)
        let status = historyContainer(in: app).staticTexts["statusRawValue: idea → abandoned"]
        reveal(status, in: app)
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        #if os(macOS)
        XCTAssertEqual(status.value as? String, "statusRawValue: idea → abandoned")
        #else
        XCTAssertEqual(status.label, "statusRawValue: idea → abandoned")
        #endif
        let recordedSurvivor = historyContainer(in: app).buttons[
            "Recorded canonical task: History Survivor · 00000000-0000-0000-0000-000000238101"].firstMatch
        reveal(recordedSurvivor, in: app)
        XCTAssertTrue(recordedSurvivor.waitForExistence(timeout: 5))
        XCTAssertEqual(recordedSurvivor.label,
            "Recorded canonical task: History Survivor · 00000000-0000-0000-0000-000000238101")
        let original = historyContainer(in: app)
            .buttons["Original task: History Original · 00000000-0000-0000-0000-000000238102"]
        reveal(original, in: app, towardEarlierContent: true)
        XCTAssertTrue(original.waitForExistence(timeout: 5))
        XCTAssertEqual(original.label, "Original task: History Original · 00000000-0000-0000-0000-000000238102")
        activate(original)
        let history = historyContainer(in: app, taskID: "00000000-0000-0000-0000-000000238102")
            .staticTexts["consolidation.history.00000000-0000-0000-0000-000000238102"]
        reveal(history, in: app, taskID: "00000000-0000-0000-0000-000000238102")
        XCTAssertTrue(history.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Undo consolidation"].exists)
    }

    @MainActor func testRenderedReversedHistory() throws {
        let app = launchHistory("consolidationHistoryReversed")
        defer { app.terminate() }
        let reason = disclosure("Synthetic reviewed history", in: app)
        reveal(reason, in: app)
        XCTAssertTrue(reason.waitForExistence(timeout: 5))
        XCTAssertEqual(reason.label, "Synthetic reviewed history")
        activate(reason)
        let reversed = historyContainer(in: app).staticTexts["Reversed"]
        reveal(reversed, in: app)
        XCTAssertTrue(reversed.waitForExistence(timeout: 5))
        let unavailable = historyContainer(in: app).staticTexts["Whole reversal unavailable: already_reversed"]
        reveal(unavailable, in: app)
        XCTAssertTrue(unavailable.exists)
        XCTAssertFalse(app.buttons["Undo consolidation"].exists)
    }

    @MainActor func testRenderedUnavailableAndOverLimitHistory() throws {
        for (scenario, message) in [
            ("consolidationHistoryUnavailable", "Saved consolidation history is unavailable."),
            ("consolidationHistoryOverLimit", "Complete saved consolidation history exceeds the 16 MiB read limit.")
        ] {
            let app = launchHistory(scenario)
            #if os(macOS)
            let problem = historyContainer(in: app).staticTexts[message]
            #else
            let problem = historyContainer(in: app).staticTexts
                .containing(NSPredicate(format: "label CONTAINS %@", message)).firstMatch
            #endif
            reveal(problem, in: app)
            XCTAssertTrue(problem.waitForExistence(timeout: 5))
            #if os(macOS)
            XCTAssertEqual(problem.value as? String, message)
            #endif
            XCTAssertFalse(disclosure("Synthetic reviewed history", in: app).exists)
            app.terminate()
        }
    }

    @MainActor func testRenderedMissingAndAmbiguousOriginalReferences() throws {
        for scenario in ["consolidationHistoryMissing", "consolidationHistoryAmbiguous"] {
            let app = launchHistory(scenario)
            let reason = disclosure("Synthetic reviewed history", in: app)
            reveal(reason, in: app)
            XCTAssertTrue(reason.waitForExistence(timeout: 5))
            XCTAssertEqual(reason.label, "Synthetic reviewed history")
            activate(reason)
            let unresolved = historyContainer(in: app)
                .staticTexts["Unresolved original task: 00000000-0000-0000-0000-000000238102"]
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
        #if os(macOS)
        let survivor = app.windows.containing(.button, identifier: "dashboard.addButton")
            .firstMatch.staticTexts["History Survivor"]
        #else
        let survivor = app.staticTexts["History Survivor"]
        #endif
        XCTAssertTrue(survivor.waitForExistence(timeout: 5))
        activate(survivor)
        #if os(macOS)
        XCTAssertTrue(historyWindow(in: app).waitForExistence(timeout: 5),
                      "The exact saved survivor detail window must open before history interaction")
        #endif
        return app
    }

    @MainActor private func assertRetainedExplanation(in app: XCUIApplication) {
        let explanation = "Original description remains available"
        #if os(macOS)
        let retained = historyContainer(in: app)
            .staticTexts["consolidation.preservation.00000000-0000-0000-0000-000000238100"]
        #else
        let retained = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", explanation)).firstMatch
        #endif
        reveal(retained, in: app)
        XCTAssertTrue(retained.waitForExistence(timeout: 5))
        #if os(macOS)
        XCTAssertTrue((retained.value as? String)?.contains(explanation) == true)
        #endif
    }

    @MainActor private func historyContainer(
        in app: XCUIApplication,
        taskID: String = "00000000-0000-0000-0000-000000238101"
    ) -> XCUIElement {
        #if os(macOS)
        historyWindow(in: app, taskID: taskID)
        #else
        app
        #endif
    }

    @MainActor private func disclosure(_ title: String, in app: XCUIApplication) -> XCUIElement {
        #if os(macOS)
        historyWindow(in: app).disclosureTriangles[title]
        #else
        app.buttons[title]
        #endif
    }

    @MainActor private func assertExpanded(_ element: XCUIElement) {
        #if os(macOS)
        XCTAssertEqual((element.value as? NSNumber)?.intValue, 1)
        #else
        XCTAssertEqual(element.value as? String, "Expanded")
        #endif
    }

    @MainActor private func activate(_ element: XCUIElement) {
        #if os(macOS)
        if element.elementType == .disclosureTriangle {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5))
                .withOffset(CGVector(dx: 28, dy: 0)).click()
        } else {
            element.click()
        }
        #else
        element.tap()
        #endif
    }

    #if os(macOS)
    @MainActor private func historyWindow(
        in app: XCUIApplication,
        taskID: String = "00000000-0000-0000-0000-000000238101"
    ) -> XCUIElement {
        app.windows.containing(.staticText, identifier: "consolidation.history.\(taskID)").firstMatch
    }
    #endif

    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication,
                                   towardEarlierContent: Bool = false,
                                   taskID: String = "00000000-0000-0000-0000-000000238101") {
        for _ in 0..<8 where !element.isHittable {
            #if os(macOS)
            let window = historyWindow(in: app, taskID: taskID)
            XCTAssertTrue(window.waitForExistence(timeout: 5),
                          "The exact saved task detail window must exist before scrolling")
            guard window.exists else { return }
            window.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: towardEarlierContent ? 300 : -300)
            #else
            if towardEarlierContent { app.swipeDown() } else { app.swipeUp() }
            #endif
        }
    }
}
