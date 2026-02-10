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

    /// The visual column this status maps to on the dashboard.
    var column: DashboardColumn {
        switch self {
        case .idea: .idea
        case .planning: .planning
        case .spec, .readyForImplementation: .spec
        case .inProgress, .readyForReview: .inProgress
        case .done, .abandoned: .doneAbandoned
        }
    }

    /// Whether this is an agent handoff status that renders promoted in its column.
    var isHandoff: Bool {
        self == .readyForImplementation || self == .readyForReview
    }

    var isTerminal: Bool {
        self == .done || self == .abandoned
    }

    var displayName: String {
        switch self {
        case .idea: "Idea"
        case .planning: "Planning"
        case .spec: "Spec"
        case .readyForImplementation: "Ready for Implementation"
        case .inProgress: "In Progress"
        case .readyForReview: "Ready for Review"
        case .done: "Done"
        case .abandoned: "Abandoned"
        }
    }

    /// Short labels for iPhone segmented control [req 13.2]
    var shortLabel: String {
        switch column {
        case .idea: "Idea"
        case .planning: "Plan"
        case .spec: "Spec"
        case .inProgress: "Active"
        case .doneAbandoned: "Done"
        }
    }
}

enum DashboardColumn: String, CaseIterable, Identifiable {
    case idea
    case planning
    case spec
    case inProgress
    case doneAbandoned

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .idea: "Idea"
        case .planning: "Planning"
        case .spec: "Spec"
        case .inProgress: "In Progress"
        case .doneAbandoned: "Done / Abandoned"
        }
    }

    /// The status assigned when a task is dropped into this column.
    /// Columns containing multiple statuses map to the "base" status —
    /// handoff statuses are only set via the detail view or App Intents.
    var primaryStatus: TaskStatus {
        switch self {
        case .idea: .idea
        case .planning: .planning
        case .spec: .spec
        case .inProgress: .inProgress
        case .doneAbandoned: .done  // never .abandoned via drag [req 7.4]
        }
    }
}
