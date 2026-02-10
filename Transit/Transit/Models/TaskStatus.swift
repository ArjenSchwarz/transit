import Foundation

enum TaskStatus: String, Codable, CaseIterable {
    case idea
    case planning
    case spec
    case readyForImplementation = "ready-for-implementation"
    case inProgress = "in-progress"
    case readyForReview = "ready-for-review"
    case done
    case abandoned

    nonisolated var column: DashboardColumn {
        switch self {
        case .idea:
            return .idea
        case .planning:
            return .planning
        case .spec, .readyForImplementation:
            return .spec
        case .inProgress, .readyForReview:
            return .inProgress
        case .done, .abandoned:
            return .doneAbandoned
        }
    }

    nonisolated var isHandoff: Bool {
        self == .readyForImplementation || self == .readyForReview
    }

    nonisolated var isTerminal: Bool {
        self == .done || self == .abandoned
    }

    nonisolated var shortLabel: String {
        switch column {
        case .idea:
            return "Idea"
        case .planning:
            return "Plan"
        case .spec:
            return "Spec"
        case .inProgress:
            return "Active"
        case .doneAbandoned:
            return "Done"
        }
    }
}

enum DashboardColumn: String, CaseIterable, Identifiable {
    case idea
    case planning
    case spec
    case inProgress
    case doneAbandoned

    nonisolated var id: String {
        rawValue
    }

    nonisolated var displayName: String {
        switch self {
        case .idea:
            return "Idea"
        case .planning:
            return "Planning"
        case .spec:
            return "Spec"
        case .inProgress:
            return "In Progress"
        case .doneAbandoned:
            return "Done / Abandoned"
        }
    }

    nonisolated var primaryStatus: TaskStatus {
        switch self {
        case .idea:
            return .idea
        case .planning:
            return .planning
        case .spec:
            return .spec
        case .inProgress:
            return .inProgress
        case .doneAbandoned:
            return .done
        }
    }
}
