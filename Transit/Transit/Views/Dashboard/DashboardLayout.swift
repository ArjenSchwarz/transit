import SwiftUI

enum DashboardLayoutMode: Equatable {
    case singleColumn
    case kanban(visibleCount: Int, initialScrollTarget: DashboardColumn?)
}

enum DashboardLayoutLogic {
    static let columnMinWidth: CGFloat = 200
    static let defaultSingleColumn: DashboardColumn = .inProgress

    static func layout(
        width: CGFloat,
        verticalSizeClass: UserInterfaceSizeClass?,
        isPhone: Bool
    ) -> DashboardLayoutMode {
        let rawColumnCount = max(1, Int(width / columnMinWidth))
        let isPhoneLandscape = isPhone && verticalSizeClass == .compact
        let columnCount = isPhoneLandscape ? min(rawColumnCount, 3) : rawColumnCount

        if columnCount == 1 {
            return .singleColumn
        }

        return .kanban(
            visibleCount: min(columnCount, DashboardColumn.allCases.count),
            initialScrollTarget: isPhoneLandscape ? .planning : nil
        )
    }
}
