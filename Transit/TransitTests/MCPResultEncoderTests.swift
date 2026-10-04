#if os(macOS)
import Foundation
import Testing
@testable import Transit

@MainActor
struct MCPResultEncoderTests {
    private typealias Fixture = MCPResultEncoderFixtures

    @Test func completeResponsesPreserveSourceTextAndOptionalErrorPresence() throws {
        let values = ["null", "true", "1E-9999", "\"東京\\nquote\\\"\"", "[false,null,9007199254740993]",
                      " {\"source\":null,\"presentation\":false,\"contractVersion\":99} \n"]
        let errors: [Bool?] = [nil, false, true]
        for value in values {
            for error in errors {
                let source = try Fixture.source(value, isError: error)
                let presentation = try MCPResultAdapter.present(source, context: Fixture.context())
                let bytes = try MCPResultEncoder.encode(source: source, presentation: presentation,
                                                        id: .string("new-\"\\\n🛰️"), metadata: nil)
                let result = try Fixture.result(bytes, id: .string("new-\"\\\n🛰️"))
                #expect(try Fixture.originalText(result) == value)
                #expect(Fixture.field("isError", in: result) == error.map(MCPJSONValue.boolean))
                #expect(Fixture.field("_meta", in: result) == nil)
                let structured = try Fixture.structured(result)
                let retained = Fixture.field("source", in: structured)
                #expect(Fixture.field("kind", in: retained) == .string("json"))
                #expect(Fixture.field("payload", in: retained) == source.document?.value)
                #expect(Fixture.field("evidence", in: Fixture.field("presentation", in: structured)) != nil)
            }
        }
    }

