#if os(macOS)
import Foundation
import CoreFoundation
import SwiftData

struct MCPWriteCommandServices {
    let tasks: TaskService
    let projects: ProjectService
    let comments: CommentService
    let milestones: MilestoneService
    let context: ModelContext
}

enum PreparedMCPWrite {
    case taskCreation(TaskService.PreparedCreation)
    case milestoneCreation(MilestoneService.PreparedCreation)
    case task(UUID)
    case milestone(UUID)
    case project
}

struct MCPWriteCommand {
    typealias AfterTaskApply = @MainActor (MCPWriteCommand, TransitTask, MCPWriteCommandServices) throws -> Void

    static let protectedTools: Set<String> = [
        "create_task", "create_project", "create_milestone", "add_comment",
        "update_task", "update_task_status", "update_milestone", "delete_milestone"
    ]
    static let revisionTools: Set<String> = [
        "update_task", "update_task_status", "update_milestone", "delete_milestone"
    ]
    let tool: String
    let key: String
    let arguments: [String: Any]
    var expectedRevision: String? { arguments["expectedRevision"] as? String }

    static func validate(tool: String, arguments: [String: Any]) throws -> Self {
        guard protectedTools.contains(tool),
            let definition = MCPToolDefinitions.coreTools.first(where: { $0.name == tool })
        else {
            throw MCPWriteFailure("INVALID_INPUT", "Unknown protected tool")
        }
        let properties = definition.inputSchema.properties ?? [:]
        let safetyFields: Set<String> =
            revisionTools.contains(tool)
            ? ["idempotencyKey", "expectedRevision"] : ["idempotencyKey"]
        for field in arguments.keys where properties[field] == nil && !safetyFields.contains(field) {
            throw MCPWriteFailure("INVALID_INPUT", "Unknown argument: \(field)")
        }
        for field in definition.inputSchema.required ?? [] where arguments[field] == nil {
            throw MCPWriteFailure("INVALID_INPUT", "Missing required argument: \(field)")
        }
        let usesProjectID = ["create_task", "create_milestone"].contains(tool)
            && (arguments["projectId"] as? String).flatMap(UUID.init(uuidString:)) != nil
        for (field, value) in arguments where !safetyFields.contains(field) {
            if field == "project", usesProjectID { continue }
            try validateValue(value, field: field, schema: properties[field]!)
        }
        guard let key = arguments["idempotencyKey"] as? String,
            key.range(of: "^[A-Za-z0-9._:-]{1,128}$", options: .regularExpression) == key.startIndex..<key.endIndex
        else {
            throw MCPWriteFailure("INVALID_INPUT", "idempotencyKey must match [A-Za-z0-9._:-]{1,128}")
        }
        if revisionTools.contains(tool) {
            guard let revision = arguments["expectedRevision"] as? String,
                revision.range(of: "^r1:[0-9a-f]{64}$", options: .regularExpression) == revision
                    .startIndex..<revision.endIndex
            else {
                throw MCPWriteFailure("INVALID_INPUT", "expectedRevision must match r1:[0-9a-f]{64}")
            }
        }
        for field in ["taskId", "projectId", "milestoneId"] {
            if let value = arguments[field] as? String, UUID(uuidString: value) == nil {
                throw MCPWriteFailure("INVALID_INPUT", "\(field) must be a valid UUID string")
            }
        }
        return Self(tool: tool, key: key, arguments: arguments)
    }

    private static func validateValue(_ value: Any, field: String, schema: JSONSchemaProperty) throws {
        let valid: Bool
        switch schema.type {
        case "string": valid = value is String
        case "integer": valid = IntentHelpers.parseIntValue(value) != nil
        case "boolean": valid = IntentHelpers.parseBoolValue(value) != nil
        case "object": valid = value is [String: Any]
        default: valid = false
        }
        guard valid else {
            if ["projectId", "taskId", "milestoneId"].contains(field) {
                throw MCPWriteFailure("INVALID_INPUT", "\(field) must be a valid UUID string")
            }
            let article = schema.type == "integer" || schema.type == "object" ? "an" : "a"
            throw MCPWriteFailure("INVALID_INPUT", "\(field) must be \(article) \(schema.type ?? "JSON")")
        }
    }

