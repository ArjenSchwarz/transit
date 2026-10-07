import CoreFoundation
import Foundation
import SwiftData

/// Stages receipts in the shared context; it never saves a domain operation.
@MainActor final class MCPWriteReceiptStore {
    enum Error: Swift.Error { case inconsistentReceipt }
    let scopeID: String
    private let context: ModelContext
    private let container: ModelContainer

    init(context: ModelContext, scopeID: String) {
        self.context = context
        self.container = context.container
        self.scopeID = scopeID
    }

    func lookup(tool: String, key: String, durable: Bool = false) throws -> MCPWriteReceipt? {
        let source = durable ? ModelContext(container) : context
        let scope = scopeID
        let descriptor = FetchDescriptor<MCPWriteReceipt>(
            predicate: #Predicate {
                $0.localScopeID == scope && $0.tool == tool && $0.key == key
            })
        let receipts = try source.fetch(descriptor)
        guard receipts.count <= 1 else { throw Error.inconsistentReceipt }
        if let receipt = receipts.first { try validate(receipt) }
        return receipts.first
    }

    func insert(_ reservation: MCPLocalReservation, acceptedAt: Date) throws -> MCPWriteReceipt {
        guard reservation.scopeID == scopeID,
            try lookup(tool: reservation.tool, key: reservation.key) == nil
        else { throw Error.inconsistentReceipt }
        let receipt = MCPWriteReceipt(
            id: reservation.receiptID, localScopeID: scopeID,
            tool: reservation.tool, key: reservation.key,
            formatVersion: reservation.formatVersion,
            requestJSON: reservation.requestJSON, acceptedAt: acceptedAt)
        context.insert(receipt)
        return receipt
    }

    func validate(_ receipt: MCPWriteReceipt) throws {
        guard receipt.localScopeID == scopeID, receipt.formatVersion == 1,
            !receipt.tool.isEmpty, !receipt.key.isEmpty,
            receipt.acceptedAt.timeIntervalSinceReferenceDate.isFinite,
            let data = receipt.requestJSON.data(using: .utf8),
            let request = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            try MCPCanonicalJSON.encode(request) == receipt.requestJSON
        else {
            throw Error.inconsistentReceipt
        }
        if receipt.stateRawValue == "accepted" {
            guard receipt.completedAt == nil, receipt.expiresAt == nil,
                receipt.resultJSON == nil, receipt.resultIsError == nil
            else { throw Error.inconsistentReceipt }
        } else {
            guard ["committed", "rejected"].contains(receipt.stateRawValue),
                let completed = receipt.completedAt, completed.timeIntervalSinceReferenceDate.isFinite,
                completed >= receipt.acceptedAt,
                let expiry = receipt.expiresAt, expiry.timeIntervalSinceReferenceDate.isFinite,
                expiry == completed.addingTimeInterval(604800),
                let result = receipt.resultJSON?.data(using: .utf8),
                let envelope = try JSONSerialization.jsonObject(with: result) as? [String: Any],
                let version = envelope["contractVersion"], try MCPCanonicalJSON.encode(version) == "1",
                envelope["outcome"] as? String == receipt.stateRawValue,
                envelope["tool"] as? String == receipt.tool,
                envelope["idempotencyKey"] as? String == receipt.key,
                let accepted = envelope["accepted"], try MCPCanonicalJSON.encode(accepted) == "true",
                envelope["completedAt"] as? String == MCPRecordSnapshot.timestamp(completed),
                envelope["replayExpiresAt"] as? String == MCPRecordSnapshot.timestamp(expiry),
                receipt.resultIsError == (receipt.stateRawValue == "rejected")
            else {
                throw Error.inconsistentReceipt
            }
            try validateTerminal(envelope, receipt: receipt, request: request)
        }
    }

    /// Repair terminal guard deadlines before deleting either side. The caller
    /// saves staged receipt deletions; a remaining receipt can restore its guard.
    func cleanup(now: Date, reservations: MCPLocalReservationStore) throws {
        guard reservations.scopeID == scopeID else { throw Error.inconsistentReceipt }
        let scope = scopeID
        let receipts = try context.fetch(
            FetchDescriptor<MCPWriteReceipt>(
                predicate: #Predicate {
                    $0.localScopeID == scope
                }))
        var seenKeys = Set<MCPLocalReservationStore.BindingKey>()
        var seenIDs = Set<UUID>()
        var terminal: [MCPLocalReservation] = []
        for receipt in receipts {
            guard seenKeys.insert(.init(tool: receipt.tool, key: receipt.key)).inserted,
                seenIDs.insert(receipt.id).inserted
            else { throw Error.inconsistentReceipt }
            try validate(receipt)
            guard let expiry = receipt.expiresAt else { continue }
            terminal.append(
                MCPLocalReservation(
                    scopeID: scopeID, tool: receipt.tool, key: receipt.key, requestJSON: receipt.requestJSON,
                    formatVersion: receipt.formatVersion, receiptID: receipt.id, expiresAt: expiry))
        }
        try reservations.reconcileTerminalBindings(terminal, now: now)
        for receipt in receipts where receipt.expiresAt.map({ $0 <= now }) == true {
            context.delete(receipt)
        }
    }
}

