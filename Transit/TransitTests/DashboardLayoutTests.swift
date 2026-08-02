import SwiftUI
import Testing
@testable import Transit

@MainActor
struct DashboardLayoutTests {
    @Test(arguments: [320, 400, 428, 599])
    func compactPortraitUsesSingleColumnAtEveryWidth(width: Int) {
        let layout = DashboardLayoutLogic.layout(
            width: CGFloat(width),
            horizontalSizeClass: .compact,
            verticalSizeClass: .regular
        )

        #expect(layout == .singleColumn)
    }

    @Test func compactWidthRegularHeightUsesSingleColumnForNarrowIPadSplitView() {
        let layout = DashboardLayoutLogic.layout(
            width: 500,
            horizontalSizeClass: .compact,
            verticalSizeClass: .regular
        )

        #expect(layout == .singleColumn)
    }

    @Test func compactHeightRetainsLandscapeGeometryAdaptation() {
        let layout = DashboardLayoutLogic.layout(
            width: 400,
            horizontalSizeClass: .compact,
            verticalSizeClass: .compact
        )

        #expect(layout == .kanban(visibleCount: 2, initialScrollTarget: .planning))
    }

    @Test func regularIPadWidthRetainsGeometryAdaptation() {
        let layout = DashboardLayoutLogic.layout(
            width: 600,
            horizontalSizeClass: .regular,
            verticalSizeClass: .regular
        )

        #expect(layout == .kanban(visibleCount: 3, initialScrollTarget: nil))
    }

    @Test func regularMacWidthRetainsGeometryAdaptationAndCapsAtFiveColumns() {
        let layout = DashboardLayoutLogic.layout(
            width: 1_200,
            horizontalSizeClass: nil,
            verticalSizeClass: nil
        )

        #expect(layout == .kanban(visibleCount: 5, initialScrollTarget: nil))
    }
}
