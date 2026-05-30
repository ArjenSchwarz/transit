import Foundation

struct ReportData {
    let dateRangeLabel: String
    let projectGroups: [ProjectGroup]
    let totalDone: Int
    let totalAbandoned: Int
    let totalMilestonesDone: Int
    let totalMilestonesAbandoned: Int

    init(
        dateRangeLabel: String,
        projectGroups: [ProjectGroup],
        totalDone: Int,
        totalAbandoned: Int,
        totalMilestonesDone: Int = 0,
        totalMilestonesAbandoned: Int = 0
    ) {
        self.dateRangeLabel = dateRangeLabel
        self.projectGroups = projectGroups
        self.totalDone = totalDone
        self.totalAbandoned = totalAbandoned
        self.totalMilestonesDone = totalMilestonesDone
        self.totalMilestonesAbandoned = totalMilestonesAbandoned
    }

    var totalTasks: Int { totalDone + totalAbandoned }
    var isEmpty: Bool { projectGroups.isEmpty }

    /// Summary of completed/abandoned tasks. Used where only task counts are relevant.
    static func summaryText(done: Int, abandoned: Int) -> String {
        switch (done > 0, abandoned > 0) {
        case (true, true):
            "\(done) done, \(abandoned) abandoned"
        case (true, false):
            "\(done) done"
        case (false, true):
            "\(abandoned) abandoned"
        case (false, false):
            "0 done"
        }
    }

    /// Summary that also reflects milestone counts. When no milestones are present the
    /// output is identical to `summaryText(done:abandoned:)`; otherwise milestone
    /// done/abandoned counts are appended so milestone-only summaries are not misleading.
    static func summaryText(
        done: Int,
        abandoned: Int,
        milestonesDone: Int,
        milestonesAbandoned: Int
    ) -> String {
        let taskSummary = summaryText(done: done, abandoned: abandoned)
        var parts: [String] = []
        if milestonesDone > 0 {
            let word = milestonesDone == 1 ? "milestone" : "milestones"
            parts.append("\(milestonesDone) \(word) done")
        }
        if milestonesAbandoned > 0 {
            let word = milestonesAbandoned == 1 ? "milestone" : "milestones"
            parts.append("\(milestonesAbandoned) \(word) abandoned")
        }
        guard !parts.isEmpty else { return taskSummary }
        return ([taskSummary] + parts).joined(separator: ", ")
    }
}

struct ProjectGroup: Identifiable {
    let id: UUID
    let projectName: String
    let tasks: [ReportTask]
    let milestones: [ReportMilestone]
    var doneCount: Int { tasks.filter { !$0.isAbandoned }.count }
    var abandonedCount: Int { tasks.filter { $0.isAbandoned }.count }
    var doneMilestoneCount: Int { milestones.filter { !$0.isAbandoned }.count }
    var abandonedMilestoneCount: Int { milestones.filter { $0.isAbandoned }.count }
}

struct ReportMilestone: Identifiable {
    let id: UUID
    let displayID: String
    let name: String
    let isAbandoned: Bool
    let taskCount: Int

    var taskCountLabel: String {
        taskCount == 1 ? "1 task" : "\(taskCount) tasks"
    }
}

struct ReportTask: Identifiable {
    let id: UUID
    let displayID: String
    let name: String
    let taskType: TaskType
    let isAbandoned: Bool
    let completionDate: Date
    let permanentDisplayId: Int?
    let milestoneName: String?
}
