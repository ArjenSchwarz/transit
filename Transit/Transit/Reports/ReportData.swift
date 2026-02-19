import Foundation

struct ReportData {
    let dateRangeLabel: String
    let projectGroups: [ProjectGroup]
    let totalDone: Int
    let totalAbandoned: Int

    var totalTasks: Int { totalDone + totalAbandoned }
    var isEmpty: Bool { projectGroups.isEmpty }
}

struct ProjectGroup: Identifiable {
    let id: UUID
    let projectName: String
    let tasks: [ReportTask]
    var doneCount: Int { tasks.filter { !$0.isAbandoned }.count }
    var abandonedCount: Int { tasks.filter { $0.isAbandoned }.count }
}

struct ReportTask: Identifiable {
    let id: UUID
    let displayID: String
    let name: String
    let taskType: TaskType
    let isAbandoned: Bool
    let completionDate: Date
    let permanentDisplayId: Int?
}
