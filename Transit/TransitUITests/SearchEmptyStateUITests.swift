import XCTest

/// UI tests for the dashboard search empty state. [T-198]
final class SearchEmptyStateUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchBoardApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TRANSIT_UI_TEST_SCENARIO"] = "board"
        app.launch()
        return app
    }

    @MainActor
    func testSearchEmptyStateShowsAndSearchFieldPersists() throws {
        let app = launchBoardApp()

        // Wait for the board to seed before searching.
        XCTAssertTrue(app.staticTexts["Ship Active"].waitForExistence(timeout: 5))

        // "ZZZNOMATCH" matches no seeded task name, description, or display ID
        // (board seeds: Ship Active / Backlog Idea / Old Abandoned / Beta Review,
        // all with nil descriptions and display IDs T-1..T-4).
        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("ZZZNOMATCH")

        // The dedicated search empty state appears (ContentUnavailableView.search).
        let searchEmptyState = app.descendants(matching: .any)["dashboard.searchEmptyState"]
        XCTAssertTrue(
            searchEmptyState.waitForExistence(timeout: 5),
            "Search-only no-match should show dashboard.searchEmptyState"
        )

        // The search field MUST remain present so the user can edit/clear the query
        // (the .searchable modifier stays outside the overlay branching).
        XCTAssertTrue(app.searchFields.firstMatch.exists)
    }

    @MainActor
    func testNonSearchFilterNoMatchShowsGenericFilterState() throws {
        let app = launchBoardApp()

        XCTAssertTrue(app.staticTexts["Ship Active"].waitForExistence(timeout: 5))

        // The board seeds only feature/research/chore/bug tasks — no documentation
        // task — so filtering by Documentation (with no search text) matches nothing.
        let typeFilter = app.buttons["dashboard.filter.types"]
        XCTAssertTrue(typeFilter.waitForExistence(timeout: 5))
        typeFilter.tap()

        let documentationOption = app.buttons["filter.type.documentation"]
        XCTAssertTrue(documentationOption.waitForExistence(timeout: 5))
        documentationOption.tap()
        app.buttons["Done"].tap()

        // A non-search filter with no match shows the generic filter state, NOT the
        // search state (decision_log.md Decision 1).
        let filterEmptyState = app.descendants(matching: .any)["dashboard.filterEmptyState"]
        XCTAssertTrue(
            filterEmptyState.waitForExistence(timeout: 5),
            "Non-search filter no-match should show dashboard.filterEmptyState"
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["dashboard.searchEmptyState"].exists,
            "The search empty state must not appear when only a non-search filter is active"
        )
    }
}
