#if os(macOS)
import Foundation

extension MCPReadProjection {
    static func projects(_ view: CapturedReadView, checkpoint: () throws -> Void = {}) throws -> [[String: Any]] {
        let tasksByKey = try catalogTaskIndex(view, checkpoint: checkpoint)
        var milestonesByProject: [UUID: [ReadMilestone]] = [:]
        for milestone in view.milestones {
            try checkpoint()
            if let projectID = milestone.storedProjectID {
                milestonesByProject[projectID, default: []].append(milestone)
            }
        }
        return try view.projects.sorted { $0.name < $1.name }.map { project in
            try checkpoint()
            var record = try object(project.selectedRecordJSON)
            var activeTaskCount = 0
            for key in project.taskKeys {
                try checkpoint()
                guard let task = tasksByKey[key] else { throw MCPReadCaptureError.incoherentCapture }
                if !["done", "abandoned"].contains(task.effectiveStatus) { activeTaskCount += 1 }
            }
            record["activeTaskCount"] = activeTaskCount
            // Ordinary catalog queries historically select milestones by project UUID.
            let milestones = milestonesByProject[project.id, default: []]
            if !milestones.isEmpty {
                record["milestones"] = try milestones.map { milestone in
                    try checkpoint()
                    return milestoneSummary(milestone)
                }
            }
            return record
        }
    }

    static func milestones(_ view: CapturedReadView, arguments: [String: Any],
                           checkpoint: () throws -> Void = {}) throws -> [[String: Any]] {
        try checkpoint()
        let project = try project(arguments, view: view, validateIgnoredName: false)
        try enumeration(arguments, key: "status", type: MilestoneStatus.self)
        try string(arguments, key: "search")
        try integer(arguments, key: "displayId")
        let id = IntentHelpers.parseIntValue(arguments["displayId"])
        var milestones = view.milestones
        if let id {
            milestones = try milestones.filter { milestone in
                try checkpoint()
                return milestone.permanentDisplayId == id
            }
            guard milestones.count <= 1 else {
                throw MCPTaskQueryError(code: "AMBIGUOUS_FILTER",
                    message: "Duplicate milestone identifier detected for displayId \(id)")
            }
        }
        let tasksByKey = id == nil ? [:] : try catalogTaskIndex(view, checkpoint: checkpoint)
        return try milestones.filter { milestone in
            try checkpoint()
            return matchesMilestone(ReadMilestoneIdentity(id: milestone.id,
                permanentDisplayId: milestone.permanentDisplayId, name: milestone.name,
                storedProjectID: milestone.storedProjectID, rawStatus: milestone.rawStatus,
                milestoneDescription: milestone.milestoneDescription), arguments: arguments, projectID: project?.id)
        }.map { milestone in
            try checkpoint()
            var record = try object(milestone.selectedRecordJSON)
            record["taskCount"] = milestone.taskKeys.count
            if id != nil {
                record["tasks"] = try milestone.taskKeys.map { key in
                    try checkpoint()
                    guard let task = tasksByKey[key] else {
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

    private static func catalogTaskIndex(_ view: CapturedReadView,
                                         checkpoint: () throws -> Void) throws -> [LocalRecordKey: ReadTask] {
        try checkpoint()
        var index: [LocalRecordKey: ReadTask] = [:]
        for task in view.tasks {
            try checkpoint()
            guard index.updateValue(task, forKey: task.physicalKey) == nil else {
                throw MCPReadCaptureError.incoherentCapture
            }
        }
        return index
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
