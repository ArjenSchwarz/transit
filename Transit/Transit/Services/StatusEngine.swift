import Foundation

/// Centralises all task status transition logic. Every status change in the app
/// goes through StatusEngine so side-effects (timestamps, completion dates) are
/// applied consistently regardless of the caller (UI, App Intents, future MCP).
struct StatusEngine {

    /// Sets the initial state for a newly created task.
    static func initializeNewTask(_ task: TransitTask, now: Date = .now) {
        task.status = .idea
        task.creationDate = now
        task.lastStatusChangeDate = now
    }

    /// Moves a task to `newStatus`, updating timestamps and completion date
    /// according to the status lifecycle rules.
    ///
    /// - Terminal statuses (.done, .abandoned) set `completionDate`.
    /// - Transitioning *from* a terminal status to a non-terminal one clears it.
    static func applyTransition(task: TransitTask, to newStatus: TaskStatus, now: Date = .now) {
        let oldStatus = task.status
        task.status = newStatus
        task.lastStatusChangeDate = now

        switch newStatus {
        case .done, .abandoned:
            task.completionDate = now
        default:
            if oldStatus.isTerminal {
                task.completionDate = nil
            }
        }
    }
}
