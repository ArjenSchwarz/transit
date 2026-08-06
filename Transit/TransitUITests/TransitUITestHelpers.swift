import XCTest

extension XCUIApplication {
    @MainActor
    func dismissTransitSearch() {
        let searchKey = keyboards.buttons["search"]
        XCTAssertTrue(searchKey.waitForExistence(timeout: 5))
        searchKey.tap()

        let closeSearch = buttons["close"]
        XCTAssertTrue(closeSearch.waitForExistence(timeout: 5))
        closeSearch.tap()
    }

    @MainActor
    func tapTransitToolbarButton(identifier: String, overflowLabel: String) {
        let directButton = buttons[identifier].firstMatch
        if directButton.waitForExistence(timeout: 1) {
            directButton.tap()
            return
        }

        let moreButton = buttons["More"]
        XCTAssertTrue(moreButton.waitForExistence(timeout: 5))
        moreButton.tap()

        let overflowButton = buttons[overflowLabel]
        XCTAssertTrue(overflowButton.waitForExistence(timeout: 5))
        overflowButton.tap()
    }
}
