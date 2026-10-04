#if os(macOS)
import Foundation
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct MCPBatchTaskEvidenceBoundaryTests {
    private typealias Fixture = MCPBatchTaskResultFixtures

    @Test(arguments: ["1.0000000000000000000000001", "0.9999999999999999999999999", "-1",
                      "1e999999999999999999999", "100e-2", "0.0100e2", "10.0e-1", "1E+0000"])
    func exactDecimalVersionDoesNotRoundAdjacentValues(version: String) throws {
        let source = try Fixture.source(Fixture.committed(version: version))
        let assessment = MCPBatchTaskEvidence.assess(source: source, operation: "update_task",
            originalKey: Fixture.key, taskID: Fixture.taskID, requiresStatusComment: false)
        let equivalent = ["100e-2", "0.0100e2", "10.0e-1", "1E+0000"].contains(version)
        #expect(assessment.canAdvance == equivalent)
        #expect(assessment.source.originalText == source.originalText)
        #expect(assessment.source.document?.originalUTF8 == source.document?.originalUTF8)
    }

    @Test(arguments: ["2026-02-30T00:00:00.000Z", "2026-01-01T24:00:00.000Z",
                      "2026-01-01T00:00:00.000+00:00", "2026-01-01T00:00:00.0000Z"])
    func noncanonicalOrNormalizedInvalidDateCannotEstablishCommit(timestamp: String) throws {
        let original = Fixture.committed()
        let text = original.replacingOccurrences(of: #""completedAt":"2026-01-01T00:00:00.000Z""#,
                                                with: "\"completedAt\":\"\(timestamp)\"")
        #expect(text != original)
        let source = try Fixture.source(text)
        let assessment = MCPBatchTaskEvidence.assess(source: source, operation: "update_task",
            originalKey: Fixture.key, taskID: Fixture.taskID, requiresStatusComment: false)
        #expect(!assessment.canAdvance)
        #expect(assessment.source.originalText == text)
    }

    @Test(arguments: ["unicode", "case"])
    func opaqueKeyIdentityUsesExactScalarsRatherThanCanonicalEquality(kind: String) throws {
        let savedKey = kind == "unicode" ? "saved.\u{00E9}" : "batch.original"
        let requestedKey = kind == "unicode" ? "saved.e\u{0301}" : "Batch.Original"
        let text = Fixture.committed().replacingOccurrences(of: Fixture.key, with: savedKey)
        let source = try Fixture.source(text)
        let assessment = MCPBatchTaskEvidence.assess(source: source, operation: "update_task",
            originalKey: requestedKey, taskID: Fixture.taskID, requiresStatusComment: false)
        #expect(!assessment.canAdvance)
        #expect(assessment.source.originalText == text)
    }

    @Test(arguments: ["error", "retry", "both", "direction"])
    func committedOptionalNullsPreserveEvidenceWithoutInventingFailure(kind: String) throws {
        let extra: String
        switch kind {
        case "error": extra = ",\"error\":null"
        case "retry": extra = ",\"retryAction\":null"
        case "both": extra = ",\"error\":null,\"retryAction\":null"
        default: extra = ",\"retryAction\":\"reconcile\""
        }
        let text = Fixture.committed(extra: extra)
        let source = try Fixture.source(text)
        let assessment = MCPBatchTaskEvidence.assess(source: source, operation: "update_task",
            originalKey: Fixture.key, taskID: Fixture.taskID, requiresStatusComment: false)
        #expect(assessment.canAdvance == (kind != "direction"))
        #expect(assessment.source.originalText == text)
        #expect(assessment.source.document?.value == source.document?.value)
        if kind == "error" || kind == "both" {
            #expect(Fixture.field("error", in: assessment.source.document?.value) == .null)
        }
        if kind == "retry" || kind == "both" {
            #expect(Fixture.field("retryAction", in: assessment.source.document?.value) == .null)
        }
    }

    @Test(arguments: ["rejected", "in_progress", "uncertain", "missingError", "wrongError", "missingCode",
                      "wrongMessage", "missingRetry", "wrongRetry", "acceptedConflict", "unknownOutcome"])
    func supportedFailuresRemainDistinctFromUnavailableEvidence(kind: String) throws {
        let outcome = ["rejected", "in_progress", "uncertain"].contains(kind) ? kind : "uncertain"
        let code = outcome == "in_progress" ? "OPERATION_IN_PROGRESS" : "OUTCOME_UNCERTAIN"
        let retry = outcome == "uncertain" ? "reconcile" : "retry_same_request"
        let error = "\"error\":{\"code\":\"\(code)\",\"message\":\"saved\"}"
        let retryField = "\"retryAction\":\"\(retry)\""
        var text = """
        {"contractVersion":1,"tool":"update_task","idempotencyKey":"\(Fixture.key)",
        "outcome":"\(outcome)","accepted":true,\(error),\(retryField),"unknown":null}
        """
        let baseline = text
        switch kind {
        case "missingError": text = text.replacingOccurrences(of: error + ",", with: "")
        case "wrongError": text = text.replacingOccurrences(of: error, with: "\"error\":null")
        case "missingCode": text = text.replacingOccurrences(of: "\"code\":\"\(code)\",", with: "")
        case "wrongMessage":
            text = text.replacingOccurrences(of: "\"message\":\"saved\"", with: "\"message\":false")
        case "missingRetry": text = text.replacingOccurrences(of: retryField + ",", with: "")
        case "wrongRetry":
            text = text.replacingOccurrences(of: retryField, with: "\"retryAction\":\"new_request_new_key\"")
        case "acceptedConflict": text = text.replacingOccurrences(of: "\"accepted\":true", with: "\"accepted\":false")
        case "unknownOutcome":
            text = text.replacingOccurrences(of: "\"outcome\":\"uncertain\"", with: "\"outcome\":\"unknown\"")
        default: break
        }
        let supported = ["rejected", "in_progress", "uncertain"].contains(kind)
        #expect(supported || text != baseline)
        let source = try Fixture.source(text, isError: true)
        let assessment = MCPBatchTaskEvidence.assess(source: source, operation: "update_task",
            originalKey: Fixture.key, taskID: Fixture.taskID, requiresStatusComment: false)
        #expect(assessment.kind == (supported ? .itemResult : .unavailable))
        #expect(!assessment.canAdvance && assessment.source.originalText == text)
        #expect(assessment.source.originalIsError == true)
        #expect(assessment.source.document?.value == source.document?.value)
    }

}
#endif
