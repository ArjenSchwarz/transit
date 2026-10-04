#if os(macOS)
import Foundation
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct MCPReadProviderEvidenceTests {
    @Test(arguments: [false, true])
    func providerSidecarPreservesWireAndPublicationAttachment(declared: Bool) throws {
        let text = "Saved read capture service is unavailable"
        let evidence = declared ? MCPResultProviderEvidence(origin: .plainText, evidence: .established) : nil
        let original = try MCPPreparedToolRead(text: text, isError: true)
        let annotated = try MCPPreparedToolRead(text: text, isError: true, providerEvidence: evidence)
        let attached = annotated.attaching([])
        #expect(attached.encodedToolResult == original.encodedToolResult)
        #expect(attached.result.content.first?.text == text && attached.result.isError == true)
        #expect((attached.result.providerEvidence != nil) == declared)
        let decoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(attached.result))
        let wire = try #require(decoded as? [String: Any])
        #expect(wire["providerEvidence"] == nil && wire["origin"] == nil)
    }

    @Test func explicitPlainTextEvidenceOverridesGeneratedJSONAdapterDefault() throws {
        let text = "Saved read storage failed"
        let tool = try MCPPreparedToolRead(text: text, isError: true,
            providerEvidence: MCPResultProviderEvidence(origin: .plainText, evidence: .established))
        let context = MCPResultContext(tool: "get_projects", semanticFailure: nil,
                                       mutationRecovery: nil, entityPositions: [])
        let outcome = try MCPResultProviderAdapters.outcome(result: tool.result, context: context,
                                                            origin: .generatedJSON)
        #expect(outcome.source.kind == .text && outcome.source.evidence == .established)
        #expect(outcome.source.originalText == text && outcome.source.originalIsError == true)
        #expect(outcome.source.document == nil)
    }
}
#endif