extension MCPWriteReceiptStore {
    fileprivate func validateTerminal(
        _ envelope: [String: Any], receipt: MCPWriteReceipt, request: [String: Any]
    ) throws {
        if receipt.stateRawValue == "rejected" {
            try validateRejection(envelope, tool: receipt.tool)
            return
        }
        guard let entity = envelope["entityId"] as? String, let id = UUID(uuidString: entity) else {
            throw Error.inconsistentReceipt
        }
        try validateCommitted(envelope, tool: receipt.tool, id: id, request: request)
    }

    fileprivate func validateCommitted(_ envelope: [String: Any], tool: String, id: UUID,
                                       request: [String: Any]) throws {
        switch tool {
        case "consolidate_tasks":
            try validateConsolidation(envelope, id: id)
            try validateConsolidationHistory(envelope, id: id, requiresReversal: false)
        case "undo_task_consolidation": try validateUndoTerminal(envelope, id: id, request: request)
        case "create_project": try validateRecord(envelope["record"], kind: "project", id: id)
        case "add_comment": try validateRecord(envelope["record"], kind: "comment", id: id)
        case "create_milestone", "update_milestone":
            try validateRecord(envelope["record"], kind: "milestone", id: id)
        case "delete_milestone":
            guard let deleted = envelope["deleted"], try MCPCanonicalJSON.encode(deleted) == "true" else {
                throw Error.inconsistentReceipt
            }
            try validateRecord(envelope["recordBeforeDeletion"], kind: "milestone", id: id)
        case "create_task", "update_task", "update_task_status":
            try validateRecord(envelope["record"], kind: "task", id: id)
            if tool == "update_task_status" {
                try validateStatusComment(envelope["comment"], taskID: id, request: request)
            }
        default: throw Error.inconsistentReceipt
        }
    }

    fileprivate func validateRejection(_ envelope: [String: Any], tool: String) throws {
        guard let error = envelope["error"] as? [String: Any],
            let code = error["code"] as? String, !code.isEmpty,
            error["message"] is String,
            envelope["retryAction"] as? String == "new_request_new_key"
        else { throw Error.inconsistentReceipt }
        let group = ["consolidate_tasks", "undo_task_consolidation"].contains(tool)
        if group && code == "REVISION_CONFLICT" {
            try validateGroupConflict(envelope)
        }
        if (code == "REVISION_CONFLICT" && !group) || envelope["currentRecord"] != nil {
            let kind = ["update_milestone", "delete_milestone"].contains(tool) ? "milestone" : "task"
            try validateRecord(envelope["currentRecord"], kind: kind)
        }

    }

    func validateConsolidation(_ envelope: [String: Any], id: UUID) throws {
        guard (envelope["operationId"] as? String).flatMap(UUID.init(uuidString:)) == id,
              let revision = envelope["operationRevision"] as? String,
              revision.range(of: "^o1:[0-9a-f]{64}$", options: .regularExpression)
                == revision.startIndex..<revision.endIndex,
              let reason = envelope["reason"] as? String,
              !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let participants = envelope["participants"] as? [[String: Any]], (2...6).contains(participants.count),
              let undo = envelope["undoAvailable"],
              ["true", "false"].contains(try MCPCanonicalJSON.encode(undo)) else {
            throw Error.inconsistentReceipt
        }
        if try MCPCanonicalJSON.encode(undo) == "false" {
            guard let unavailable = envelope["undoUnavailableReason"] as? String, !unavailable.isEmpty else {
                throw Error.inconsistentReceipt
            }
        } else if envelope["undoUnavailableReason"] != nil { throw Error.inconsistentReceipt }
        var ids = Set<UUID>()
        for participant in participants {
            try validateRecord(participant, kind: "task")
            guard let raw = participant["taskId"] as? String, let id = UUID(uuidString: raw),
                  ids.insert(id).inserted else { throw Error.inconsistentReceipt }
        }
    }

    fileprivate func validateGroupConflict(_ envelope: [String: Any]) throws {
        guard let ids = envelope["affectedTaskIds"] as? [String], (1...6).contains(ids.count),
              ids.allSatisfy({ UUID(uuidString: $0) != nil }), Set(ids).count == ids.count,
              let revisions = envelope["currentRevisions"] as? [String: String], Set(revisions.keys) == Set(ids),
              revisions.values.allSatisfy({ revision in
                  revision.range(of: "^r1:[0-9a-f]{64}$", options: .regularExpression)
                    == revision.startIndex..<revision.endIndex
              }), envelope["currentRecord"] == nil else { throw Error.inconsistentReceipt }
    }

