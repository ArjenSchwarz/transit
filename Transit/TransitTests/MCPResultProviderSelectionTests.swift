#if os(macOS)
import Foundation
import Testing
@testable import Transit

/// Synthetic providers exercise common response selection without a second write engine.
nonisolated struct MCPResultProviderSelectionTests: Sendable {
    private enum Fault: Error { case preparation, afterEffect, encoding }

    private nonisolated final class Counts: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [String: Int] = [:]
        func increment(_ name: String) { lock.lock(); defer { lock.unlock() }; values[name, default: 0] += 1 }
        func count(_ name: String) -> Int { lock.lock(); defer { lock.unlock() }; return values[name, default: 0] }
    }

    private func context(_ recovery: MCPMutationRecoveryContext? = nil) -> MCPResultContext {
        MCPResultContext(tool: "update_task", semanticFailure: nil,
                         mutationRecovery: recovery ?? .protectedWrite(.init(tool: "update_task",
                                                                            idempotencyKey: "original-key")),
                         entityPositions: [])
    }

    private func source(_ text: String, origin: MCPResultOrigin = .retainedJSON,
                        isError: Bool? = false) throws -> MCPResultSource {
        try MCPResultAdapter.source(text: text, isError: isError, origin: origin, evidence: .established)
    }

    private func fallback() throws -> MCPResultSource {
        try source(#"{"error":{"code":"OUTCOME_UNKNOWN"}}"#, origin: .generatedJSON, isError: true)
    }

    private func bytes(_ selection: MCPResultResponseSelection, reconciliation: Bool = false) throws -> Data {
        switch selection {
        case .normal(let data): #expect(!reconciliation); return data
        case .reconciliation(let data): #expect(reconciliation); return data
        case .suppressed: Issue.record("Expected complete response, got suppression"); throw Fault.encoding
        }
    }

    private func object(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func preparationFailureDispatchesNothing() async throws {
        let counts = Counts()
        do {
            _ = try await MCPResultProviderSelection.mutation(id: .string("prepare-rpc"), context: context(),
                metadata: nil, fallbackSource: fallback(), prepareFallback: { _, _, _, _ in throw Fault.preparation },
                dispatch: { counts.increment("dispatch"); throw Fault.afterEffect })
            Issue.record("Expected original preparation error")
        } catch Fault.preparation {}
        #expect(counts.count("dispatch") == 0)
    }

    @Test func postEffectEncodingFailureSelectsCompleteReadyBytesOnce() async throws {
        let counts = Counts()
        let fixed = context()
        let failed = try fallback()
        let id = JSONRPCId.string("new-rpc")
        let metadata = try MCPResultMetadata.make(document: MCPJSONDocument.parse(
            #"{"example.test/opaque":{"n":1E+9999,"missing":null}}"#))
        let ready = try MCPResultProviderSelection.prepare(id: id, source: failed, context: fixed, metadata: metadata)
        let selection = try await MCPResultProviderSelection.mutation(id: id, context: fixed,
            metadata: metadata, fallbackSource: failed,
            prepareFallback: { _, _, _, _ in counts.increment("prepare"); return ready },
            encodeOutcome: { _, _, _ in counts.increment("encode"); throw Fault.encoding },
            dispatch: {
                #expect(counts.count("prepare") == 1)
                counts.increment("effect")
                return MCPResultProviderOutcome(source: try self.source(#"{"accepted":true,"outcome":"committed"}"#),
                                                context: fixed)
            })
        #expect(try bytes(selection, reconciliation: true) == ready)
        #expect(counts.count("prepare") == 1)
        #expect(counts.count("effect") == 1)
        #expect(counts.count("encode") == 1)
        let wire = try #require(String(data: ready, encoding: .utf8))
        #expect(wire.contains(#""id":"new-rpc""#))
        #expect(wire.contains(#""idempotencyKey":"original-key""#))
        #expect(wire.contains(#""_meta":{"example.test/opaque":{"n":1E+9999,"missing":null}}"#))
    }

    @Test func providerFailureAfterEffectUsesPreparedReconciliation() async throws {
        let counts = Counts()
        let fixed = context()
        let failed = try fallback()
        let ready = try MCPResultProviderSelection.prepare(id: .integer(31), source: failed, context: fixed,
                                                           metadata: nil)
        let selected = try await MCPResultProviderSelection.mutation(id: .integer(31), context: fixed,
            metadata: nil, fallbackSource: failed, encodeOutcome: { _, _, _ in
                counts.increment("encode"); throw Fault.encoding
            }, dispatch: { counts.increment("effect"); throw Fault.afterEffect })
        #expect(try bytes(selected, reconciliation: true) == ready)
        #expect(counts.count("effect") == 1)
        #expect(counts.count("encode") == 0)
    }

    @Test func cancellationSuppressesDeliveryWithoutReinterpretingEffect() async throws {
        let counts = Counts()
        let fixed = context()
        let retained = try source(#"{"outcome":"committed","accepted":true,"retryAction":null}"#)
        let selected = try await MCPResultProviderSelection.mutation(id: .string("cancel-rpc"), context: fixed,
            metadata: nil, fallbackSource: fallback(), shouldDeliver: { counts.count("effect") == 0 }, dispatch: {
                counts.increment("effect")
                return MCPResultProviderOutcome(source: retained, context: fixed)
            })
        if case .suppressed = selected {} else { Issue.record("Cancellation must suppress delivery") }
        #expect(counts.count("effect") == 1)
        #expect(retained.originalText == #"{"outcome":"committed","accepted":true,"retryAction":null}"#)
        #expect(retained.originalIsError == false)
    }

    @Test func historicalSourceAndOpaqueMetadataKeepExactBytesWithNewRPCID() async throws {
        let fixed = context()
        let text = #" {"unknown":{"presentation":null,"contractVersion":false},"#
            + #""retryAction":null,"n":-0.00E+0,"accepted":true} "#
        let retained = try source(text, isError: nil)
        let metadata = try MCPResultMetadata.make(document: MCPJSONDocument.parse(
            #" {"example.test/opaque":{"a":null,"n":1E+9999}} "#))
        let outcome = MCPResultProviderOutcome(source: retained, context: fixed)
        let expected = try MCPResultProviderSelection.encode(outcome: outcome, id: .string("replay-new-id"),
                                                             metadata: metadata)
        let selection = try await MCPResultProviderSelection.mutation(id: .string("replay-new-id"), context: fixed,
            metadata: metadata, fallbackSource: fallback(), dispatch: { outcome })
        #expect(try bytes(selection) == expected)
        #expect(retained.originalText == text)
        #expect(retained.originalIsError == nil)
        let wire = try #require(String(data: expected, encoding: .utf8))
        #expect(wire.contains(#""payload":"# + text))
        #expect(wire.contains(#""_meta": {"example.test/opaque":{"a":null,"n":1E+9999}} "#))
    }

    @Test func forgedOutcomeRecoveryNeverReplacesOriginalIdentity() async throws {
        let fixed = context()
        let substitutions = [
            context(.protectedWrite(.init(tool: "update_task", idempotencyKey: "different-key"))),
            MCPResultContext(tool: "other_tool", semanticFailure: nil,
                             mutationRecovery: fixed.mutationRecovery, entityPositions: []),
            context(.unprotectedMaintenance(tool: "update_task"))
        ]
        for substituted in substitutions {
            let counts = Counts()
            let failed = try fallback()
            let ready = try MCPResultProviderSelection.prepare(id: .integer(42), source: failed, context: fixed,
                                                               metadata: nil)
            let selected = try await MCPResultProviderSelection.mutation(id: .integer(42), context: fixed,
                metadata: nil, fallbackSource: failed, encodeOutcome: { _, _, _ in
                    counts.increment("encode"); throw Fault.encoding
                }, dispatch: { MCPResultProviderOutcome(source: try self.source("null"), context: substituted) })
            #expect(try bytes(selected, reconciliation: true) == ready)
            #expect(counts.count("encode") == 0)
        }
    }

    @Test func originalTextJSONAndUnreadableEvidenceNeverBecomeInventedOutcomes() async throws {
        let fixed = context()
        for (text, origin, flag) in [
            ("Plain original error", MCPResultOrigin.plainText, true),
            (#"{"error":{"unknown":null},"accepted":false}"#, .retainedJSON, false),
            ("{unreadable retained original", .retainedJSON, true)
        ] {
            let retained = try source(text, origin: origin, isError: flag)
            let outcome = MCPResultProviderOutcome(source: retained, context: fixed)
            let expected = try MCPResultProviderSelection.encode(outcome: outcome, id: .integer(8), metadata: nil)
            let selected = try await MCPResultProviderSelection.mutation(id: .integer(8), context: fixed,
                metadata: nil, fallbackSource: fallback(), dispatch: { outcome })
            #expect(try bytes(selected) == expected)
            #expect(retained.originalText == text)
            #expect(retained.originalIsError == flag)
            if retained.kind == .unreadable { #expect(retained.evidence == .unestablished) }
        }
    }

    @Test func cancellationBeforeDispatchSuppressesWithoutCallingProvider() async throws {
        let counts = Counts()
        let selected = try await MCPResultProviderSelection.mutation(id: .integer(9), context: context(),
            metadata: nil, fallbackSource: fallback(), shouldDeliver: { false }, dispatch: {
                counts.increment("dispatch"); throw Fault.afterEffect
            })
        if case .suppressed = selected {} else { Issue.record("Expected suppressed pre-dispatch delivery") }
        #expect(counts.count("dispatch") == 0)
    }

    @Test func cancellationAfterEffectAndEncodingFailureStillSuppressesDelivery() async throws {
        let counts = Counts()
        let fixed = context()
        let selected = try await MCPResultProviderSelection.mutation(id: .integer(10), context: fixed,
            metadata: nil, fallbackSource: fallback(), encodeOutcome: { _, _, _ in
                counts.increment("cancel"); throw Fault.encoding
            }, shouldDeliver: { counts.count("cancel") == 0 }, dispatch: {
                counts.increment("effect")
                return MCPResultProviderOutcome(source: try self.source("null"), context: fixed)
            })
        if case .suppressed = selected {} else { Issue.record("Expected suppressed post-effect failure response") }
        #expect(counts.count("effect") == 1)
        #expect(counts.count("cancel") == 1)
    }

    @Test func batchFallbackOmitsUnboundedItemIDAndKeepsOrderedOriginalKeys() async throws {
        let taskID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let items = [
            MCPBatchRecoveryItem(index: 0, itemId: String(repeating: "huge", count: 100_000), operation: "update",
                                 originalKey: .init(tool: "update_task", idempotencyKey: "first-key"),
                                 targetTaskId: taskID),
            MCPBatchRecoveryItem(index: 1, itemId: nil, operation: "comment",
                                 originalKey: .init(tool: "add_comment", idempotencyKey: "second-key"),
                                 targetTaskId: nil)
        ]
        let fixed = MCPResultContext(tool: "mutate_tasks", semanticFailure: nil,
                                     mutationRecovery: .applicationBatch(items: items), entityPositions: [])
        let selected = try await MCPResultProviderSelection.mutation(id: .string("batch-id"), context: fixed,
            metadata: nil, fallbackSource: source(#"{"summary":"serialization_failed"}"#,
                                                 origin: .generatedJSON, isError: true),
            encodeOutcome: { _, _, _ in throw Fault.encoding }, dispatch: {
                MCPResultProviderOutcome(source: try self.source(#"{"items":[],"summary":"all_committed"}"#),
                                                context: fixed)
            })
        let response = try object(bytes(selected, reconciliation: true))
        let result = try #require(response["result"] as? [String: Any])
        let structured = try #require(result["structuredContent"] as? [String: Any])
        let presentation = try #require(structured["presentation"] as? [String: Any])
        let recovery = try #require(presentation["recovery"] as? [String: Any])
        let retained = try #require(recovery["items"] as? [[String: Any]])
        try #require(retained.count == 2)
        #expect(retained[0]["itemId"] == nil)
        #expect(retained[0]["idempotencyKey"] as? String == "first-key")
        #expect(retained[1]["idempotencyKey"] as? String == "second-key")
        #expect(retained[0]["targetTaskId"] as? String == taskID.uuidString)
        #expect(retained[0]["index"] as? Int == 0)
        #expect(retained[1]["index"] as? Int == 1)
    }

    @Test func maintenanceFallbackHasNoInventedProtectedKey() async throws {
        let fixed = MCPResultContext(tool: "reassign_duplicate_display_ids", semanticFailure: nil,
            mutationRecovery: .unprotectedMaintenance(tool: "reassign_duplicate_display_ids"), entityPositions: [])
        let selected = try await MCPResultProviderSelection.mutation(id: .string("maintenance-id"), context: fixed,
            metadata: nil, fallbackSource: fallback(), dispatch: { throw Fault.afterEffect })
        let wire = try #require(String(data: bytes(selected, reconciliation: true), encoding: .utf8))
        #expect(wire.contains(#""direction":"reconcile_maintenance""#))
        #expect(wire.contains(#""tool":"reassign_duplicate_display_ids""#))
        #expect(!wire.contains("idempotencyKey"))
    }
}
#endif
