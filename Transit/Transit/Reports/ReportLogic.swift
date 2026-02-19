import Foundation

enum ReportLogic {
    static func buildReport(
        tasks: [TransitTask],
        dateRange: ReportDateRange,
        now: Date = .now
    ) -> ReportData {
        let range = dateRange.dateRange

        // 1. Filter to terminal tasks with valid project and completionDate in range
        let filtered = tasks.filter { task in
            guard task.project != nil else { return false }
            guard task.status.isTerminal else { return false }
            guard let completionDate = task.completionDate else { return false }
            return DateFilterHelpers.dateInRange(completionDate, range: range, now: now)
        }

        // 2. Group by project ID, skipping any task whose project became nil after filtering
        let grouped = Dictionary(grouping: filtered) { $0.project?.id ?? $0.id }

        // 3. Build project groups sorted alphabetically (case-insensitive)
        let projectGroups = grouped.compactMap { (_, tasks) -> ProjectGroup? in
            guard let firstProject = tasks[0].project else { return nil }
            return ProjectGroup(
                id: firstProject.id,
                projectName: firstProject.name,
                tasks: buildReportTasks(from: tasks)
            )
        }
        .sorted { $0.projectName.localizedCaseInsensitiveCompare($1.projectName) == .orderedAscending }

        // 4. Compute summary counts from group-level counts
        let totalDone = projectGroups.reduce(0) { $0 + $1.doneCount }
        let totalAbandoned = projectGroups.reduce(0) { $0 + $1.abandonedCount }

        return ReportData(
            dateRangeLabel: dateRange.labelWithDates(now: now),
            projectGroups: projectGroups,
            totalDone: totalDone,
            totalAbandoned: totalAbandoned
        )
    }

    // MARK: - Private

    private static func buildReportTasks(from tasks: [TransitTask]) -> [ReportTask] {
        let sorted = tasks.sorted { lhs, rhs in
            let lhsDate = lhs.completionDate ?? .distantPast
            let rhsDate = rhs.completionDate ?? .distantPast

            if lhsDate != rhsDate {
                return lhsDate < rhsDate
            }

            switch (lhs.permanentDisplayId, rhs.permanentDisplayId) {
            case let (lhsId?, rhsId?) where lhsId != rhsId:
                return lhsId < rhsId
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                return lhs.id.uuidString < rhs.id.uuidString
            }
        }

        return sorted.map { task in
            ReportTask(
                id: task.id,
                displayID: task.displayID.formatted,
                name: task.name,
                taskType: task.type,
                isAbandoned: task.status == .abandoned,
                completionDate: task.completionDate ?? .distantPast,
                permanentDisplayId: task.permanentDisplayId
            )
        }
    }
}
