import Foundation
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct TaskConsolidationReviewFixTests {
    @Test func unchangedLargeCandidateFieldsDoNotConsumeHistoryCapacity() throws {
        let value = try fixture(description: String(repeating: "x", count: 300_000),
            metadata: "{\"retained\":\"" + String(repeating: "m", count: 300_000) + "\"}")
        let json = try TaskConsolidationHistoryCodec.encode(value)
        let document = try object(json)
        let changes = try #require(document["changes"] as? [[String: Any]])
        let fields = try #require(changes.first?["fields"] as? [String: Any])
        #expect(Set(fields.keys) == ["statusRawValue", "lastStatusChangeDate", "completionDate"])
        #expect(json.utf8.count < 4_096)
    }

    @Test func changedLargeFieldUsesExactEncodedCapAndExplicitNull() throws {
        let baseline = try TaskConsolidationHistoryCodec.encode(fixture(changedDescription: "x")).utf8.count
        let size = TaskConsolidationHistoryCodec.maximumPayloadBytes - baseline + 1
        let exact = try fixture(changedDescription: String(repeating: "x", count: size))
        let json = try TaskConsolidationHistoryCodec.encode(exact)
        #expect(json.utf8.count == TaskConsolidationHistoryCodec.maximumPayloadBytes)
        #expect(throws: (any Error).self) {
            try TaskConsolidationHistoryCodec.encode(fixture(changedDescription:
                String(repeating: "x", count: size + 1)))
        }
        let changes = try #require(object(json)["changes"] as? [[String: Any]])
        let fields = try #require(changes.first?["fields"] as? [String: [String: Any]])
        #expect(fields["description"]?["before"] is NSNull)
        #expect(fields["metadataJSON"] == nil)
    }

    @Test func forwardApplyRelabeledUndoCannotBeAccepted() throws {
        let apply = try event(fixture())
        var document = try object(apply.payloadJSON)
        document["kind"] = "undo"
        let undo = try copied(apply, document: document, kind: "undo")
        #expect(throws: (any Error).self) {
            try TaskConsolidationHistoryCodec.history([apply, undo], operationId: apply.operationId)
        }
    }

    @Test(arguments: ["field", "removed", "retained", "multiplicity"])
    func reversalMustMatchInverseAndOnlyAttributableRemoval(fault: String) throws {
        let base = try event(fixture())
        var document = try object(base.payloadJSON)
        let created = try occurrence(source: try #require(base.candidateSlots[0]), target: base.survivorTaskId,
            kind: "duplicate")
        let retained = try occurrence(source: try #require(base.candidateSlots[0]),
            target: UUID(), kind: "duplicate")
        document["createdOccurrences"] = [created]
        let other = try occurrence(source: try #require(base.candidateSlots[0]), target: UUID(), kind: "duplicate")
        document["retainedOccurrences"] = fault == "multiplicity" ? [retained, retained, other] : [retained]
        let apply = try copied(base, document: document, kind: "apply", id: base.id)
        var undoDocument = try inverse(document)
        let valid = try copied(base, document: undoDocument, kind: "undo")
        #expect(try TaskConsolidationHistoryCodec.history([apply, valid],
            operationId: base.operationId).reversal != nil)
        switch fault {
        case "field": undoDocument["changes"] = document["changes"]
        case "removed": undoDocument["removedOccurrences"] = [retained]
        case "multiplicity": undoDocument["retainedOccurrences"] = [retained, other, other]
        default: undoDocument["retainedOccurrences"] = [] as [[String: Any]]
        }
        let corrupt = try copied(base, document: undoDocument, kind: "undo")
        #expect(throws: (any Error).self) {
            try TaskConsolidationHistoryCodec.history([apply, corrupt], operationId: base.operationId)
        }
    }

    @Test(arguments: ["missing", "unchanged", "unknown"])
    func malformedChangedFieldDeltaFailsClosed(fault: String) throws {
        let base = try event(fixture())
        var document = try object(base.payloadJSON)
        var changes = try #require(document["changes"] as? [[String: Any]])
        var fields = try #require(changes[0]["fields"] as? [String: [String: Any]])
        switch fault {
        case "missing": fields["completionDate"] = ["after": "0"]
        case "unchanged": fields["description"] = ["before": NSNull(), "after": NSNull()]
        default: fields["futureField"] = ["before": NSNull(), "after": "x"]
        }
        changes[0]["fields"] = fields
        document["changes"] = changes
        let malformed = try copied(base, document: document, kind: "apply", id: base.id)
        #expect(throws: (any Error).self) { try TaskConsolidationHistoryCodec.decode(malformed) }
    }

    private func fixture(description: String? = nil, metadata: String? = nil,
                         changedDescription: String? = nil) throws -> TaskConsolidationPayload {
        let survivor = UUID(), candidate = UUID()
        let before = TaskConsolidationRawFields(description: description, metadataJSON: metadata,
            statusRawValue: "idea", lastStatusChangeDate: "0", completionDate: nil)
        let after = TaskConsolidationRawFields(description: changedDescription ?? description, metadataJSON: metadata,
            statusRawValue: "abandoned", lastStatusChangeDate: "3ff0000000000000", completionDate: "3ff0000000000000")
        return TaskConsolidationPayload(operationId: UUID(), kind: "apply", survivorTaskId: survivor,
            candidateTaskIds: [candidate], reason: "x",
            preservationJSON: "{\"\(candidate.uuidString)\":{\"retainedExplanation\":\"retained\"}}",
            changes: [.init(taskId: candidate, before: before, after: after)],
            appliedRevisions: [survivor.uuidString: "r1:" + String(repeating: "a", count: 64),
                               candidate.uuidString: "r1:" + String(repeating: "b", count: 64)],
            createdOccurrences: [], retainedOccurrences: [], requestKey: "review-fix", reviewId: UUID(),
            reviewRevision: "p1:" + String(repeating: "c", count: 64))
    }

    private func occurrence(source: UUID, target: UUID, kind: String) throws -> [String: Any] {
        let value = TaskLinkOccurrenceValue(physicalKey: Data(), id: UUID(), kind: kind,
            source: source, target: target, createdAt: Date(timeIntervalSinceReferenceDate: 0))
        return ["id": value.id.uuidString, "kind": kind, "source": source.uuidString,
            "target": target.uuidString, "createdAt": "0", "revision": try TaskLinkGraph.occurrenceRevision(value)]
    }

    private func inverse(_ document: [String: Any]) throws -> [String: Any] {
        var result = document
        result["kind"] = "undo"
        result["removedOccurrences"] = document["createdOccurrences"]
        result["createdOccurrences"] = [] as [[String: Any]]
        let changes = try #require(document["changes"] as? [[String: Any]])
        result["changes"] = changes.map { change in
            var inverse = change
            if let fields = change["fields"] as? [String: [String: Any]] {
                inverse["fields"] = fields.mapValues { ["before": $0["after"]!, "after": $0["before"]!] }
            } else {
                inverse["before"] = change["after"]
                inverse["after"] = change["before"]
            }
            return inverse
        }
        return result
    }

    private func object(_ json: String) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    }

    private func event(_ payload: TaskConsolidationPayload) throws -> TaskConsolidationEventValue {
        TaskConsolidationEventValue(physicalKey: Data(payload.operationId.uuidString.utf8), id: payload.operationId,
            operationId: payload.operationId, kind: "apply", createdAt: "0", originScopeId: "local-test",
            survivorTaskId: payload.survivorTaskId,
            candidateSlots: payload.candidateTaskIds.map(Optional.some) + [nil, nil, nil, nil],
            payloadJSON: try TaskConsolidationHistoryCodec.encode(payload))
    }

    private func copied(_ base: TaskConsolidationEventValue, document: [String: Any], kind: String,
                        id: UUID = UUID()) throws -> TaskConsolidationEventValue {
        let json = try #require(String(data: JSONSerialization.data(withJSONObject: document), encoding: .utf8))
        return TaskConsolidationEventValue(physicalKey: Data(id.uuidString.utf8), id: id, operationId: base.operationId,
            kind: kind, createdAt: base.createdAt, originScopeId: base.originScopeId,
            survivorTaskId: base.survivorTaskId, candidateSlots: base.candidateSlots, payloadJSON: json)
    }
}