    func prepare(using services: MCPWriteCommandServices) async throws -> PreparedMCPWrite {
        try Task.checkCancellation()
        switch tool {
        case "create_task":
            let project = try project(using: services)
            guard let type = TaskType(rawValue: try string("type")) else {
                throw MCPWriteFailure("INVALID_TYPE", "Invalid task type")
            }
            let priority = try taskPriority()
            let milestone = try assignedMilestone(project: project, using: services)
            return .taskCreation(
                try await services.tasks.prepareTaskCreation(
                    name: try string("name"), description: arguments["description"] as? String,
                    type: type, project: project, metadata: IntentHelpers.stringMetadata(from: arguments["metadata"]),
                    priority: priority, milestone: milestone
                ))
        case "create_milestone":
            return .milestoneCreation(
                try await services.milestones.prepareMilestoneCreation(
                    name: try string("name"), description: arguments["description"] as? String,
                    project: project(using: services)
                ))
        case "create_project": return .project
        case "update_milestone", "delete_milestone":
            if let id = arguments["milestoneId"] as? String {
                return .milestone(try services.milestones.findByID(UUID(uuidString: id)!).id)
            }
            if let id = arguments["displayId"] as? NSNumber {
                return .milestone(try services.milestones.findByDisplayID(id.intValue).id)
            }
            throw MCPWriteFailure("INVALID_INPUT", "Provide either displayId or milestoneId")
        default: return .task(try services.tasks.resolveTask(from: arguments).id)
        }
    }

    func apply(_ prepared: PreparedMCPWrite, using services: MCPWriteCommandServices,
               afterTaskApply: AfterTaskApply? = nil) throws -> [String: Any] {
        try Task.checkCancellation()
        switch prepared {
        case .taskCreation(let creation):
            let task = try services.tasks.applyTaskCreation(creation)
            try afterTaskApply?(self, task, services)
            return try saved(MCPRecordSnapshot.task(task, in: services.context))
        case .milestoneCreation(let creation):
            let milestone = try services.milestones.applyMilestoneCreation(creation)
            return try saved(MCPRecordSnapshot.milestone(milestone))
        case .project:
            let raw = try string("colorHex")
            let hex = raw.hasPrefix("#") ? String(raw.dropFirst()) : raw
            guard hex.range(of: "^[0-9a-fA-F]{6}$", options: .regularExpression) == hex.startIndex..<hex.endIndex
            else {
                throw MCPWriteFailure("INVALID_INPUT", "colorHex must contain six hexadecimal digits")
            }
            let project = try services.projects.createProject(
                name: try string("name"), description: arguments["description"] as? String ?? "",
                gitRepo: arguments["gitRepo"] as? String, colorHex: raw, save: false
            )
            return try saved(MCPRecordSnapshot.project(project))
        case .task(let id): return try applyTask(id, using: services, afterTaskApply: afterTaskApply)
        case .milestone(let id): return try applyMilestone(id, using: services)
        }
    }

    private func applyTask(_ id: UUID, using services: MCPWriteCommandServices,
                           afterTaskApply: AfterTaskApply?) throws -> [String: Any] {
        let task = try services.tasks.findByID(id)
        if expectedRevision != nil { try check(MCPRecordSnapshot.task(task, in: services.context)) }
        if tool == "add_comment" {
            let comment = try services.comments.addComment(
                to: task, content: try string("content"),
                authorName: try string("authorName"),
                isAgent: true, save: nil)
            try afterTaskApply?(self, task, services)
            return try saved(MCPRecordSnapshot.comment(comment))
        }
        if tool == "update_task" {
            let update = try TaskUpdateValidator.validate(
                arguments, task: task, milestoneService: services.milestones
            ).get()
            try TaskUpdateValidator.apply(
                update, to: task, taskService: services.tasks,
                milestoneService: services.milestones)
            try afterTaskApply?(self, task, services)
            return try saved(MCPRecordSnapshot.task(task, in: services.context))
        }
        let validation = try MCPTaskMutationValidation.status(
            currentStatus: task.statusRawValue, targetStatus: try string("status"),
            comment: arguments["comment"] as? String, authorName: arguments["authorName"] as? String)
        guard let status = TaskStatus(rawValue: validation.targetStatus) else {
            throw MCPWriteFailure("INVALID_STATUS", "Invalid task status")
        }
        let comment = try services.tasks.updateStatus(
            task: task, to: status,
            comment: arguments["comment"] as? String,
            commentAuthor: arguments["authorName"] as? String,
            commentService: services.comments, save: false)
        try afterTaskApply?(self, task, services)
        var result = try saved(MCPRecordSnapshot.task(task, in: services.context))
        result["comment"] = try comment.map { try MCPRecordSnapshot.comment($0).record } as Any? ?? NSNull()
        return result
    }

