import Foundation
import CryptoKit

nonisolated struct TaskConsolidationRawFields: Codable, Equatable, Sendable {
    let description: String?
    let metadataJSON: String?
    let statusRawValue: String
    let lastStatusChangeDate: String
    let completionDate: String?

    static func exactDate(_ date: Date) throws -> String {
        let interval = date.timeIntervalSinceReferenceDate
        guard interval.isFinite else { throw TaskConsolidationHistoryError.malformed }
        return String(interval.bitPattern, radix: 16)
    }

    static func date(_ bits: String) throws -> Date {
        guard let raw = UInt64(bits, radix: 16), String(raw, radix: 16) == bits,
              Double(bitPattern: raw).isFinite else { throw TaskConsolidationHistoryError.malformed }
        return Date(timeIntervalSinceReferenceDate: Double(bitPattern: raw))
    }
}

nonisolated struct TaskConsolidationOccurrence: Codable, Hashable, Sendable {
    let id: UUID
    let kind: String
    let source: UUID
    let target: UUID
    let createdAt: String
    let revision: String
}

nonisolated struct TaskConsolidationPayload: Codable, Equatable, Sendable {
    var version = 1
    let operationId: UUID
    let kind: String
    let survivorTaskId: UUID
    let candidateTaskIds: [UUID]
    let reason: String
    let preservationJSON: String
    let changes: [TaskConsolidationTaskChange]
    let appliedRevisions: [String: String]
    let createdOccurrences: [TaskConsolidationOccurrence]
    let retainedOccurrences: [TaskConsolidationOccurrence]
    var removedOccurrences: [TaskConsolidationOccurrence] = []
    let requestKey: String
    let reviewId: UUID
    let reviewRevision: String
    var mappings: [TaskConsolidationMapping]?
}

nonisolated struct TaskConsolidationEventValue: Codable, Equatable, Sendable {
    let physicalKey: Data
    let id: UUID
    let operationId: UUID
    let kind: String
    let createdAt: String
    let originScopeId: String
    let survivorTaskId: UUID
    let candidateSlots: [UUID?]
    let payloadJSON: String
}

nonisolated enum TaskConsolidationHistoryError: Error {
    case capacityExceeded, malformed, unsupportedVersion, ambiguous, missingApply
}

