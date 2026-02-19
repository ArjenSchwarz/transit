import Foundation

enum ReportLogic {
    static func buildReport(
        tasks: [TransitTask],
        dateRange: ReportDateRange,
        now: Date = .now
    ) -> ReportData {
        let range = dateRange.dateRange

        // 1. Filter: exclude orphans, non-terminal, nil completionDate, out-of-range
        let filtered = tasks.filter { task in
            guard task.project != nil else { return false }
            guard task.status.isTerminal else { return false }
            guard let completionDate = task.completionDate else { return false }
            return DateFilterHelpers.dateInRange(completionDate, range: range, now: now)
        }

        // 2. Group by project ID
        let grouped = Dictionary(grouping: filtered) { $0.project!.id }

        // 3. Build project groups sorted alphabetically (case-insensitive)
        let projectGroups = grouped.map { (projectId, tasks) -> ProjectGroup in
            let projectName = tasks[0].project!.name

            // 4. Sort tasks: completionDate asc, permanentDisplayId asc (nil last), UUID string
            let sortedTasks = tasks.sorted { lhs, rhs in
                let lhsDate = lhs.completionDate!
                let rhsDate = rhs.completionDate!

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

            let reportTasks = sortedTasks.map { task in
                ReportTask(
                    id: task.id,
                    displayID: task.displayID.formatted,
                    name: task.name,
                    taskType: task.type,
                    isAbandoned: task.status == .abandoned,
                    completionDate: task.completionDate!,
                    permanentDisplayId: task.permanentDisplayId
                )
            }

            return ProjectGroup(id: projectId, projectName: projectName, tasks: reportTasks)
        }
        .sorted { $0.projectName.localizedCaseInsensitiveCompare($1.projectName) == .orderedAscending }

        // 5. Compute summary counts
        let totalDone = projectGroups.flatMap(\.tasks).filter { !$0.isAbandoned }.count
        let totalAbandoned = projectGroups.flatMap(\.tasks).filter(\.isAbandoned).count

        return ReportData(
            dateRangeLabel: dateRange.labelWithDates(now: now),
            projectGroups: projectGroups,
            totalDone: totalDone,
            totalAbandoned: totalAbandoned
        )
    }
}
