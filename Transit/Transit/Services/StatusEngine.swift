import Foundation

struct StatusEngine {
    static func initializeNewTask(_ task: TransitTask, now: Date = .now) {
        task.status = .idea
        task.creationDate = now
        task.lastStatusChangeDate = now
        task.completionDate = nil
    }

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
            task.completionDate = now
        default:
            if oldStatus.isTerminal {
                task.completionDate = nil
            }
        }
    }
}