nonisolated enum TaskConsolidationHistoryCodec {
    static let maximumPayloadBytes = 256 * 1_024

    static func encode(_ payload: TaskConsolidationPayload) throws -> String {
        try validate(payload)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let bytes = try encoder.encode(payload)
        guard bytes.count <= maximumPayloadBytes else { throw TaskConsolidationHistoryError.capacityExceeded }
        guard let result = String(data: bytes, encoding: .utf8) else { throw TaskConsolidationHistoryError.malformed }
        return result
    }

    static func decode(_ value: TaskConsolidationEventValue) throws -> TaskConsolidationPayload {
        guard value.payloadJSON.utf8.count <= maximumPayloadBytes else {
            throw TaskConsolidationHistoryError.capacityExceeded
        }
        let payload = try JSONDecoder().decode(TaskConsolidationPayload.self, from: Data(value.payloadJSON.utf8))
        try validate(payload)
        let slots = value.candidateSlots
        guard slots.count == 5, slots.prefix(payload.candidateTaskIds.count).compactMap({ $0 })
                == payload.candidateTaskIds, slots.dropFirst(payload.candidateTaskIds.count).allSatisfy({ $0 == nil }),
              value.operationId == payload.operationId, value.kind == payload.kind,
              value.survivorTaskId == payload.survivorTaskId, !value.originScopeId.isEmpty,
              value.kind != "apply" || value.id == value.operationId else {
            throw TaskConsolidationHistoryError.malformed
        }
        _ = try TaskConsolidationRawFields.date(value.createdAt)
        return payload
    }

    static func validate(_ payload: TaskConsolidationPayload) throws {
        guard payload.version == 1 else { throw TaskConsolidationHistoryError.unsupportedVersion }
        let participants = [payload.survivorTaskId] + payload.candidateTaskIds
        guard ["apply", "undo"].contains(payload.kind), (1...5).contains(payload.candidateTaskIds.count),
              Set(participants).count == participants.count,
              !payload.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !payload.requestKey.isEmpty, token(payload.reviewRevision, prefix: "p1:"),
              Set(payload.changes.map(\.taskId)).count == payload.changes.count,
              payload.changes.allSatisfy({ participants.contains($0.taskId) }) else {
            throw TaskConsolidationHistoryError.malformed
        }
        let revisionIds = payload.appliedRevisions.keys.compactMap(UUID.init(uuidString:))
        guard revisionIds.count == participants.count, Set(revisionIds) == Set(participants),
              payload.appliedRevisions.values.allSatisfy({ token($0, prefix: "r1:") }) else {
            throw TaskConsolidationHistoryError.malformed
        }
        if let mappings = payload.mappings {
            guard mappings.count == participants.count,
                  Set(mappings.map(\.sourceTaskId)) == Set(participants), mappings.allSatisfy({ mapping in
                      mapping.path.first == mapping.sourceTaskId && mapping.path.last == mapping.canonicalTaskId
                          && mapping.canonicalTaskId == payload.survivorTaskId
                          && Set(mapping.path).count == mapping.path.count
                          && Set(mapping.directTaskIds).count == mapping.directTaskIds.count
                  }) else { throw TaskConsolidationHistoryError.malformed }
        }
        try validatePreservation(payload)
        try validateChanges(payload.changes)
        for occurrence in payload.createdOccurrences + payload.retainedOccurrences + payload.removedOccurrences {
            let date = try TaskConsolidationRawFields.date(occurrence.createdAt)
            guard ["dependency", "association", "attribution", "duplicate"].contains(occurrence.kind),
                  occurrence.source != occurrence.target, token(occurrence.revision, prefix: "l1:") else {
                throw TaskConsolidationHistoryError.malformed
            }
            let fields = ["id": occurrence.id.uuidString.lowercased(), "kind": occurrence.kind,
                "source": occurrence.source.uuidString.lowercased(),
                "target": occurrence.target.uuidString.lowercased(),
                "createdAt": try TaskConsolidationRawFields.exactDate(date)]
            let bytes = try JSONSerialization.data(withJSONObject: fields,
                options: [.sortedKeys, .withoutEscapingSlashes])
            let fingerprint = "l1:" + SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            guard fingerprint == occurrence.revision else { throw TaskConsolidationHistoryError.malformed }
        }
        guard payload.kind == "apply" ? payload.removedOccurrences.isEmpty : payload.createdOccurrences.isEmpty else {
            throw TaskConsolidationHistoryError.malformed
        }
        let created = payload.kind == "apply" ? payload.createdOccurrences : payload.removedOccurrences
        guard Set(created.map(\.id)).count == created.count,
              created.allSatisfy({ $0.kind == "duplicate" && payload.candidateTaskIds.contains($0.source)
                  && $0.target == payload.survivorTaskId }) else { throw TaskConsolidationHistoryError.malformed }
    }

    private static func validateChanges(_ changes: [TaskConsolidationTaskChange]) throws {
        for change in changes { try change.validate() }
    }

    private static func token(_ value: String, prefix: String) -> Bool {
        value.hasPrefix(prefix) && value.count == prefix.count + 64
            && value.dropFirst(prefix.count).allSatisfy { "0123456789abcdef".contains($0) }
    }

    private static func validatePreservation(_ payload: TaskConsolidationPayload) throws {
        guard let entries = try JSONSerialization.jsonObject(with: Data(payload.preservationJSON.utf8))
                as? [String: [String: Any]], entries.count == payload.candidateTaskIds.count,
              Set(entries.keys.compactMap(UUID.init(uuidString:))) == Set(payload.candidateTaskIds) else {
            throw TaskConsolidationHistoryError.malformed
        }
        for entry in entries.values {
            guard Set(entry.keys).isSubset(of: ["incorporated", "retainedExplanation"]) else {
                throw TaskConsolidationHistoryError.malformed
            }
            var accounted = false
            if let raw = entry["retainedExplanation"] {
                guard let text = raw as? String,
                      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw TaskConsolidationHistoryError.malformed
                }
                accounted = true
            }
            if let raw = entry["incorporated"] {
                guard let references = raw as? [[String: String]], !references.isEmpty else {
                    throw TaskConsolidationHistoryError.malformed
                }
                for reference in references {
                    guard Set(reference.keys) == ["sourceDetail", "survivorField"],
                          let source = reference["sourceDetail"], !source.isEmpty,
                          let field = reference["survivorField"], ["description", "metadata"].contains(field),
                          payload.changes.contains(where: { change in
                              change.taskId == payload.survivorTaskId && (field == "description"
                                  ? change.fields["description"] != nil : change.fields["metadataJSON"] != nil)
                          }) else { throw TaskConsolidationHistoryError.malformed }
                }
                accounted = true
            }
            guard accounted else { throw TaskConsolidationHistoryError.malformed }
        }
    }

    /// Immutable scalar content and physical multiplicity are retained in the digest.
    static func revision(_ events: [TaskConsolidationEventValue]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let tuples = try events.map { value in
            // Temporary SwiftData physical IDs can change during the one save.
            // Scalar event tuples and multiplicity are the stable content evidence.
            let stable = TaskConsolidationEventValue(physicalKey: Data(), id: value.id,
                operationId: value.operationId, kind: value.kind, createdAt: value.createdAt,
                originScopeId: value.originScopeId, survivorTaskId: value.survivorTaskId,
                candidateSlots: value.candidateSlots, payloadJSON: value.payloadJSON)
            return try encoder.encode(stable)
        }.sorted { $0.lexicographicallyPrecedes($1) }
        let bytes = try encoder.encode(tuples)
        return "o1:" + SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    private static func sameOccurrences(_ lhs: [TaskConsolidationOccurrence],
                                        _ rhs: [TaskConsolidationOccurrence]) -> Bool {
        Dictionary(grouping: lhs, by: { $0 }).mapValues(\.count)
            == Dictionary(grouping: rhs, by: { $0 }).mapValues(\.count)
    }

    static func history(_ events: [TaskConsolidationEventValue], operationId: UUID)
        throws -> (apply: TaskConsolidationPayload, reversal: TaskConsolidationPayload?) {
        guard events.allSatisfy({ $0.operationId == operationId }),
              Set(events.map(\.id)).count == events.count,
              Set(events.map(\.physicalKey)).count == events.count else {
            throw TaskConsolidationHistoryError.ambiguous
        }
        let decoded = try events.map(decode)
        let applies = decoded.filter { $0.kind == "apply" }
        let reversals = decoded.filter { $0.kind == "undo" }
        guard !applies.isEmpty else { throw TaskConsolidationHistoryError.missingApply }
        guard applies.count == 1, reversals.count <= 1 else { throw TaskConsolidationHistoryError.ambiguous }
        let apply = applies[0]
        if let reversal = reversals.first {
            guard apply.survivorTaskId == reversal.survivorTaskId,
                  apply.candidateTaskIds == reversal.candidateTaskIds,
                  Dictionary(uniqueKeysWithValues: apply.changes.map { ($0.taskId, $0.inverse) })
                    == Dictionary(uniqueKeysWithValues: reversal.changes.map { ($0.taskId, $0) }),
                  sameOccurrences(reversal.removedOccurrences, apply.createdOccurrences),
                  sameOccurrences(reversal.retainedOccurrences, apply.retainedOccurrences),
                  reversal.mappings == apply.mappings else {
                throw TaskConsolidationHistoryError.malformed
            }
        }
        return (apply, reversals.first)
    }
}
