#if os(macOS)
import Foundation
import Testing
@testable import Transit

@MainActor struct MCPResultSourceTests {
    @Test func generatedJSONRetainsUnknownFieldsNullAndAllErrorPresenceVariants() throws {
        let text = " \n{\"source\":{\"presentation\":true},\"unknown\":18446744073709551616,\"explicit\":null}\t"
        for isError: Bool? in [nil, false, true] {
            let source = try MCPResultAdapter.source(text: text, isError: isError, origin: .generatedJSON,
                                                   evidence: .established)
            #expect(source.originalText == text)
            #expect(source.originalIsError == isError)
            #expect(source.kind == .json)
            #expect(source.evidence == .established)
            let document = try #require(source.document)
            #expect(document.originalUTF8 == Data(text.utf8))
            guard case .object(let members) = document.value else { Issue.record("Expected source object"); return }
            #expect(members.map(\.name) == ["source", "unknown", "explicit"])
            #expect(!members.contains { $0.name == "absent" })
            #expect(members.last?.value == .null)
        }
    }

    @Test(arguments: ["[]", "[false,1,null]", "null", "true", "9007199254740993", #""plain JSON string""#])
    func anyCompleteJSONValueIsAJSONSource(text: String) throws {
        let source = try MCPResultAdapter.source(text: text, isError: nil, origin: .generatedJSON,
                                               evidence: .established)
        #expect(source.kind == .json)
        #expect(source.document?.originalUTF8 == Data(text.utf8))
        #expect(source.originalText == text)
    }

    @Test func malformedGeneratedJSONFailsInsteadOfBecomingSuccessEvidence() {
        #expect(throws: MCPResultBoundaryError.invalidJSON) {
            try MCPResultAdapter.source(text: "{broken", isError: false, origin: .generatedJSON,
                                        evidence: .established)
        }
    }

    @Test func malformedRetainedJSONKeepsOriginalEvidenceAndDoesNotThrow() throws {
        for text in ["{broken", "", "{\"a\":1,\"a\":2}"] {
            for isError: Bool? in [nil, false, true] {
                let source = try MCPResultAdapter.source(text: text, isError: isError, origin: .retainedJSON,
                                                       evidence: .established)
                #expect(source.originalText == text)
                #expect(source.originalIsError == isError)
                #expect(source.kind == .unreadable)
                #expect(source.evidence == .unestablished)
                #expect(source.document == nil)
            }
        }
    }

    @Test func parseableUnsupportedRetainedOutcomeKeepsItsWholePayload() throws {
        let text = #"{"contractVersion":999,"outcome":"future","accepted":null,"extra":1e999}"#
        let source = try MCPResultAdapter.source(text: text, isError: false, origin: .retainedJSON,
                                               evidence: .unestablished)
        #expect(source.kind == .json)
        #expect(source.evidence == .unestablished)
        #expect(source.originalIsError == false)
        #expect(source.originalText == text)
        #expect(source.document?.originalUTF8 == Data(text.utf8))
    }

    @Test func declaredPlainErrorNeverGuessesJSONOrUnreadableOrigin() throws {
        for text in ["", "null", "{broken", "Storage unavailable\nTry again"] {
            let source = try MCPResultAdapter.source(text: text, isError: true, origin: .plainText,
                                                   evidence: .established)
            #expect(source.originalText == text)
            #expect(source.originalIsError == true)
            #expect(source.kind == .text)
            #expect(source.evidence == .established)
            #expect(source.document == nil)
        }
    }

    @Test func retainedOriginDoesNotSwallowWorkerCancellationAsUnreadableEvidence() {
        #expect(throws: MCPJSONCheckpointFailure.cancelled) {
            try MCPResultAdapter.source(text: "{\"a\":1}", isError: false, origin: .retainedJSON,
                                        evidence: .established) { throw MCPJSONCheckpointFailure.cancelled }
        }
    }

    @Test func generatedDepth33ThrowsDistinctResourceLimit() {
        let text = String(repeating: "[", count: 33) + "null" + String(repeating: "]", count: 33)
        #expect(throws: MCPResultBoundaryError.resourceLimit) {
            try MCPResultAdapter.source(text: text, isError: false, origin: .generatedJSON,
                                        evidence: .established)
        }
    }

    @Test func retainedDepth33PreservesRawEvidenceAndAllErrorPresenceVariants() throws {
        let text = " \n" + String(repeating: "[", count: 33) + "null" + String(repeating: "]", count: 33) + "\t"
        for isError: Bool? in [nil, false, true] {
            let source = try MCPResultAdapter.source(text: text, isError: isError, origin: .retainedJSON,
                                                   evidence: .established)
            #expect(source.originalText == text)
            #expect(source.originalIsError == isError)
            #expect(source.kind == .unreadable)
            #expect(source.evidence == .unestablished)
            #expect(source.document == nil)
        }
    }

    @Test func retainedDepth33StillPropagatesOriginalWorkerCancellation() {
        let text = String(repeating: "[", count: 33) + "null" + String(repeating: "]", count: 33)
        #expect(throws: MCPJSONCheckpointFailure.cancelled) {
            try MCPResultAdapter.source(text: text, isError: true, origin: .retainedJSON,
                                        evidence: .established) { throw MCPJSONCheckpointFailure.cancelled }
        }
    }
}
#endif