    private func applyMilestone(_ id: UUID, using services: MCPWriteCommandServices) throws -> [String: Any] {
        let milestone = try services.milestones.findByID(id)
        let before = try MCPRecordSnapshot.milestone(milestone)
        try check(before)
        if tool == "delete_milestone" {
            try services.milestones.deleteMilestone(milestone, save: false)
            return ["entityId": id.uuidString, "deleted": true, "recordBeforeDeletion": before.record]
        }
        var name: String?
        if let input = arguments["name"] as? String {
            let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw MilestoneService.Error.invalidName }
            if let project = milestone.project,
                try services.milestones.milestoneNameExists(trimmed, in: project, excluding: id) {
                throw MilestoneService.Error.duplicateName
            }
            name = trimmed
        }
        var status: MilestoneStatus?
        if let raw = arguments["status"] as? String {
            guard let parsed = MilestoneStatus(rawValue: raw) else {
                throw MCPWriteFailure("INVALID_STATUS", "Invalid milestone status")
            }
            status = parsed
        }
        if let name { milestone.name = name }
        if let description = arguments["description"] as? String {
            let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
            milestone.milestoneDescription = trimmed.isEmpty ? nil : trimmed
        }
        if let status, milestone.statusRawValue != status.rawValue {
            milestone.status = status
            milestone.lastStatusChangeDate = Date()
            milestone.completionDate = status.isTerminal ? milestone.lastStatusChangeDate : nil
        }
        return try saved(MCPRecordSnapshot.milestone(milestone))
    }

    private func project(using services: MCPWriteCommandServices) throws -> Project {
        try services.projects.findProject(
            id: (arguments["projectId"] as? String).flatMap(UUID.init(uuidString:)),
            name: arguments["project"] as? String
        ).get()
    }

    private func string(_ key: String) throws -> String {
        guard let value = arguments[key] as? String else {
            throw MCPWriteFailure("INVALID_INPUT", "\(key) must be a string")
        }
        return value
    }

    private func taskPriority() throws -> TaskPriority {
        guard let raw = arguments["priority"] as? String else { return .medium }
        guard let priority = TaskPriority(rawValue: raw) else {
            throw MCPWriteFailure("INVALID_PRIORITY", "Invalid task priority")
        }
        return priority
    }

    private func check(_ snapshot: MCPRecordSnapshot) throws {
        guard snapshot.revision == expectedRevision else {
            throw MCPWriteFailure(
                "REVISION_CONFLICT", "Record changed since it was read", currentRecord: snapshot.record)
        }
    }

    private func saved(_ snapshot: MCPRecordSnapshot) -> [String: Any] {
        ["entityId": snapshot.entityID.uuidString, "record": snapshot.record]
    }
}
extension MCPWriteCommand {
    private func assignedMilestone(project: Project, using services: MCPWriteCommandServices) throws -> Milestone? {
        if let id = arguments["milestoneDisplayId"] as? NSNumber {
            do {
                return try services.milestones.findByDisplayID(id.intValue)
            } catch MilestoneService.Error.milestoneNotFound {
                throw MCPWriteFailure("MILESTONE_NOT_FOUND", "No milestone with displayId \(id.intValue)")
            } catch MilestoneService.Error.duplicateDisplayID {
                throw MCPWriteFailure("INTERNAL_ERROR",
                    "Duplicate milestone identifier detected for displayId \(id.intValue)")
            } catch {
                throw MCPWriteFailure("INTERNAL_ERROR", "Failed to find milestone: \(error)")
            }
        }
        if let name = arguments["milestone"] as? String {
            do {
                guard let milestone = try services.milestones.findByName(name, in: project) else {
                    throw MCPWriteFailure("MILESTONE_NOT_FOUND",
                        "No milestone named '\(name)' in project '\(project.name)'")
                }
                return milestone
            } catch let failure as MCPWriteFailure {
                throw failure
            } catch MilestoneService.Error.ambiguousName {
                throw MCPWriteFailure("AMBIGUOUS_MILESTONE",
                    "Multiple milestones named '\(name)' exist in project '\(project.name)'")
            } catch {
                throw MCPWriteFailure("INTERNAL_ERROR", "Failed to look up milestone: \(error)")
            }
        }
        return nil
    }
}

#endif
