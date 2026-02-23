import Foundation

nonisolated enum MilestoneStatus: String, CaseIterable, Sendable, Equatable {
    case open
    case done
    case abandoned

    nonisolated var isTerminal: Bool {
        self == .done || self == .abandoned
    }

    nonisolated var displayName: String {
        switch self {
        case .open: "Open"
        case .done: "Done"
        case .abandoned: "Abandoned"
        }
    }
}