    @Test func plainAndUnreadableSourcesKeepRawEvidenceWithoutInventedPayload() throws {
        for origin: MCPResultOrigin in [.plainText, .retainedJSON] {
            let raw = "unreadable \"\\\n\u{0000} 東京"
            let source = try Fixture.source(raw, isError: false, origin: origin)
            let presentation = try MCPResultAdapter.present(source, context: Fixture.context())
            let result = try Fixture.result(MCPResultEncoder.encode(source: source, presentation: presentation,
                                                                    id: .integer(Int.min), metadata: nil),
                                            id: .integer(Int.min))
            #expect(try Fixture.originalText(result) == raw)
            #expect(Fixture.field("isError", in: result) == .boolean(false))
            let structured = try Fixture.structured(result)
            let retained = Fixture.field("source", in: structured)
            if case .plainText = origin {
                #expect(Fixture.field("kind", in: retained) == .string("text"))
                #expect(Fixture.field("payload", in: retained) == .string(raw))
            } else {
                #expect(Fixture.field("kind", in: retained) == .string("unreadable"))
                #expect(Fixture.field("payload", in: retained) == nil)
                #expect(Fixture.field("evidence", in: Fixture.field("presentation", in: structured))
                        == .string("unestablished"))
            }
        }
    }

    @Test func seededLosslessSourcesSurviveCompleteEnvelopeAndSafeEscaping() throws {
        var generator = MCPJSONFixtureGenerator(seed: 0x2383_0607)
        for index in 0..<64 {
            let fixture = generator.value(depth: 3)
            let source = try Fixture.source(fixture.json())
            let presentation = try MCPResultAdapter.present(source, context: Fixture.context())
            let bytes = try MCPResultEncoder.encode(source: source, presentation: presentation,
                                                    id: .integer(index), metadata: nil)
            let result = try Fixture.result(bytes, id: .integer(index))
            #expect(try Fixture.originalText(result) == fixture.json())
            let structured = try Fixture.structured(result)
            let payload = try #require(Fixture.field("payload", in: Fixture.field("source", in: structured)))
            #expect(fixture.matches(payload), "Seed2383_0607 index\(index) must preserve exact tokens and identities")
        }
    }

    @Test func metadataUsesOwnedLosslessObjectAndIndependentNamespace() throws {
        let raw = """
        {"com.example/capture":{"é":9007199254740993,"e\u{0301}":1E-9999,"missing":null},
         "com.example/policy":{"source":"collides","presentation":false}}
        """
        let document = try MCPJSONDocument.parse(raw)
        let metadata = try MCPResultMetadata.make(document: document)
        let source = try Fixture.source("{\"_meta\":null,\"source\":\"original\"}")
        let presentation = try MCPResultAdapter.present(source, context: Fixture.context())
        let result = try Fixture.result(MCPResultEncoder.encode(source: source, presentation: presentation,
                                                                id: .integer(Int.max), metadata: metadata),
                                        id: .integer(Int.max))
        let actual = try #require(Fixture.field("_meta", in: result))
        let fixture = MCPJSONFixtureValue.object([
            MCPJSONFixtureMember(name: "com.example/capture", value: .object([
                MCPJSONFixtureMember(name: "é", value: .number("9007199254740993")),
                MCPJSONFixtureMember(name: "e\u{0301}", value: .number("1E-9999")),
                MCPJSONFixtureMember(name: "missing", value: .null)
            ])),
            MCPJSONFixtureMember(name: "com.example/policy", value: .object([
                MCPJSONFixtureMember(name: "source", value: .string("collides")),
                MCPJSONFixtureMember(name: "presentation", value: .boolean(false))
            ]))
        ])
        #expect(fixture.matches(actual))
        #expect(metadata.document.originalUTF8 == document.originalUTF8)
        let payload = Fixture.field("payload", in: Fixture.field("source", in: try Fixture.structured(result)))
        #expect(payload == source.document?.value)
        #expect(Fixture.field("com.example/capture", in: payload) == nil)
    }

    @Test func metadataRejectsNonObjectAndInvalidNamespaceBeforeEncoding() throws {
        for raw in ["null", "[]", "3", "{\"bad key\":true}"] {
            let document = try MCPJSONDocument.parse(raw)
            #expect(throws: MCPResultBoundaryError.invalidJSON) {
                _ = try MCPResultMetadata.make(document: document)
            }
        }
    }

    @Test func frozenFragmentsAreIDIndependentAndReuseExactToolBytes() throws {
        let source = try Fixture.source("{\"revision\":\"r1:frozen\",\"record\":null}")
        let presentation = try MCPResultAdapter.present(source, context: Fixture.context())
        let metadata = try MCPResultMetadata.make(document: MCPJSONDocument.parse(
            "{\"com.example/capturedAt\":\"original\",\"com.example/expiry\":\"fixed\"}"))
        let fragment = try MCPResultEncoder.freeze(source: source, presentation: presentation, metadata: metadata)
        let frozen = try MCPJSONDocument.parse(fragment.encodedResult).value
        #expect(Fixture.field("id", in: frozen) == nil)
        #expect(Fixture.field("jsonrpc", in: frozen) == nil)
        for id: JSONRPCId in [.string("continuation-2"), .integer(3)] {
            let bytes = try MCPResultEncoder.encode(fragment: fragment, id: id)
            #expect(try Fixture.result(bytes, id: id) == frozen)
            #expect(bytes.range(of: fragment.encodedResult) != nil)
        }
    }

    @Test func rawPayloadAndFrozenMetadataPreserveExactOwnedFragments() throws {
        let raw = #"{"z": -0,"escaped":"\u0061\/","é":9007199254740993,"e\u0301":1E-9999,"first":null}"#
        let source = try Fixture.source(raw)
        let metadata = try MCPResultMetadata.make(document: MCPJSONDocument.parse(
            #"{"com.example/raw":{"z":-0,"é":1E-9999,"e\u0301":"\u0061\/"}}"#))
        let presentation = try MCPResultAdapter.present(source, context: Fixture.context())
        let fragment = try MCPResultEncoder.freeze(source: source, presentation: presentation, metadata: metadata)
        #expect(try Fixture.rawFragment(fragment.encodedResult, path: ["structuredContent", "source", "payload"])
                == source.document?.originalUTF8)
        #expect(try Fixture.rawFragment(fragment.encodedResult, path: ["_meta"]) == metadata.document.originalUTF8)
        let wire = try MCPResultEncoder.encode(fragment: fragment, id: .string("fresh"))
        #expect(try Fixture.rawFragment(wire, path: ["result"]) == fragment.encodedResult)
        #expect(try Fixture.rawFragment(wire, path: ["result", "structuredContent", "source", "payload"])
                == source.document?.originalUTF8)
    }

    @Test func depth32InputsRemainValidWhenEnvelopeAddsNesting() throws {
        let raw = String(repeating: "[", count: 32) + "-0" + String(repeating: "]", count: 32)
        let source = try Fixture.source(raw)
        let nested = String(repeating: "[", count: 31) + "1E-9999" + String(repeating: "]", count: 31)
        let metadata = try MCPResultMetadata.make(document: MCPJSONDocument.parse(
            "{\"com.example/deep\":\(nested)}"))
        let presentation = try MCPResultAdapter.present(source, context: Fixture.context())
        let bytes = try MCPResultEncoder.encode(source: source, presentation: presentation,
                                                id: .integer(32), metadata: metadata)
        // Full wire has greater depth than the separately validated source cap.
        #expect(try Fixture.rawFragment(bytes, path: ["result", "structuredContent", "source", "payload"])
                == source.document?.originalUTF8)
        #expect(try Fixture.rawFragment(bytes, path: ["result", "_meta"]) == metadata.document.originalUTF8)
        #expect(try Fixture.rawFragment(bytes, path: ["id"]) == Data("32".utf8))
        #expect(try Fixture.rawFragment(bytes, path: ["result", "resultType"]) == Data("\"complete\"".utf8))
    }

    @Test func encodingHonoursOriginalCheckpointAndNeverRetainsIt() throws {
        let source = try Fixture.source("[\"safe\"]")
        let presentation = try MCPResultAdapter.present(source, context: Fixture.context())
        let counter = MCPEncoderCheckpointCounter()
        let fragment = try MCPResultEncoder.freeze(source: source, presentation: presentation, metadata: nil,
                                                  checkpoint: { try counter.check() })
        let finished = counter.value()
        #expect(finished > 0)
        _ = try MCPResultEncoder.encode(fragment: fragment, id: .integer(1))
        #expect(counter.value() == finished)
        let cancelled = MCPEncoderCheckpointCounter(failAt: 1)
        #expect(throws: MCPResultEncoderFixtures.FixtureError.cancelled) {
            _ = try MCPResultEncoder.encode(source: source, presentation: presentation, id: .integer(1),
                                            metadata: nil, checkpoint: { try cancelled.check() })
        }
        #expect(cancelled.value() == 1)
        let metadataCancelled = MCPEncoderCheckpointCounter(failAt: 1)
        let document = try MCPJSONDocument.parse("{\"com.example/check\":true}")
        #expect(throws: MCPResultEncoderFixtures.FixtureError.cancelled) {
            _ = try MCPResultMetadata.make(document: document, checkpoint: { try metadataCancelled.check() })
        }
        #expect(metadataCancelled.value() == 1)
        let wrapCancelled = MCPEncoderCheckpointCounter(failAt: 1)
        #expect(throws: MCPResultEncoderFixtures.FixtureError.cancelled) {
            _ = try MCPResultEncoder.encode(fragment: fragment, id: .integer(2),
                                            checkpoint: { try wrapCancelled.check() })
        }
        #expect(wrapCancelled.value() == 1)
    }
}
#endif
