import SwiftUI
import Testing
@testable import Transit

@MainActor
struct DashboardLayoutTests {
    @Test(arguments: [320, 375, 390, 399])
    func narrowPhonePortraitUsesSingleColumn(width: Int) {
        let layout = DashboardLayoutLogic.layout(
            width: CGFloat(width),
            verticalSizeClass: .regular,
            isPhone: true
        )

        #expect(layout == .singleColumn)
    }

    @Test(arguments: [400, 428, 599])
    func widePhonePortraitUsesTwoColumnKanban(width: Int) {
        let layout = DashboardLayoutLogic.layout(
            width: CGFloat(width),
            verticalSizeClass: .regular,
            isPhone: true
        )

        #expect(layout == .kanban(visibleCount: 2, initialScrollTarget: nil))
    }

    @Test func widerPhonePortraitUsesThreeColumnKanban() {
        let layout = DashboardLayoutLogic.layout(
            width: 600,
            verticalSizeClass: .regular,
            isPhone: true
        )

        #expect(layout == .kanban(visibleCount: 3, initialScrollTarget: nil))
    }

    @Test func compactWidthRegularHeightUsesGeometryAdaptationForWideIPadSplitView() {
        let layout = DashboardLayoutLogic.layout(
            width: 500,
            verticalSizeClass: .regular,
            isPhone: false
        )

        #expect(layout == .kanban(visibleCount: 2, initialScrollTarget: nil))
    }

    @Test func narrowIPadSplitViewFallsBackToSingleColumn() {
        let layout = DashboardLayoutLogic.layout(
            width: 199,
            verticalSizeClass: .regular,
            isPhone: false
        )

        #expect(layout == .singleColumn)
    }

    @Test func compactHeightRetainsLandscapeGeometryAdaptation() {
        let layout = DashboardLayoutLogic.layout(
            width: 400,
            verticalSizeClass: .compact,
            isPhone: true
        )

        #expect(layout == .kanban(visibleCount: 2, initialScrollTarget: .planning))
    }

    @Test func widePhoneLandscapeRetainsThreeColumnCap() {
        let layout = DashboardLayoutLogic.layout(
            width: 800,
            verticalSizeClass: .compact,
            isPhone: true
        )

        #expect(layout == .kanban(visibleCount: 3, initialScrollTarget: .planning))
    }

    @Test func regularIPadWidthRetainsGeometryAdaptation() {
        let layout = DashboardLayoutLogic.layout(
            width: 600,
            verticalSizeClass: .regular,
            isPhone: false
        )

        #expect(layout == .kanban(visibleCount: 3, initialScrollTarget: nil))
    }

    @Test func regularMacWidthRetainsGeometryAdaptationAndCapsAtFiveColumns() {
        let layout = DashboardLayoutLogic.layout(
            width: 1_200,
            verticalSizeClass: nil,
            isPhone: false
        )

        #expect(layout == .kanban(visibleCount: 5, initialScrollTarget: nil))
    }

    @Test func missingVerticalSizeClassRetainsWidthBasedFallback() {
        let layout = DashboardLayoutLogic.layout(
            width: 400,
            verticalSizeClass: nil,
            isPhone: true
        )

        #expect(layout == .kanban(visibleCount: 2, initialScrollTarget: nil))
    }

    @Test func narrowFallbackUsesShortLabelsAndDefaultsToActive() {
        let labels = DashboardColumn.allCases.map { $0.primaryStatus.shortLabel }

        #expect(labels == ["Idea", "Plan", "Spec", "Active", "Done"])
        #expect(DashboardLayoutLogic.defaultSingleColumn == .inProgress)
    }
}
