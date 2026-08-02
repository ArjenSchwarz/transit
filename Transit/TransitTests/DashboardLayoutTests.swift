import SwiftUI
import Testing
@testable import Transit

@MainActor
struct DashboardLayoutTests {
    @Test(arguments: [320, 375, 390, 400, 428, 599])
    func compactPortraitUsesSingleColumnAtEveryWidth(width: Int) {
        let layout = DashboardLayoutLogic.layout(
            width: CGFloat(width),
            horizontalSizeClass: .compact,
            verticalSizeClass: .regular,
            isPhone: true
        )

        #expect(layout == .singleColumn)
    }

    @Test func compactWidthRegularHeightUsesGeometryAdaptationForWideIPadSplitView() {
        let layout = DashboardLayoutLogic.layout(
            width: 500,
            horizontalSizeClass: .compact,
            verticalSizeClass: .regular,
            isPhone: false
        )

        #expect(layout == .kanban(visibleCount: 2, initialScrollTarget: nil))
    }

    @Test func narrowIPadSplitViewFallsBackToSingleColumn() {
        let layout = DashboardLayoutLogic.layout(
            width: 199,
            horizontalSizeClass: .compact,
            verticalSizeClass: .regular,
            isPhone: false
        )

        #expect(layout == .singleColumn)
    }

    @Test func compactHeightRetainsLandscapeGeometryAdaptation() {
        let layout = DashboardLayoutLogic.layout(
            width: 400,
            horizontalSizeClass: .compact,
            verticalSizeClass: .compact,
            isPhone: true
        )

        #expect(layout == .kanban(visibleCount: 2, initialScrollTarget: .planning))
    }

    @Test func regularWidthCompactHeightRetainsPhoneLandscapeAdaptation() {
        let layout = DashboardLayoutLogic.layout(
            width: 800,
            horizontalSizeClass: .regular,
            verticalSizeClass: .compact,
            isPhone: true
        )

        #expect(layout == .kanban(visibleCount: 3, initialScrollTarget: .planning))
    }

    @Test func regularIPadWidthRetainsGeometryAdaptation() {
        let layout = DashboardLayoutLogic.layout(
            width: 600,
            horizontalSizeClass: .regular,
            verticalSizeClass: .regular,
            isPhone: false
        )

        #expect(layout == .kanban(visibleCount: 3, initialScrollTarget: nil))
    }

    @Test func regularMacWidthRetainsGeometryAdaptationAndCapsAtFiveColumns() {
        let layout = DashboardLayoutLogic.layout(
            width: 1_200,
            horizontalSizeClass: nil,
            verticalSizeClass: nil,
            isPhone: false
        )

        #expect(layout == .kanban(visibleCount: 5, initialScrollTarget: nil))
    }

    @Test func missingSizeClassesRetainWidthBasedPreviewFallback() {
        let layout = DashboardLayoutLogic.layout(
            width: 400,
            horizontalSizeClass: nil,
            verticalSizeClass: nil,
            isPhone: false
        )

        #expect(layout == .kanban(visibleCount: 2, initialScrollTarget: nil))
    }

    @Test func missingVerticalSizeClassDoesNotAssumePortrait() {
        let layout = DashboardLayoutLogic.layout(
            width: 400,
            horizontalSizeClass: .compact,
            verticalSizeClass: nil,
            isPhone: true
        )

        #expect(layout == .kanban(visibleCount: 2, initialScrollTarget: nil))
    }
}
