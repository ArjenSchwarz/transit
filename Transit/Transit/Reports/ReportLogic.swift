import Foundation

enum ReportLogic {
    static func buildReport(
        tasks: [TransitTask],
        milestones: [Milestone] = [],
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

        // 2. Filter milestones with terminal status and completionDate in range
        let filteredMilestones = milestones.filter { milestone in
            guard milestone.project != nil else { return false }
            guard milestone.status.isTerminal else { return false }
            guard let completionDate = milestone.completionDate else { return false }
            return DateFilterHelpers.dateInRange(completionDate, range: range, now: now)
        }
        let milestonesByProject = Dictionary(grouping: filteredMilestones) { $0.project?.id ?? $0.id }

        // 3. Group tasks by project ID, skipping any task whose project became nil after filtering
        let grouped = Dictionary(grouping: filtered) { $0.project?.id ?? $0.id }

        // 4. Collect all project IDs from both tasks and milestones
        let allProjectIDs = Set(grouped.keys).union(milestonesByProject.keys)

        // 5. Build project groups sorted alphabetically (case-insensitive)
        let projectGroups = allProjectIDs.compactMap { projectID -> ProjectGroup? in
            let projectTasks = grouped[projectID] ?? []
            let projectMilestones = milestonesByProject[projectID] ?? []

            // Find the project from either tasks or milestones
            let project = projectTasks.first?.project ?? projectMilestones.first?.project
            guard let project else { return nil }

            return ProjectGroup(
                id: project.id,
                projectName: project.name,
                tasks: buildReportTasks(from: projectTasks),
                milestones: buildReportMilestones(from: projectMilestones)
            )
        }
        .sorted { $0.projectName.localizedCaseInsensitiveCompare($1.projectName) == .orderedAscending }

        // 6. Compute summary counts from group-level counts
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

    private static func buildReportMilestones(from milestones: [Milestone]) -> [ReportMilestone] {
        milestones
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { milestone in
                ReportMilestone(
                    id: milestone.id,
                    displayID: milestone.displayID.formatted(prefix: "M"),
                    name: milestone.name,
                    isAbandoned: milestone.status == .abandoned,
                    taskCount: milestone.tasks?.count ?? 0
                )
            }
    }

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
                permanentDisplayId: task.permanentDisplayId,
                milestoneName: task.milestone?.name
            )
        }
    }
}