    fileprivate func validateStatusComment(_ value: Any?, taskID: UUID, request: [String: Any]) throws {
        guard let value else { throw Error.inconsistentReceipt }
        if let record = value as? [String: Any] {
            try validateRecord(record, kind: "comment")
            guard (record["taskId"] as? String).flatMap(UUID.init(uuidString:)) == taskID else {
                throw Error.inconsistentReceipt
            }
        } else {
            let requested = (request["comment"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard value is NSNull, requested?.isEmpty != false else { throw Error.inconsistentReceipt }
        }
    }

    fileprivate func validateRecord(_ value: Any?, kind: String, id: UUID? = nil) throws {
        guard let record = value as? [String: Any], let revision = record["revision"] as? String,
            revision.range(of: "^r1:[0-9a-f]{64}$", options: .regularExpression) == revision
                .startIndex..<revision.endIndex
        else { throw Error.inconsistentReceipt }
        let idField = kind == "comment" ? "id" : kind + "Id"
        guard let rawID = record[idField] as? String, let recordID = UUID(uuidString: rawID),
            id == nil || id == recordID
        else { throw Error.inconsistentReceipt }
        let strings: [String]
        switch kind {
        case "project": strings = ["name", "description", "colorHex"]
        case "comment": strings = ["content", "authorName", "creationDate"]
        case "milestone": strings = ["name", "status", "creationDate", "lastStatusChangeDate"]
        default: strings = ["name", "status", "type", "priority", "creationDate", "lastStatusChangeDate"]
        }
        guard strings.allSatisfy({ record[$0] is String }) else { throw Error.inconsistentReceipt }
        try validateRecordDatesAndIDs(record, idField: idField)
        try validateOptionalRecordFields(record, kind: kind)
        try validateRecordContent(record, kind: kind, id: recordID)
    }

    fileprivate func validateRecordDatesAndIDs(_ record: [String: Any], idField: String) throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for field in ["creationDate", "lastStatusChangeDate", "completionDate"] {
            if let value = record[field] {
                guard let string = value as? String, formatter.date(from: string) != nil else {
                    throw Error.inconsistentReceipt
                }
            }
        }
        for field in ["projectId", "taskId"] where field != idField {
            if let value = record[field] {
                guard let string = value as? String, UUID(uuidString: string) != nil else {
                    throw Error.inconsistentReceipt
                }
            }
        }
    }

    fileprivate func validateOptionalRecordFields(_ record: [String: Any], kind: String) throws {
        for field in ["description", "gitRepo", "projectName"] {
            if let value = record[field] {
                guard value is String || (kind == "task" && field == "description" && value is NSNull) else {
                    throw Error.inconsistentReceipt
                }
            }
        }
        if let displayID = record["displayId"] {
            guard let number = displayID as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                displayID is Int
            else { throw Error.inconsistentReceipt }
        }
        if let milestone = record["milestone"] {
            guard let summary = milestone as? [String: Any],
                let rawID = summary["milestoneId"] as? String, UUID(uuidString: rawID) != nil,
                summary["name"] is String, summary["status"] is String
            else { throw Error.inconsistentReceipt }
            if let displayID = summary["displayId"] {
                guard let number = displayID as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                    displayID is Int
                else { throw Error.inconsistentReceipt }
            }
        }
    }

    fileprivate func validateRecordContent(_ record: [String: Any], kind: String, id: UUID) throws {
        if kind == "comment" {
            guard let number = record["isAgent"] as? NSNumber,
                CFGetTypeID(number) == CFBooleanGetTypeID(), record["taskId"] is String
            else {
                throw Error.inconsistentReceipt
            }
        }
        if kind == "milestone" {
            guard let count = record["taskCount"] as? NSNumber,
                CFGetTypeID(count) != CFBooleanGetTypeID(), let integer = Int(exactly: count.doubleValue),
                integer >= 0
            else { throw Error.inconsistentReceipt }
        }
        if kind == "task" {
            guard record["description"] is String || record["description"] is NSNull,
                let metadata = record["metadata"] as? [String: Any],
                metadata.values.allSatisfy({ $0 is String }),
                let comments = record["comments"] as? [[String: Any]]
            else { throw Error.inconsistentReceipt }
            for comment in comments {
                try validateRecord(comment, kind: "comment")
                guard (comment["taskId"] as? String).flatMap(UUID.init(uuidString:)) == id else {
                    throw Error.inconsistentReceipt
                }
            }
        }
    }
}
