import Foundation

struct ReportData {
    let dateRangeLabel: String
    let projectGroups: [ProjectGroup]
    let totalDone: Int
    let totalAbandoned: Int

    var totalTasks: Int { totalDone + totalAbandoned }
    var isEmpty: Bool { projectGroups.isEmpty }

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
}

struct ProjectGroup: Identifiable {
    let id: UUID
    let projectName: String
    let tasks: [ReportTask]
    let milestones: [ReportMilestone]
    var doneCount: Int { tasks.filter { !$0.isAbandoned }.count }
    var abandonedCount: Int { tasks.filter { $0.isAbandoned }.count }
}

struct ReportMilestone: Identifiable {
    let id: UUID
    let displayID: String
    let name: String
    let isAbandoned: Bool
    let taskCount: Int
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
