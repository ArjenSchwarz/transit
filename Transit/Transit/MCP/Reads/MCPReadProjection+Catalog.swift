#if os(macOS)
import Foundation

extension MCPReadProjection {
    static func projects(_ view: CapturedReadView) throws -> [[String: Any]] {
        try view.projects.sorted { $0.name < $1.name }.map { project in
            var record = try object(project.selectedRecordJSON)
            let tasks = project.taskKeys.compactMap { key in view.tasks.first { $0.physicalKey == key } }
            guard tasks.count == project.taskKeys.count else { throw MCPReadCaptureError.incoherentCapture }
            record["activeTaskCount"] = tasks.filter { !["done", "abandoned"].contains($0.effectiveStatus) }.count
            // Ordinary catalog queries historically select milestones by project UUID.
            let milestones = view.milestones.filter { $0.storedProjectID == project.id }
            if !milestones.isEmpty { record["milestones"] = milestones.map(milestoneSummary) }
            return record
        }
    }

    static func milestones(_ view: CapturedReadView, arguments: [String: Any]) throws -> [[String: Any]] {
        let project = try project(arguments, view: view, validateIgnoredName: false)
        try enumeration(arguments, key: "status", type: MilestoneStatus.self)
        try string(arguments, key: "search")
        try integer(arguments, key: "displayId")
        let id = IntentHelpers.parseIntValue(arguments["displayId"])
        var milestones = view.milestones
        if let id {
            milestones = milestones.filter { $0.permanentDisplayId == id }
            guard milestones.count <= 1 else {
                throw MCPTaskQueryError(code: "AMBIGUOUS_FILTER",
                    message: "Duplicate milestone identifier detected for displayId \(id)")
            }
        }
        return try milestones.filter { milestone in
            matchesMilestone(ReadMilestoneIdentity(id: milestone.id,
                permanentDisplayId: milestone.permanentDisplayId, name: milestone.name,
                storedProjectID: milestone.storedProjectID, rawStatus: milestone.rawStatus,
                milestoneDescription: milestone.milestoneDescription), arguments: arguments, projectID: project?.id)
        }.map { milestone in
            var record = try object(milestone.selectedRecordJSON)
            record["taskCount"] = milestone.taskKeys.count
            if id != nil {
                record["tasks"] = try milestone.taskKeys.map { key in
                    guard let task = view.tasks.first(where: { $0.physicalKey == key }) else {
                        throw MCPReadCaptureError.incoherentCapture
                    }
                    var summary: [String: Any] = ["taskId": task.id.uuidString, "name": task.name,
                        "status": task.rawStatus, "type": task.rawType, "priority": task.effectivePriority]
                    summary["displayId"] = task.permanentDisplayId
                    return summary
                }
            }
            return record
        }
    }

    static func matchesMilestone(_ milestone: ReadMilestoneIdentity, arguments: [String: Any],
                                 projectID: UUID?) -> Bool {
        if let projectID, milestone.storedProjectID != projectID { return false }
        if let values = arguments["status"] as? [String], !values.contains(milestone.rawStatus) { return false }
        if let value = arguments["status"] as? String, value != milestone.rawStatus { return false }
        if let search = arguments["search"] as? String,
           !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !milestone.name.localizedCaseInsensitiveContains(search),
           milestone.milestoneDescription?.localizedCaseInsensitiveContains(search) != true { return false }
        return true
    }

    private static func milestoneSummary(_ milestone: ReadMilestone) -> [String: Any] {
        var record: [String: Any] = ["milestoneId": milestone.id.uuidString, "name": milestone.name,
                                   "status": milestone.rawStatus, "taskCount": milestone.taskKeys.count]
        record["displayId"] = milestone.permanentDisplayId
        return record
    }
}
#endif
