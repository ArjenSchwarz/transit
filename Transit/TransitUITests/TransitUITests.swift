import XCTest

final class TransitUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Helpers

    private func launchApp(scenario: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        if let scenario {
            app.launchEnvironment["TRANSIT_UI_TEST_SCENARIO"] = scenario
        } else {
            app.launchEnvironment["TRANSIT_UI_TEST_SCENARIO"] = "empty"
        }
        app.launch()
        return app
    }

    // MARK: - Empty States

    @MainActor
    func testEmptyDashboardShowsGlobalEmptyState() throws {
        let app = launchApp()

        // [req 20.1] Dashboard with zero tasks shows empty state
        let emptyStateText = app.staticTexts["No tasks yet. Tap + to create one."]
        XCTAssertTrue(emptyStateText.waitForExistence(timeout: 5))
    }

    @MainActor
    func testSettingsWithNoProjectsShowsCreatePrompt() throws {
        let app = launchApp()

        // Navigate to settings [req 12.1]
        let settingsButton = app.buttons["dashboard.settingsButton"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.tap()

        // [req 20.4] Settings with zero projects shows create prompt
        let prompt = app.staticTexts["Create your first project to get started."]
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
    }

    // MARK: - Navigation Flows

    @MainActor
    func testTappingGearPushesSettingsView() throws {
        let app = launchApp()

        let settingsButton = app.buttons["dashboard.settingsButton"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.tap()

        // [req 12.1] Settings view is pushed onto the navigation stack
        let settingsTitle = app.navigationBars["Settings"]
        XCTAssertTrue(settingsTitle.waitForExistence(timeout: 5))
    }

    @MainActor
    func testSettingsHasBackChevron() throws {
        let app = launchApp()

        app.buttons["dashboard.settingsButton"].tap()

        // [req 12.2] Chevron-only back button (no label text)
        let backButton = app.navigationBars["Settings"].buttons.element(boundBy: 0)
        XCTAssertTrue(backButton.waitForExistence(timeout: 5))
        backButton.tap()

        // Should return to dashboard
        let transitTitle = app.navigationBars["Transit"]
        XCTAssertTrue(transitTitle.waitForExistence(timeout: 5))
    }

    @MainActor
    func testTappingAddButtonOpensAddTaskSheet() throws {
        let app = launchApp()

        // [req 10.1] Tapping + opens the add task sheet
        let addButton = app.buttons["dashboard.addButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()

        // Sheet should show "New Task" title
        let sheetTitle = app.staticTexts["New Task"]
        XCTAssertTrue(sheetTitle.waitForExistence(timeout: 5))
    }

    @MainActor
    func testAddTaskWithNoProjectsShowsEmptyMessage() throws {
        let app = launchApp()

        app.buttons["dashboard.addButton"].tap()

        // [req 10.7, 20.3] No projects exist → shows message directing to Settings
        let message = app.staticTexts["No projects yet. Create one in Settings."]
        XCTAssertTrue(message.waitForExistence(timeout: 5))
    }

    @MainActor
    func testTappingFilterButtonShowsPopover() throws {
        let app = launchApp(scenario: "board")

        // [req 9.1] Tapping filter shows popover
        let filterButton = app.buttons["dashboard.filterButton"]
        XCTAssertTrue(filterButton.waitForExistence(timeout: 5))
        filterButton.tap()

        // Popover should contain a seeded project name
        let projectLabel = app.staticTexts["Alpha"]
        XCTAssertTrue(projectLabel.waitForExistence(timeout: 5))
    }

    // MARK: - Sheet Presentation with Data

    @MainActor
    func testTappingTaskCardOpensDetailSheet() throws {
        let app = launchApp(scenario: "board")

        // Wait for seeded task to appear
        let taskCard = app.staticTexts["Ship Active"]
        XCTAssertTrue(taskCard.waitForExistence(timeout: 5))
        taskCard.tap()

        // [req 6.4] Detail view opens showing the display ID
        let displayId = app.staticTexts["T-1"]
        XCTAssertTrue(displayId.waitForExistence(timeout: 5))
    }

    // MARK: - Default Segment

    @MainActor
    func testIPhonePortraitDefaultsToActiveSegment() throws {
        let app = launchApp()

        // [req 13.3] iPhone portrait default segment is "Active" (In Progress)
        let segmentedControl = app.segmentedControls.firstMatch
        if segmentedControl.waitForExistence(timeout: 5) {
            let activeSegment = segmentedControl.buttons.matching(
                NSPredicate(format: "label CONTAINS 'Active'")
            ).firstMatch
            XCTAssertTrue(activeSegment.exists)
            XCTAssertTrue(activeSegment.isSelected)
        }
        // On wider devices (iPad), segmented control may not appear — test passes implicitly
    }

    // MARK: - Filter Badge

    @MainActor
    func testFilterBadgeUpdatesWhenProjectSelected() throws {
        let app = launchApp(scenario: "board")

        // Initially no filter badge
        let filterButton = app.buttons["dashboard.filterButton"]
        XCTAssertTrue(filterButton.waitForExistence(timeout: 5))
        filterButton.tap()

        // Select the project in the popover
        let projectRow = app.staticTexts["Alpha"]
        XCTAssertTrue(projectRow.waitForExistence(timeout: 5))
        projectRow.tap()

        // Dismiss popover by tapping elsewhere
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.1)).tap()

        // [req 9.3] Filter button should now show count
        let updatedFilter = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Filter (1)'")
        ).firstMatch
        XCTAssertTrue(updatedFilter.waitForExistence(timeout: 5))
    }

    // MARK: - Abandoned Task Opacity

    @MainActor
    func testAbandonedTaskCardIsVisible() throws {
        let app = launchApp(scenario: "board")

        // Navigate to the Done/Abandoned column if on iPhone (segmented control)
        let segmentedControl = app.segmentedControls.firstMatch
        if segmentedControl.waitForExistence(timeout: 3) {
            let doneSegment = segmentedControl.buttons.matching(
                NSPredicate(format: "label CONTAINS 'Done'")
            ).firstMatch
            if doneSegment.exists {
                doneSegment.tap()
            }
        }

        // [req 5.7] Abandoned task should be present (rendered at 50% opacity)
        // XCUITest cannot directly verify opacity, but we verify the task card exists
        let abandonedTask = app.staticTexts["Old Abandoned"]
        XCTAssertTrue(abandonedTask.waitForExistence(timeout: 5))
    }
}
