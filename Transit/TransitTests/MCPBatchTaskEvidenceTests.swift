#if os(macOS)
import Foundation
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct MCPBatchTaskEvidenceTests {
    private typealias Fixture = MCPBatchTaskResultFixtures

    // Intentionally absent batch-local classifier is Task 3's RED boundary.
    @Test(arguments: ["1", "1.0", "1e0"], [nil, false] as [Bool?])
    func equivalentNumericVersionAndOriginalOptionalFlagCanAdvance(version: String, isError: Bool?) throws {
        let text = Fixture.committed(version: version, extra:
            #", "unknown":{"n":1E+9999,"adjacent":9007199254740993,"explicitNull":null}"#)
        let source = try Fixture.source(text, isError: isError)
        let result = MCPBatchTaskEvidence.assess(source: source, operation: "update_task",
            originalKey: Fixture.key, taskID: Fixture.taskID, requiresStatusComment: false)
        #expect(result.canAdvance)
        #expect(result.source.originalText == text && result.source.originalIsError == isError)
        #expect(result.source.document?.originalUTF8 == Data(text.utf8))
        #expect(result.source.document?.value == source.document?.value)
        // January expiry is historical: current classification must not deny
        // the established saved commit or remint a revision/expiry.
    }

    @Test(arguments: ["2", "true", #""1""#, "null"])
    func unsupportedOrWrongVersionStopsWithoutRewriting(version: String) throws {
        let source = try Fixture.source(Fixture.committed(version: version))
        let result = MCPBatchTaskEvidence.assess(source: source, operation: "update_task",
            originalKey: Fixture.key, taskID: Fixture.taskID, requiresStatusComment: false)
        #expect(!result.canAdvance)
        #expect(result.source.originalText == source.originalText)
        #expect(result.source.document?.value == source.document?.value)
    }

    @Test(arguments: ["acceptedFalse", "acceptedNumber", "acceptedString", "acceptedNull", "acceptedMissing",
                      "versionMissing", "entityMismatch", "recordMismatch", "recordMissing", "revision",
                      "completedAt", "expiry", "wrongTool", "wrongKey", "error"])
    func missingMalformedOrContradictoryCommitEvidenceStops(caseName: String) throws {
        let replacements: [String: (String, String)] = [
            "acceptedFalse": (#""accepted":true"#, #""accepted":false"#),
            "acceptedNumber": (#""accepted":true"#, #""accepted":1"#),
            "acceptedString": (#""accepted":true"#, #""accepted":"true""#),
            "acceptedNull": (#""accepted":true"#, #""accepted":null"#),
            "acceptedMissing": (#","accepted":true"#, ""),
            "versionMissing": (#""contractVersion":1,"#, ""),
            "entityMismatch": ("\"entityId\":\"\(Fixture.taskID.uuidString)\"", "\"entityId\":\"bad\""),
            "recordMismatch": ("\"taskId\":\"\(Fixture.taskID.uuidString)\"",
                               "\"taskId\":\"\(Fixture.commentID.uuidString)\""),
            "recordMissing": (",\"record\":\(Fixture.taskRecord)", ""),
            "revision": (Fixture.revision, "r1:bad"),
            "completedAt": (#""completedAt":"2026-01-01T00:00:00.000Z""#,
                            #""completedAt":"2026-01-01T00:00:00Z""#),
            "expiry": ("2026-01-08T00:00:00.000Z", "2025-12-31T00:00:00.000Z"),
            "wrongTool": (#""tool":"update_task""#, #""tool":"add_comment""#),
            "wrongKey": ("\"idempotencyKey\":\"\(Fixture.key)\"", #""idempotencyKey":"other""#),
            "error": (#""outcome":"committed""#,
                      #""outcome":"committed","error":{"code":"INTERNAL_ERROR","message":"contradiction"}"#)
        ]
        let replacement = try #require(replacements[caseName])
        let original = Fixture.committed()
        let text = original.replacingOccurrences(of: replacement.0, with: replacement.1)
        #expect(text != original)
        let source = try Fixture.source(text)
        let result = MCPBatchTaskEvidence.assess(source: source, operation: "update_task",
            originalKey: Fixture.key, taskID: Fixture.taskID, requiresStatusComment: false)
        #expect(!result.canAdvance)
        #expect(result.source.originalText == text)
    }

    @Test(arguments: ["update_task", "update_task_status", "add_comment"])
    func operationSpecificSavedIdentityCanAdvance(operation: String) throws {
        let source = try Fixture.source(Fixture.committed(operation: operation))
        let result = MCPBatchTaskEvidence.assess(source: source, operation: operation,
            originalKey: Fixture.key, taskID: Fixture.taskID, requiresStatusComment: false)
        #expect(result.canAdvance)
    }

    @Test(arguments: ["valid", "missing", "null", "wrongTask", "badRevision", "badID"])
    func requestedStatusReasonRequiresItsOwnSavedComment(kind: String) throws {
        var comment = Fixture.commentRecord
        if kind == "wrongTask" {
            comment = comment.replacingOccurrences(of: Fixture.taskID.uuidString, with: Fixture.commentID.uuidString)
        }
        if kind == "badRevision" { comment = comment.replacingOccurrences(of: Fixture.revision, with: "bad") }
        if kind == "badID" { comment = comment.replacingOccurrences(of: Fixture.commentID.uuidString, with: "bad") }
        let extra = kind == "missing" ? "" : ",\"comment\":\(kind == "null" ? "null" : comment)"
        let source = try Fixture.source(Fixture.committed(operation: "update_task_status", extra: extra))
        let result = MCPBatchTaskEvidence.assess(source: source, operation: "update_task_status",
            originalKey: Fixture.key, taskID: Fixture.taskID, requiresStatusComment: true)
        #expect(result.canAdvance == (kind == "valid"))
        #expect(result.source.document?.value == source.document?.value)
    }

    @Test(arguments: ["rejected", "in_progress", "uncertain", "unknown"])
    func unsuccessfulOriginalOutcomeAndRetryDirectionRemainSourceOwned(outcome: String) throws {
        let text = """
        {"contractVersion":1,"outcome":"\(outcome)","accepted":null,"retryAction":"retry_same_request",\
        "error":{"code":"INTERNAL_ERROR","message":"saved"},"unknown":null}
        """
        let source = try Fixture.source(text, isError: true)
        let result = MCPBatchTaskEvidence.assess(source: source, operation: "update_task",
            originalKey: Fixture.key, taskID: Fixture.taskID, requiresStatusComment: false)
        #expect(!result.canAdvance)
        #expect(result.source.originalText == text && result.source.originalIsError == true)
        #expect(Fixture.field("retryAction", in: result.source.document?.value) == .string("retry_same_request"))
        #expect(Fixture.field("unknown", in: result.source.document?.value) == .null)
        #expect(Fixture.field("missing", in: result.source.document?.value) == nil)
    }

    @Test(arguments: ["malformed", "depth33", "unestablished", "errorFlag"])
    func unreadableOrUnestablishedEvidenceCannotAdvance(kind: String) throws {
        let text = kind == "malformed" ? "{broken" : kind == "depth33" ? Fixture.nestedArrays(33) : Fixture.committed()
        let source = try Fixture.source(text, isError: kind == "errorFlag" ? true : nil,
                                        evidence: kind == "unestablished" ? .unestablished : .established)
        let result = MCPBatchTaskEvidence.assess(source: source, operation: "update_task",
            originalKey: Fixture.key, taskID: Fixture.taskID, requiresStatusComment: false)
        #expect(!result.canAdvance)
        #expect(result.source.originalText == text && result.source.originalIsError == source.originalIsError)
        if kind == "malformed" || kind == "depth33" {
            #expect(result.source.kind == .unreadable && result.source.evidence == .unestablished)
            #expect(result.source.document == nil)
        }
    }
}
#endif
