import Foundation
import SwiftData

/// Versioned lossless snapshot. Relationships refer to physical rows, not potentially colliding application UUIDs.
nonisolated struct DatabaseArchive: Codable, Equatable, Sendable {
    var formatVersion = 1
    var createdAt: Date
    var application = "Transit"
    /// Historical local retry bindings are archived for recovery evidence, never installed as executable guards.
    var archivedReservationJSON: [String]?
    struct ProjectRow: Codable, Equatable, Sendable {
        var id: UUID
        var name: String
        var projectDescription: String
        var gitRepo: String?
        var colorHex: String
    }
    var projectRows: [ProjectRow]
    struct MilestoneRow: Codable, Equatable, Sendable {
        var id: UUID
        var permanentDisplayId: Int?
        var name: String
        var milestoneDescription: String?
        var statusRawValue: String
        var creationDate: Date
        var lastStatusChangeDate: Date
        var completionDate: Date?
        var projectRow: Int?
    }
    var milestoneRows: [MilestoneRow]
    struct TransitTaskRow: Codable, Equatable, Sendable {
        var id: UUID
        var permanentDisplayId: Int?
        var name: String
        var taskDescription: String?
        var statusRawValue: String
        var typeRawValue: String
        var priorityRawValue: String
        var creationDate: Date
        var lastStatusChangeDate: Date
        var completionDate: Date?
        var metadataJSON: String?
        var projectRow: Int?
        var milestoneRow: Int?
    }
    var transitTaskRows: [TransitTaskRow]
    struct CommentRow: Codable, Equatable, Sendable {
        var id: UUID
        var content: String
        var authorName: String
        var isAgent: Bool
        var creationDate: Date
        var taskRow: Int?
    }
    var commentRows: [CommentRow]
    struct SyncHeartbeatRow: Codable, Equatable, Sendable {
        var id: String
        var lastBeat: Date
    }
    var syncHeartbeatRows: [SyncHeartbeatRow]
    struct MCPWriteReceiptRow: Codable, Equatable, Sendable {
        var id: UUID
        var localScopeID: String
        var tool: String
        var key: String
        var formatVersion: Int
        var requestJSON: String
        var stateRawValue: String
        var acceptedAt: Date
        var completedAt: Date?
        var expiresAt: Date?
        var resultJSON: String?
        var resultIsError: Bool?
    }
    var mCPWriteReceiptRows: [MCPWriteReceiptRow]
    struct TaskLinkOccurrenceRow: Codable, Equatable, Sendable {
        var id: UUID
        var kindRawValue: String
        var sourceTaskID: UUID
        var targetTaskID: UUID
        var createdAt: Date
    }
    var taskLinkOccurrenceRows: [TaskLinkOccurrenceRow]
    struct TaskLinkRemovalEvidenceRow: Codable, Equatable, Sendable {
        var id: UUID
        var edgeId: UUID
        var kindRawValue: String
        var sourceTaskID: UUID
        var targetTaskID: UUID
        var createdAt: Date
        var occurrenceRevision: String
        var removedAt: Date
    }
    var taskLinkRemovalEvidenceRows: [TaskLinkRemovalEvidenceRow]
    struct TaskConsolidationEventRow: Codable, Equatable, Sendable {
        var id: UUID
        var operationId: UUID
        var kindRawValue: String
        var createdAt: Date
        var originScopeId: String
        var survivorTaskId: UUID
        var candidate1: UUID?
        var candidate2: UUID?
        var candidate3: UUID?
        var candidate4: UUID?
        var candidate5: UUID?
        var payloadJSON: String
    }
    var taskConsolidationEventRows: [TaskConsolidationEventRow]
}

