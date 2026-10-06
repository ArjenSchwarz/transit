import Foundation
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct TaskConsolidationCodecTests {
    @Test func exactRawFieldsAndDateBitsRoundTrip() throws {
        let value = try fixture()
        let event = try event(value)
        #expect(try TaskConsolidationHistoryCodec.decode(event) == value)
        let fields = try #require(value.changes.first?.fields)
        #expect(fields["metadataJSON"]?.before == "{ \"source\" : \"café\" }")
        let closure = try #require(value.changes.first { $0.taskId == value.candidateTaskIds[0] })
        let date = try TaskConsolidationRawFields.date(try #require(closure.fields["lastStatusChangeDate"]?.before))
        #expect(date.timeIntervalSinceReferenceDate.bitPattern == Double(123456.00000000001).bitPattern)
        #expect(throws: (any Error).self) { try TaskConsolidationRawFields.date("7ff0000000000000") }
    }

    @Test func payloadLimitCountsEncodedUTF8Exactly() throws {
        var value = try fixture()
        let baseline = try TaskConsolidationHistoryCodec.encode(value).utf8.count
        value = try fixture(reason: String(repeating: "a", count: 256 * 1_024 - baseline + 1))
        #expect(try TaskConsolidationHistoryCodec.encode(value).utf8.count == 256 * 1_024)
        #expect(try TaskConsolidationHistoryCodec.encode(fixture(reason: String(repeating: "a",
            count: 256 * 1_024 - baseline))).utf8.count == 256 * 1_024 - 1)
        #expect(throws: (any Error).self) {
            try TaskConsolidationHistoryCodec.encode(fixture(reason: String(repeating: "a",
                count: 256 * 1_024 - baseline + 2)))
        }
        #expect(throws: (any Error).self) {
            try TaskConsolidationHistoryCodec.encode(fixture(reason: String(repeating: "é", count: 256 * 1_024)))
        }
    }

    @Test func physicalMultiplicityAndCorruptionFailClosed() throws {
        let payload = try fixture()
        let original = try event(payload)
        #expect(try TaskConsolidationHistoryCodec.history([original], operationId: payload.operationId).reversal == nil)
        #expect(throws: (any Error).self) {
            try TaskConsolidationHistoryCodec.history([original, original], operationId: payload.operationId)
        }
        #expect(throws: (any Error).self) {
            try TaskConsolidationHistoryCodec.history([], operationId: payload.operationId)
        }
        var unsupported = payload
        unsupported.version = 2
        #expect(throws: (any Error).self) { try TaskConsolidationHistoryCodec.encode(unsupported) }
        let malformed = TaskConsolidationEventValue(physicalKey: Data([1]), id: original.id,
            operationId: original.operationId, kind: original.kind, createdAt: original.createdAt,
            originScopeId: original.originScopeId, survivorTaskId: UUID(), candidateSlots: original.candidateSlots,
            payloadJSON: original.payloadJSON)
        #expect(throws: (any Error).self) { try TaskConsolidationHistoryCodec.decode(malformed) }
    }

    @Test func operationTokenIsOrderIndependentButIncludesMultiplicityAndRawBytes() throws {
        let original = try event(fixture())
        let other = try event(fixture())
        #expect(try TaskConsolidationHistoryCodec.revision([original, other])
            == TaskConsolidationHistoryCodec.revision([other, original]))
        #expect(try TaskConsolidationHistoryCodec.revision([original])
            != TaskConsolidationHistoryCodec.revision([original, original]))
        #expect(try TaskConsolidationHistoryCodec.revision([original]).hasPrefix("o1:"))
    }

    @Test(arguments: ["review", "revisions", "accounting", "version", "occurrence"])
    func importedMalformedEvidenceIsUnavailable(fault: String) throws {
        let original = try event(fixture())
        var document = try #require(JSONSerialization.jsonObject(with: Data(original.payloadJSON.utf8))
            as? [String: Any])
        switch fault {
        case "review": document["reviewRevision"] = "p1:abc"
        case "revisions": document["appliedRevisions"] = [:] as [String: String]
        case "accounting": document["preservationJSON"] = "{}"
        case "version": document["version"] = 99
        default:
            document["createdOccurrences"] = [["id": UUID().uuidString, "kind": "future-kind",
                "source": original.survivorTaskId.uuidString, "target": UUID().uuidString,
                "createdAt": "0", "revision": "l1:" + String(repeating: "a", count: 64)]]
        }
        let bytes = try JSONSerialization.data(withJSONObject: document)
        let json = try #require(String(data: bytes, encoding: .utf8))
        let corrupt = copied(original, payload: json)
        #expect(throws: (any Error).self) { try TaskConsolidationHistoryCodec.decode(corrupt) }
    }

    @Test(arguments: ["json", "missing-field", "nested-accounting", "nested-metadata"])
    func importedDecodeFailuresUseHistoryMalformed(fault: String) throws {
        let original = try event(fixture())
        var document = try #require(JSONSerialization.jsonObject(with: Data(original.payloadJSON.utf8))
            as? [String: Any])
        switch fault {
        case "missing-field": document.removeValue(forKey: "changes")
        case "nested-accounting": document["preservationJSON"] = "{"
        case "nested-metadata":
            var changes = try #require(document["changes"] as? [[String: Any]])
            var fields = try #require(changes[0]["fields"] as? [String: Any])
            fields["metadataJSON"] = ["before": "{", "after": "{}"]
            changes[0]["fields"] = fields
            document["changes"] = changes
        default: break
        }
        let json = fault == "json" ? "{" : try #require(String(data:
            JSONSerialization.data(withJSONObject: document), encoding: .utf8))
        #expect(throws: TaskConsolidationHistoryError.malformed) {
            try TaskConsolidationHistoryCodec.decode(copied(original, payload: json))
        }
    }

    @Test func multipleReversalsAreAmbiguousAndOldHistoryDoesNotExpire() throws {
        let original = try event(fixture())
        var document = try #require(JSONSerialization.jsonObject(with: Data(original.payloadJSON.utf8))
            as? [String: Any])
        document["kind"] = "undo"
        let originalPayload = try TaskConsolidationHistoryCodec.decode(original)
        document["changes"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(
            originalPayload.changes.map(\.inverse)))
        document["removedOccurrences"] = document["createdOccurrences"]
        document["createdOccurrences"] = [] as [[String: Any]]
        let bytes = try JSONSerialization.data(withJSONObject: document)
        let json = try #require(String(data: bytes, encoding: .utf8))
        let reversal = copied(original, id: UUID(), kind: "undo", payload: json)
        let another = copied(original, id: UUID(), kind: "undo", payload: json)
        let old = copied(original, date: try TaskConsolidationRawFields.exactDate(
            Date(timeIntervalSince1970: 1_000_000)))
        #expect(try TaskConsolidationHistoryCodec.history([old, reversal], operationId: original.operationId)
            .reversal?.kind == "undo")
        #expect(throws: (any Error).self) {
            try TaskConsolidationHistoryCodec.history([old, reversal, another], operationId: original.operationId)
        }
    }

    @Test func transientPhysicalIdentityDoesNotRemintOperationContentToken() throws {
        let original = try event(fixture())
        let reopened = copied(original, physicalKey: Data("permanent-store-identity".utf8))
        #expect(try TaskConsolidationHistoryCodec.revision([original])
            == TaskConsolidationHistoryCodec.revision([reopened]))
    }

    private func copied(_ original: TaskConsolidationEventValue, id: UUID? = nil, kind: String? = nil,
                        payload: String? = nil, date: String? = nil, physicalKey: Data? = nil)
        -> TaskConsolidationEventValue {
        TaskConsolidationEventValue(physicalKey: physicalKey ?? Data((id ?? original.id).uuidString.utf8),
            id: id ?? original.id, operationId: original.operationId, kind: kind ?? original.kind,
            createdAt: date ?? original.createdAt, originScopeId: original.originScopeId,
            survivorTaskId: original.survivorTaskId, candidateSlots: original.candidateSlots,
            payloadJSON: payload ?? original.payloadJSON)
    }

    private func fixture(reason: String = "x") throws -> TaskConsolidationPayload {
        let survivor = UUID(), candidate = UUID()
        let before = TaskConsolidationRawFields(description: nil, metadataJSON: "{ \"source\" : \"café\" }",
            statusRawValue: "idea", lastStatusChangeDate:
                try TaskConsolidationRawFields.exactDate(Date(timeIntervalSinceReferenceDate: 123456.00000000001)),
            completionDate: nil)
        let after = TaskConsolidationRawFields(description: before.description, metadataJSON: before.metadataJSON,
            statusRawValue: "abandoned", lastStatusChangeDate: "0", completionDate: "0")
        let edited = TaskConsolidationRawFields(description: before.description, metadataJSON: "{\"source\":\"after\"}",
            statusRawValue: before.statusRawValue, lastStatusChangeDate: before.lastStatusChangeDate,
            completionDate: before.completionDate)
        return TaskConsolidationPayload(operationId: UUID(), kind: "apply", survivorTaskId: survivor,
            candidateTaskIds: [candidate], reason: reason,
            preservationJSON: "{\"\(candidate.uuidString)\":{\"retainedExplanation\":\"original retained\"}}",
            changes: [TaskConsolidationTaskChange(taskId: survivor, before: before, after: edited),
                      TaskConsolidationTaskChange(taskId: candidate, before: before, after: after)],
            appliedRevisions: [survivor.uuidString: "r1:" + String(repeating: "a", count: 64),
                               candidate.uuidString: "r1:" + String(repeating: "b", count: 64)],
            createdOccurrences: [], retainedOccurrences: [], requestKey: "test", reviewId: UUID(),
            reviewRevision: "p1:" + String(repeating: "c", count: 64))
    }

    private func event(_ payload: TaskConsolidationPayload) throws -> TaskConsolidationEventValue {
        TaskConsolidationEventValue(physicalKey: Data(payload.operationId.uuidString.utf8), id: payload.operationId,
            operationId: payload.operationId, kind: payload.kind, createdAt: "0", originScopeId: "local-test",
            survivorTaskId: payload.survivorTaskId,
            candidateSlots: payload.candidateTaskIds.map(Optional.some) + Array(repeating: nil,
                count: 5 - payload.candidateTaskIds.count),
            payloadJSON: try TaskConsolidationHistoryCodec.encode(payload))
    }
}
