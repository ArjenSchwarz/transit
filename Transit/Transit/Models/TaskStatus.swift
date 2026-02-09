//
//  TaskStatus.swift
//  Transit
//
//  Status progression for tasks with column mapping and handoff detection.
//

import Foundation

/// Task status progression from idea to completion or abandonment.
/// Includes agent handoff statuses that render within parent columns.
enum TaskStatus: String, Codable, CaseIterable, Sendable {
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

    /// True if this is an agent handoff status requiring human attention.
    /// These statuses render promoted within their parent column.
    var isHandoff: Bool {
        self == .readyForImplementation || self == .readyForReview
    }

    /// True if this is a terminal status (Done or Abandoned).
    var isTerminal: Bool {
        self == .done || self == .abandoned
    }

    /// Short label for segmented control (iPhone portrait).
    var shortLabel: String {
        switch self {
        case .idea: return "Idea"
        case .planning: return "Plan"
        case .spec, .readyForImplementation: return "Spec"
        case .inProgress, .readyForReview: return "Active"
        case .done, .abandoned: return "Done"
        }
    }
}

/// Visual columns on the kanban dashboard.
enum DashboardColumn: String, CaseIterable, Sendable {
    case idea
    case planning
    case spec
    case inProgress = "in-progress"
    case doneAbandoned = "done-abandoned"

    /// Display name for column header.
    var displayName: String {
        switch self {
        case .idea: return "Idea"
        case .planning: return "Planning"
        case .spec: return "Spec"
        case .inProgress: return "In Progress"
        case .doneAbandoned: return "Done / Abandoned"
        }
    }

    /// The status assigned when a task is dropped into this column.
    /// Handoff statuses are only set via detail view or intents, not drag.
    var primaryStatus: TaskStatus {
        switch self {
        case .idea: return .idea
        case .planning: return .planning
        case .spec: return .spec
        case .inProgress: return .inProgress
        case .doneAbandoned: return .done
        }
    }
}
