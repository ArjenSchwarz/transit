import Foundation
import SwiftData

extension DatabaseArchive {
    nonisolated static var schema: Schema {
        Schema([
            Project.self, Milestone.self, TransitTask.self, Comment.self, SyncHeartbeat.self,
            MCPWriteReceipt.self, TaskLinkOccurrence.self, TaskLinkRemovalEvidence.self,
            TaskConsolidationEvent.self
        ])
    }

    nonisolated func validate() throws {
        guard formatVersion == 1, application == "Transit" else {
            throw DatabaseBackupError.invalidArchive("Unsupported Transit backup version.")
        }
        guard
            milestoneRows.allSatisfy({ row in
                row.projectRow.map { projectRows.indices.contains($0) } ?? true
            })
        else { throw DatabaseBackupError.invalidArchive("Invalid project relationship.") }
        guard
            transitTaskRows.allSatisfy({ row in
                row.projectRow.map { projectRows.indices.contains($0) } ?? true
            })
        else { throw DatabaseBackupError.invalidArchive("Invalid project relationship.") }
        guard
            transitTaskRows.allSatisfy({ row in
                row.milestoneRow.map { milestoneRows.indices.contains($0) } ?? true
            })
        else { throw DatabaseBackupError.invalidArchive("Invalid milestone relationship.") }
        guard
            commentRows.allSatisfy({ row in
                row.taskRow.map { transitTaskRows.indices.contains($0) } ?? true
            })
        else { throw DatabaseBackupError.invalidArchive("Invalid task relationship.") }
    }

