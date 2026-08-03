import Foundation

/// Narrow seams over terminal report fetches so report generation can distinguish
/// storage failures from a successful empty result.
@MainActor
protocol TerminalTaskFetching {
    func fetchTerminalTasks() throws -> [TransitTask]
}

extension TaskService: TerminalTaskFetching {}

@MainActor
protocol TerminalMilestoneFetching {
    func fetchTerminalMilestones() throws -> [Milestone]
}

extension MilestoneService: TerminalMilestoneFetching {}
