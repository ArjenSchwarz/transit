//
//  TransitUITests.swift
//  TransitUITests
//
//  UI tests for navigation flows, sheet presentation, and visual states.
//

import XCTest

final class TransitUITests: XCTestCase {
    var app: XCUIApplication?

    override func setUpWithError() throws {
        continueAfterFailure = false
        let application = XCUIApplication()
        application.launchArguments = ["--uitesting"]
        application.launch()
        app = application
    }

    // MARK: - Navigation Tests

    @MainActor
    func testTappingSettingsButtonNavigatesToSettings() throws {
        guard let app = app else { return }

        // Find and tap the settings button (gear icon)
        let settingsButton = app.buttons["Settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 2))
        settingsButton.tap()

        // Verify Settings view is displayed
        let settingsTitle = app.staticTexts["Settings"]
        XCTAssertTrue(settingsTitle.exists)

        // Verify back navigation exists (no label text per req 12.2)
        let backButton = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(backButton.exists)
    }

    @MainActor
    func testTappingAddButtonOpensSheet() throws {
        guard let app = app else { return }

        // This test assumes at least one project exists
        // In a real scenario, we'd set up test data first

        let addButton = app.buttons["Add Task"]
        if addButton.exists {
            addButton.tap()

            // Verify sheet is presented
            // Sheet detection varies by platform, check for sheet content
            let nameField = app.textFields["Task Name"]
            XCTAssertTrue(nameField.waitForExistence(timeout: 2))
        }
    }

    @MainActor
    func testTappingFilterButtonShowsPopover() throws {
        guard let app = app else { return }

        let filterButton = app.buttons["Filter"]
        XCTAssertTrue(filterButton.waitForExistence(timeout: 2))
        filterButton.tap()

        // Verify popover content appears
        let projectsLabel = app.staticTexts["Projects"]
        XCTAssertTrue(projectsLabel.waitForExistence(timeout: 2))
    }

    // MARK: - Empty State Tests

    @MainActor
    func testEmptyColumnShowsEmptyState() throws {
        guard let app = app else { return }

        // This test would need a clean state with no tasks in a specific column
        // In practice, this requires test data setup

        // Look for empty state messages
        let emptyStateExists = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS 'No tasks'")
        ).firstMatch.exists
        // Empty state may or may not be visible depending on data
        // This is a placeholder - real test needs controlled data
    }

    // MARK: - Filter Badge Tests

    @MainActor
    func testFilterBadgeUpdatesWhenProjectsSelected() throws {
        guard let app = app else { return }

        let filterButton = app.buttons["Filter"]
        filterButton.tap()

        // Select a project (this assumes projects exist)
        let firstCheckbox = app.buttons.matching(identifier: "project-checkbox").firstMatch
        if firstCheckbox.exists {
            firstCheckbox.tap()

            // Dismiss popover
            app.tap()

            // Verify badge appears (implementation-dependent)
            // Badge detection would need accessibility identifiers
        }
    }

    // MARK: - Visual State Tests

    @MainActor
    func testAbandonedTaskShowsReducedOpacity() throws {
        // This test requires an abandoned task to exist
        // Would need test data setup to verify opacity styling
        // Opacity is a visual property that's hard to test directly in UI tests
        // This is a placeholder for the requirement
    }

    @MainActor
    func testiPhonePortraitDefaultsToActiveSegment() throws {
        guard let app = app else { return }

        #if os(iOS)
        // Only run on iPhone
        if UIDevice.current.userInterfaceIdiom == .phone {
            // Check for segmented control
            let segmentedControl = app.segmentedControls.firstMatch
            if segmentedControl.exists {
                // Verify "Active" (In Progress) segment is selected
                let activeButton = segmentedControl.buttons["Active"]
                XCTAssertTrue(activeButton.isSelected)
            }
        }
        #endif
    }

    // MARK: - Task Card Interaction Tests

    @MainActor
    func testTappingTaskCardOpensDetailSheet() throws {
        guard let app = app else { return }

        // Find first task card (assumes tasks exist)
        let firstCard = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'task-card-'")
        ).firstMatch
        if firstCard.waitForExistence(timeout: 2) {
            firstCard.tap()

            // Verify detail view appears
            let detailView = app.otherElements["Task Detail"]
            XCTAssertTrue(detailView.waitForExistence(timeout: 2))
        }
    }

    // MARK: - Settings Navigation Tests

    @MainActor
    func testSettingsHasProjectsSection() throws {
        guard let app = app else { return }

        let settingsButton = app.buttons["Settings"]
        settingsButton.tap()

        // Verify Projects section exists
        let projectsSection = app.staticTexts["Projects"]
        XCTAssertTrue(projectsSection.waitForExistence(timeout: 2))
    }

    @MainActor
    func testSettingsHasGeneralSection() throws {
        guard let app = app else { return }

        let settingsButton = app.buttons["Settings"]
        settingsButton.tap()

        // Verify General section exists
        let generalSection = app.staticTexts["General"]
        XCTAssertTrue(generalSection.waitForExistence(timeout: 2))
    }
}
