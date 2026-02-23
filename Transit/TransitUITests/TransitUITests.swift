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
    func testProjectFilterMenu() throws {
        let app = launchApp(scenario: "board")

        let projectFilter = app.buttons["dashboard.filter.projects"]
        XCTAssertTrue(projectFilter.waitForExistence(timeout: 5))
        projectFilter.tap()

        let alphaOption = app.buttons["Alpha"]
        XCTAssertTrue(alphaOption.waitForExistence(timeout: 5))
        alphaOption.tap()

        XCTAssertTrue(app.staticTexts["Ship Active"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Beta Review"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testTypeFilterMenu() throws {
        let app = launchApp(scenario: "board")

        let typeFilter = app.buttons["dashboard.filter.types"]
        XCTAssertTrue(typeFilter.waitForExistence(timeout: 5))
        typeFilter.tap()

        let bugOption = app.buttons["Bug"]
        XCTAssertTrue(bugOption.waitForExistence(timeout: 5))
        bugOption.tap()

        XCTAssertTrue(app.staticTexts["Beta Review"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Ship Active"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testMilestoneFilterMenu() throws {
        let app = launchApp(scenario: "board")

        let projectFilter = app.buttons["dashboard.filter.projects"]
        XCTAssertTrue(projectFilter.waitForExistence(timeout: 5))
        projectFilter.tap()
        app.buttons["Alpha"].tap()

        let milestoneFilter = app.buttons["dashboard.filter.milestones"]
        XCTAssertTrue(milestoneFilter.waitForExistence(timeout: 5))
        milestoneFilter.tap()

        let milestoneOption = app.buttons["v1.0"]
        XCTAssertTrue(milestoneOption.waitForExistence(timeout: 5))
        milestoneOption.tap()

        XCTAssertTrue(app.staticTexts["Ship Active"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Backlog Idea"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Beta Review"].waitForExistence(timeout: 2))
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

    // MARK: - Filter Menus

    @MainActor
    func testClearAll() throws {
        let app = launchApp(scenario: "board")

        let projectFilter = app.buttons["dashboard.filter.projects"]
        XCTAssertTrue(projectFilter.waitForExistence(timeout: 5))
        projectFilter.tap()
        app.buttons["Alpha"].tap()

        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("Ship")

        let clearAll = app.buttons["dashboard.clearAllFilters"]
        XCTAssertTrue(clearAll.waitForExistence(timeout: 5))
        clearAll.tap()

        XCTAssertTrue(app.staticTexts["Ship Active"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Backlog Idea"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Beta Review"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testMilestoneHiddenWhenNoMilestones() throws {
        let app = launchApp()
        XCTAssertFalse(app.buttons["dashboard.filter.milestones"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testMilestoneClearedOnProjectChange() throws {
        let app = launchApp(scenario: "board")

        let projectFilter = app.buttons["dashboard.filter.projects"]
        XCTAssertTrue(projectFilter.waitForExistence(timeout: 5))
        projectFilter.tap()
        app.buttons["Alpha"].tap()

        let milestoneFilter = app.buttons["dashboard.filter.milestones"]
        XCTAssertTrue(milestoneFilter.waitForExistence(timeout: 5))
        milestoneFilter.tap()
        app.buttons["v1.0"].tap()

        projectFilter.tap()
        app.buttons["Beta"].tap()
        app.buttons["Alpha"].tap()

        XCTAssertTrue(app.staticTexts["Beta Review"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Ship Active"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testPerFilterClear() throws {
        let app = launchApp(scenario: "board")

        let projectFilter = app.buttons["dashboard.filter.projects"]
        XCTAssertTrue(projectFilter.waitForExistence(timeout: 5))
        projectFilter.tap()
        app.buttons["Alpha"].tap()

        let typeFilter = app.buttons["dashboard.filter.types"]
        XCTAssertTrue(typeFilter.waitForExistence(timeout: 5))
        typeFilter.tap()
        app.buttons["Bug"].tap()

        projectFilter.tap()
        app.buttons["Clear"].tap()

        XCTAssertTrue(app.staticTexts["Beta Review"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Ship Active"].waitForExistence(timeout: 2))
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
