import Foundation

/// Narrow seam over the task service's full-table fetch so intent and App Entity
/// query paths can be tested against a failing storage layer.
@MainActor
protocol TaskFetching {
    func fetchAllTasks() throws -> [TransitTask]
}

extension TaskService: TaskFetching {}
