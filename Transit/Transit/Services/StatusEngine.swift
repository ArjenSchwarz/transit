//
//  StatusEngine.swift
//  Transit
//
//  Centralizes status transition logic and side effects.
//

import Foundation

/// Centralizes all status transition logic so the same rules apply
/// whether a status change comes from drag-and-drop, detail view, or App Intent.
struct StatusEngine {
    /// Set initial state for a newly created task.
    /// Separate from applyTransition because creation is not a transition.
    static func initializeNewTask(_ task: TransitTask, now: Date = .now) {
        task.status = .idea
        task.creationDate = now
        task.lastStatusChangeDate = now
    }

    /// Apply side effects for a status transition.
    /// Handles: lastStatusChangeDate, completionDate set/clear.
    static func applyTransition(
        task: TransitTask,
        to newStatus: TaskStatus,
        now: Date = .now
    ) {
        let oldStatus = task.status
        task.status = newStatus
        task.lastStatusChangeDate = now

        switch newStatus {
        case .done, .abandoned:
            // Set completionDate when entering terminal status
            task.completionDate = now
        default:
            // Clear completionDate when moving out of terminal status
            if oldStatus.isTerminal {
                task.completionDate = nil
            }
        }
    }
}