    // One ordered restoration establishes every inverse relationship before the single save.
    // swiftlint:disable:next function_body_length
    nonisolated func insert(into context: ModelContext) throws -> [String: [any PersistentModel]] {
        try validate()
        let placeholderProject = Project(name: "", description: "", gitRepo: nil, colorHex: "")
        let placeholderTask = TransitTask(
            name: "", type: .feature, project: placeholderProject, displayID: .provisional)
        let projects = projectRows.map { row in
            let model = Project(
                name: row.name, description: row.projectDescription, gitRepo: row.gitRepo,
                colorHex: row.colorHex)
            model.id = row.id
            model.name = row.name
            model.projectDescription = row.projectDescription
            model.gitRepo = row.gitRepo
            model.colorHex = row.colorHex
            context.insert(model)
            return model
        }
        let milestones = milestoneRows.map { row in
            let model = Milestone(
                name: row.name, description: row.milestoneDescription, project: placeholderProject,
                displayID: .provisional)
            model.id = row.id
            model.permanentDisplayId = row.permanentDisplayId
            model.name = row.name
            model.milestoneDescription = row.milestoneDescription
            model.statusRawValue = row.statusRawValue
            model.creationDate = row.creationDate
            model.lastStatusChangeDate = row.lastStatusChangeDate
            model.completionDate = row.completionDate
            model.project = row.projectRow.map { projects[$0] }
            context.insert(model)
            return model
        }
        let transitTasks = transitTaskRows.map { row in
            let model = TransitTask(
                name: row.name, description: row.taskDescription, type: .feature,
                project: placeholderProject, displayID: .provisional)
            model.id = row.id
            model.permanentDisplayId = row.permanentDisplayId
            model.name = row.name
            model.taskDescription = row.taskDescription
            model.statusRawValue = row.statusRawValue
            model.typeRawValue = row.typeRawValue
            model.priorityRawValue = row.priorityRawValue
            model.creationDate = row.creationDate
            model.lastStatusChangeDate = row.lastStatusChangeDate
            model.completionDate = row.completionDate
            model.metadataJSON = row.metadataJSON
            model.project = row.projectRow.map { projects[$0] }
            model.milestone = row.milestoneRow.map { milestones[$0] }
            context.insert(model)
            return model
        }
        let comments = commentRows.map { row in
            let model = Comment(
                content: row.content, authorName: row.authorName, isAgent: row.isAgent,
                task: placeholderTask)
            model.id = row.id
            model.content = row.content
            model.authorName = row.authorName
            model.isAgent = row.isAgent
            model.creationDate = row.creationDate
            model.task = row.taskRow.map { transitTasks[$0] }
            context.insert(model)
            return model
        }
        let syncHeartbeats = syncHeartbeatRows.map { row in
            let model = SyncHeartbeat()
            model.id = row.id
            model.lastBeat = row.lastBeat
            context.insert(model)
            return model
        }
        let mCPWriteReceipts = mCPWriteReceiptRows.map { row in
            let model = MCPWriteReceipt(
                id: row.id, localScopeID: row.localScopeID, tool: row.tool, key: row.key,
                formatVersion: row.formatVersion, requestJSON: row.requestJSON, acceptedAt: row.acceptedAt)
            model.id = row.id
            model.localScopeID = row.localScopeID
            model.tool = row.tool
            model.key = row.key
            model.formatVersion = row.formatVersion
            model.requestJSON = row.requestJSON
            model.stateRawValue = row.stateRawValue
            model.acceptedAt = row.acceptedAt
            model.completedAt = row.completedAt
            model.expiresAt = row.expiresAt
            model.resultJSON = row.resultJSON
            model.resultIsError = row.resultIsError
            context.insert(model)
            return model
        }
        let taskLinkOccurrences = taskLinkOccurrenceRows.map { row in
            let model = TaskLinkOccurrence(
                id: row.id, kindRawValue: row.kindRawValue, sourceTaskID: row.sourceTaskID,
                targetTaskID: row.targetTaskID, createdAt: row.createdAt)
            context.insert(model)
            return model
        }
        let taskLinkRemovalEvidences = taskLinkRemovalEvidenceRows.map { row in
            let model = TaskLinkRemovalEvidence(
                id: row.id, edgeId: row.edgeId, kindRawValue: row.kindRawValue,
                sourceTaskID: row.sourceTaskID, targetTaskID: row.targetTaskID, createdAt: row.createdAt,
                occurrenceRevision: row.occurrenceRevision, removedAt: row.removedAt)
            context.insert(model)
            return model
        }
        let taskConsolidationEvents = try taskConsolidationEventRows.map { row in
            let model = try TaskConsolidationEvent(
                id: row.id, operationId: row.operationId, kindRawValue: row.kindRawValue,
                createdAt: row.createdAt, originScopeId: row.originScopeId,
                survivorTaskId: row.survivorTaskId, candidateTaskIds: [], payloadJSON: row.payloadJSON,
                archivedCandidateSlots: [
                    row.candidate1, row.candidate2, row.candidate3, row.candidate4, row.candidate5
                ])
            context.insert(model)
            return model
        }
        return [
            "Project": projects.map { $0 as any PersistentModel },
            "Milestone": milestones.map { $0 as any PersistentModel },
            "TransitTask": transitTasks.map { $0 as any PersistentModel },
            "Comment": comments.map { $0 as any PersistentModel },
            "SyncHeartbeat": syncHeartbeats.map { $0 as any PersistentModel },
            "MCPWriteReceipt": mCPWriteReceipts.map { $0 as any PersistentModel },
            "TaskLinkOccurrence": taskLinkOccurrences.map { $0 as any PersistentModel },
            "TaskLinkRemovalEvidence": taskLinkRemovalEvidences.map { $0 as any PersistentModel },
            "TaskConsolidationEvent": taskConsolidationEvents.map { $0 as any PersistentModel }
        ]
    }

    @MainActor static func deleteAll(in context: ModelContext) throws {
        for row in try context.fetch(FetchDescriptor<TaskConsolidationEvent>()) { context.delete(row) }
        for row in try context.fetch(FetchDescriptor<TaskLinkRemovalEvidence>()) { context.delete(row) }
        for row in try context.fetch(FetchDescriptor<TaskLinkOccurrence>()) { context.delete(row) }
        for row in try context.fetch(FetchDescriptor<MCPWriteReceipt>()) { context.delete(row) }
        for row in try context.fetch(FetchDescriptor<SyncHeartbeat>()) { context.delete(row) }
        for row in try context.fetch(FetchDescriptor<Comment>()) { context.delete(row) }
        for row in try context.fetch(FetchDescriptor<TransitTask>()) { context.delete(row) }
        for row in try context.fetch(FetchDescriptor<Milestone>()) { context.delete(row) }
        for row in try context.fetch(FetchDescriptor<Project>()) { context.delete(row) }
    }
}