extension DatabaseArchive {
    // Explicit coverage of every persisted entity is kept together for review.
    // swiftlint:disable:next function_body_length
    @MainActor static func capture(
        _ context: ModelContext, now: Date = .now,
        ordering: [String: [PersistentIdentifier]]? = nil
    ) throws
        -> DatabaseArchive {
        let persistent = !context.container.configurations.allSatisfy(\.isStoredInMemoryOnly)
        let before = persistent ? try SavedReadBoundary.watermark(context.container) : nil
        func ordered<T: PersistentModel>(_ rows: [T], type: String, key: (T) -> String) throws -> [T] {
            if let ids = ordering?[type] {
                let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.persistentModelID, $0) })
                guard ids.count == rows.count else { throw DatabaseBackupError.changed }
                return try ids.map { id in
                    guard let row = byID[id] else { throw DatabaseBackupError.changed }
                    return row
                }
            }
            let decorated: [(row: T, key: String)] = rows.map { (row: $0, key: key($0)) }
            let sorted = decorated.sorted { left, right in
                if left.key == right.key {
                    let first = String(describing: left.row.persistentModelID)
                    let second = String(describing: right.row.persistentModelID)
                    return first < second
                }
                return left.key < right.key
            }
            return sorted.map { $0.row }
        }
        let projects = try ordered(context.fetch(FetchDescriptor<Project>()), type: "Project") { row in

            let value = ProjectRow(
                id: row.id, name: row.name, projectDescription: row.projectDescription,
                gitRepo: row.gitRepo, colorHex: row.colorHex)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            return (try? encoder.encode(value).base64EncodedString()) ?? ""
        }
        let milestones = try ordered(context.fetch(FetchDescriptor<Milestone>()), type: "Milestone") { row in

            let value = MilestoneRow(
                id: row.id, permanentDisplayId: row.permanentDisplayId, name: row.name,
                milestoneDescription: row.milestoneDescription, statusRawValue: row.statusRawValue,
                creationDate: row.creationDate, lastStatusChangeDate: row.lastStatusChangeDate,
                completionDate: row.completionDate, projectRow: nil)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            return (try? encoder.encode(value).base64EncodedString()) ?? ""
        }
        let transitTasks = try ordered(context.fetch(FetchDescriptor<TransitTask>()), type: "TransitTask") { row in

            let value = TransitTaskRow(
                id: row.id, permanentDisplayId: row.permanentDisplayId, name: row.name,
                taskDescription: row.taskDescription, statusRawValue: row.statusRawValue,
                typeRawValue: row.typeRawValue, priorityRawValue: row.priorityRawValue,
                creationDate: row.creationDate, lastStatusChangeDate: row.lastStatusChangeDate,
                completionDate: row.completionDate, metadataJSON: row.metadataJSON, projectRow: nil,
                milestoneRow: nil)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            return (try? encoder.encode(value).base64EncodedString()) ?? ""
        }
        let comments = try ordered(context.fetch(FetchDescriptor<Comment>()), type: "Comment") { row in

            let value = CommentRow(
                id: row.id, content: row.content, authorName: row.authorName, isAgent: row.isAgent,
                creationDate: row.creationDate, taskRow: nil)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            return (try? encoder.encode(value).base64EncodedString()) ?? ""
        }
        let syncHeartbeats = try ordered(
            context.fetch(FetchDescriptor<SyncHeartbeat>()), type: "SyncHeartbeat"
        ) { row in

            let value = SyncHeartbeatRow(id: row.id, lastBeat: row.lastBeat)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            return (try? encoder.encode(value).base64EncodedString()) ?? ""
        }
        let mCPWriteReceipts = try ordered(
            context.fetch(FetchDescriptor<MCPWriteReceipt>()), type: "MCPWriteReceipt"
        ) { row in

            let value = MCPWriteReceiptRow(
                id: row.id, localScopeID: row.localScopeID, tool: row.tool, key: row.key,
                formatVersion: row.formatVersion, requestJSON: row.requestJSON,
                stateRawValue: row.stateRawValue, acceptedAt: row.acceptedAt,
                completedAt: row.completedAt, expiresAt: row.expiresAt, resultJSON: row.resultJSON,
                resultIsError: row.resultIsError)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            return (try? encoder.encode(value).base64EncodedString()) ?? ""
        }
        let taskLinkOccurrences = try ordered(
            context.fetch(FetchDescriptor<TaskLinkOccurrence>()), type: "TaskLinkOccurrence"
        ) { row in

            let value = TaskLinkOccurrenceRow(
                id: row.id, kindRawValue: row.kindRawValue, sourceTaskID: row.sourceTaskID,
                targetTaskID: row.targetTaskID, createdAt: row.createdAt)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            return (try? encoder.encode(value).base64EncodedString()) ?? ""
        }
        let taskLinkRemovalEvidences = try ordered(
            context.fetch(FetchDescriptor<TaskLinkRemovalEvidence>()), type: "TaskLinkRemovalEvidence"
        ) { row in

            let value = TaskLinkRemovalEvidenceRow(
                id: row.id, edgeId: row.edgeId, kindRawValue: row.kindRawValue,
                sourceTaskID: row.sourceTaskID, targetTaskID: row.targetTaskID,
                createdAt: row.createdAt, occurrenceRevision: row.occurrenceRevision,
                removedAt: row.removedAt)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            return (try? encoder.encode(value).base64EncodedString()) ?? ""
        }
        let taskConsolidationEvents = try ordered(
            context.fetch(FetchDescriptor<TaskConsolidationEvent>()), type: "TaskConsolidationEvent"
        ) { row in

            let value = TaskConsolidationEventRow(
                id: row.id, operationId: row.operationId, kindRawValue: row.kindRawValue,
                createdAt: row.createdAt, originScopeId: row.originScopeId,
                survivorTaskId: row.survivorTaskId, candidate1: row.candidate1,
                candidate2: row.candidate2, candidate3: row.candidate3, candidate4: row.candidate4,
                candidate5: row.candidate5, payloadJSON: row.payloadJSON)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            return (try? encoder.encode(value).base64EncodedString()) ?? ""
        }
        let physicalIndexes: [String: [PersistentIdentifier: Int]] = [
            "Project": Dictionary(
                uniqueKeysWithValues: projects.enumerated().map { ($0.element.persistentModelID, $0.offset) }),
            "Milestone": Dictionary(
                uniqueKeysWithValues: milestones.enumerated().map { ($0.element.persistentModelID, $0.offset) }),
            "TransitTask": Dictionary(
                uniqueKeysWithValues: transitTasks.enumerated().map { ($0.element.persistentModelID, $0.offset) })
        ]
        func index<T: PersistentModel>(_ value: T?, in rows: [T]) throws -> Int? {
            guard let value else { return nil }
            guard let index = physicalIndexes[String(describing: T.self)]?[value.persistentModelID]
            else {
                throw DatabaseBackupError.invalidArchive("Relationship points outside the saved database.")
            }
            return index
        }
        let archive = try DatabaseArchive(
            createdAt: now,
            projectRows: projects.map { row in
                ProjectRow(
                    id: row.id, name: row.name, projectDescription: row.projectDescription,
                    gitRepo: row.gitRepo, colorHex: row.colorHex)
            },
            milestoneRows: milestones.map { row in
                MilestoneRow(
                    id: row.id, permanentDisplayId: row.permanentDisplayId, name: row.name,
                    milestoneDescription: row.milestoneDescription, statusRawValue: row.statusRawValue,
                    creationDate: row.creationDate, lastStatusChangeDate: row.lastStatusChangeDate,
                    completionDate: row.completionDate, projectRow: try index(row.project, in: projects))
            },
            transitTaskRows: transitTasks.map { row in
                TransitTaskRow(
                    id: row.id, permanentDisplayId: row.permanentDisplayId, name: row.name,
                    taskDescription: row.taskDescription, statusRawValue: row.statusRawValue,
                    typeRawValue: row.typeRawValue, priorityRawValue: row.priorityRawValue,
                    creationDate: row.creationDate, lastStatusChangeDate: row.lastStatusChangeDate,
                    completionDate: row.completionDate, metadataJSON: row.metadataJSON,
                    projectRow: try index(row.project, in: projects),
                    milestoneRow: try index(row.milestone, in: milestones))
            },
            commentRows: comments.map { row in
                CommentRow(
                    id: row.id, content: row.content, authorName: row.authorName, isAgent: row.isAgent,
                    creationDate: row.creationDate, taskRow: try index(row.task, in: transitTasks))
            },
            syncHeartbeatRows: syncHeartbeats.map { row in
                SyncHeartbeatRow(id: row.id, lastBeat: row.lastBeat)
            },
            mCPWriteReceiptRows: mCPWriteReceipts.map { row in
                MCPWriteReceiptRow(
                    id: row.id, localScopeID: row.localScopeID, tool: row.tool, key: row.key,
                    formatVersion: row.formatVersion, requestJSON: row.requestJSON,
                    stateRawValue: row.stateRawValue, acceptedAt: row.acceptedAt,
                    completedAt: row.completedAt, expiresAt: row.expiresAt, resultJSON: row.resultJSON,
                    resultIsError: row.resultIsError)
            },
            taskLinkOccurrenceRows: taskLinkOccurrences.map { row in
                TaskLinkOccurrenceRow(
                    id: row.id, kindRawValue: row.kindRawValue, sourceTaskID: row.sourceTaskID,
                    targetTaskID: row.targetTaskID, createdAt: row.createdAt)
            },
            taskLinkRemovalEvidenceRows: taskLinkRemovalEvidences.map { row in
                TaskLinkRemovalEvidenceRow(
                    id: row.id, edgeId: row.edgeId, kindRawValue: row.kindRawValue,
                    sourceTaskID: row.sourceTaskID, targetTaskID: row.targetTaskID, createdAt: row.createdAt,
                    occurrenceRevision: row.occurrenceRevision, removedAt: row.removedAt)
            },
            taskConsolidationEventRows: taskConsolidationEvents.map { row in
                TaskConsolidationEventRow(
                    id: row.id, operationId: row.operationId, kindRawValue: row.kindRawValue,
                    createdAt: row.createdAt, originScopeId: row.originScopeId,
                    survivorTaskId: row.survivorTaskId, candidate1: row.candidate1,
                    candidate2: row.candidate2, candidate3: row.candidate3, candidate4: row.candidate4,
                    candidate5: row.candidate5, payloadJSON: row.payloadJSON)
            })
        let after = persistent ? try SavedReadBoundary.watermark(context.container) : nil
        guard before?.token == after?.token, before?.storeIdentifier == after?.storeIdentifier else {
            throw DatabaseBackupError.changed
        }
        return archive
    }
}
