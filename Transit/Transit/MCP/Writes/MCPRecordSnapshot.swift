import Foundation
import SwiftData

/// Captures value dictionaries once, so response and token describe one state.
struct MCPRecordSnapshot {
    let entityID: UUID
    let revision: String
    let record: [String: Any]
    let coveredFields: [String: Any]

    private init(entityID: UUID, entity: String, covered: [String: Any], record: [String: Any]) throws {
        self.entityID = entityID
        self.coveredFields = covered
        let revision = try MCPRecordRevision.token(entity: entity, fields: covered)
        self.revision = revision
        var response = record
        response["revision"] = revision
        self.record = response
    }

    static func project(_ project: Project) throws -> Self {
        let fields: [String: Any] = [
            "id": MCPRecordRevision.uuid(project.id), "name": project.name,
            "projectDescription": project.projectDescription,
            "gitRepo": project.gitRepo as Any? ?? NSNull(), "colorHex": project.colorHex
        ]
        var record: [String: Any] = [
            "projectId": project.id.uuidString, "name": project.name,
            "description": project.projectDescription, "colorHex": project.colorHex
        ]
        record["gitRepo"] = project.gitRepo
        return try Self(entityID: project.id, entity: "project", covered: fields, record: record)
    }

    static func comment(_ comment: Comment) throws -> Self {
        let fields: [String: Any] = [
            "id": MCPRecordRevision.uuid(comment.id), "content": comment.content,
            "authorName": comment.authorName, "isAgent": comment.isAgent,
            "creationDate": try MCPRecordRevision.exactDate(comment.creationDate),
            "taskId": MCPRecordRevision.uuid(comment.task?.id)
        ]
        var record: [String: Any] = [
            "id": comment.id.uuidString, "content": comment.content, "authorName": comment.authorName,
            "isAgent": comment.isAgent, "creationDate": timestamp(comment.creationDate)
        ]
        record["taskId"] = comment.task?.id.uuidString
        return try Self(entityID: comment.id, entity: "comment", covered: fields, record: record)
    }

    static func milestone(_ milestone: Milestone) throws -> Self {
        let fields: [String: Any] = [
            "id": MCPRecordRevision.uuid(milestone.id), "name": milestone.name,
            "milestoneDescription": milestone.milestoneDescription as Any? ?? NSNull(),
            "permanentDisplayId": milestone.permanentDisplayId as Any? ?? NSNull(),
            "statusRawValue": milestone.statusRawValue,
            "creationDate": try MCPRecordRevision.exactDate(milestone.creationDate),
            "lastStatusChangeDate": try MCPRecordRevision.exactDate(milestone.lastStatusChangeDate),
            "completionDate": try MCPRecordRevision.exactDate(milestone.completionDate),
            "projectId": MCPRecordRevision.uuid(milestone.project?.id)
        ]
        var record: [String: Any] = [
            "milestoneId": milestone.id.uuidString, "name": milestone.name,
            "status": milestone.statusRawValue, "creationDate": timestamp(milestone.creationDate),
            "lastStatusChangeDate": timestamp(milestone.lastStatusChangeDate),
            "taskCount": (milestone.tasks ?? []).count
        ]
        record["displayId"] = milestone.permanentDisplayId
        record["description"] = milestone.milestoneDescription
        record["projectId"] = milestone.project?.id.uuidString
        record["projectName"] = milestone.project?.name
        record["completionDate"] = milestone.completionDate.map(timestamp)
        return try Self(entityID: milestone.id, entity: "milestone", covered: fields, record: record)
    }

    static func task(_ task: TransitTask, in context: ModelContext) throws -> Self {
        try Self.task(task, incidence: TaskLinkIncidence.capture(task.id, in: context)) {
            try context.fetch(CommentService.descriptor(for: $0))
        }
    }

    static func task(_ task: TransitTask, incidence: [TaskLinkOccurrenceValue]?,
                     budget: TaskLinkGraphBudget? = nil, fetchComments: (UUID) throws -> [Comment]) throws -> Self {
        let comments = try fetchComments(task.id).sorted {
            ($0.creationDate, $0.id.uuidString) < ($1.creationDate, $1.id.uuidString)
        }.map { try Self.comment($0) }
        var fields: [String: Any] = [
            "id": MCPRecordRevision.uuid(task.id), "name": task.name,
            "taskDescription": task.taskDescription as Any? ?? NSNull(),
            "permanentDisplayId": task.permanentDisplayId as Any? ?? NSNull(),
            "statusRawValue": task.statusRawValue, "typeRawValue": task.typeRawValue,
            "priorityRawValue": task.priorityRawValue,
            "creationDate": try MCPRecordRevision.exactDate(task.creationDate),
            "lastStatusChangeDate": try MCPRecordRevision.exactDate(task.lastStatusChangeDate),
            "completionDate": try MCPRecordRevision.exactDate(task.completionDate),
            "metadataJSON": task.metadataJSON as Any? ?? NSNull(),
            "projectId": MCPRecordRevision.uuid(task.project?.id),
            "milestoneId": MCPRecordRevision.uuid(task.milestone?.id),
            "comments": comments.sorted { $0.entityID.uuidString < $1.entityID.uuidString }.map(\.coveredFields)
        ]
        if let incidence {
            fields["linkContract"] = "task-links-v1"
            fields["incidentLinks"] = try TaskLinkIncidence.canonical(incidence, incidentTo: task.id, budget: budget)
        }
        var record: [String: Any] = [
            "taskId": task.id.uuidString, "name": task.name, "status": task.statusRawValue,
            "type": task.typeRawValue, "priority": task.priority.rawValue,
            "creationDate": timestamp(task.creationDate),
            "lastStatusChangeDate": timestamp(task.lastStatusChangeDate),
            "description": task.taskDescription as Any? ?? NSNull(), "metadata": task.metadata,
            "comments": comments.map(\.record)
        ]
        record["graphCoverage"] = incidence == nil ? "unavailable" : "available"
        record["revisionCoverage"] = incidence == nil ? "task-fields-comments-v1" : "task-fields-comments-links-v1"
        record["displayId"] = task.permanentDisplayId
        record["projectId"] = task.project?.id.uuidString
        record["projectName"] = task.project?.name
        record["completionDate"] = task.completionDate.map(timestamp)
        if let milestone = task.milestone {
            var summary: [String: Any] = ["milestoneId": milestone.id.uuidString, "name": milestone.name,
                                           "status": milestone.statusRawValue]
            summary["displayId"] = milestone.permanentDisplayId
            record["milestone"] = summary
        }
        return try Self(entityID: task.id, entity: "task", covered: fields, record: record)
    }

    static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
