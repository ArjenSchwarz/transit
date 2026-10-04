#if os(macOS)
import Foundation
import Testing
@testable import Transit

/// Value-side task16 RED. Actual retained-store publication needs the owner bindings.
@MainActor @Suite(.serialized)
struct MCPModernReadPagePreparationTests {
    @Test func everyPrivatePageSharesFrozenCaptureOwnerAndExactText() async {
        await withOperation { operation in
            let texts = [#"{"future":-0.00E+0,"flag":false,"nullable":null}"#, "[]", "null"]
            let reads = try texts.map { try MCPPreparedToolRead(text: $0, metadata: .capture(Self.capture)) }
            let pages = try MCPModernProviderBinding.prepareReadPages(reads, tool: "query_tasks", operation: operation)
            try #require(pages.count == reads.count)
            let first = try #require(pages.first)
            let metadata = try #require(first.metadataOwner)
            for (index, page) in pages.enumerated() {
                #expect(page.source.originalText.utf8.elementsEqual(texts[index].utf8))
                #expect(page.source.document?.originalUTF8 == Data(texts[index].utf8))
                #expect(page.metadataOwner === metadata)
                #expect(page.fragment.encodedResult.range(of: try #require(reads[index].frozenMetadataBytes)) != nil)
            }
        }
    }

    @Test func malformedGeneratedLaterPageFailsWholePreparation() async {
        await withOperation { operation in
            let reads = try ["[]", "{broken"].map { try MCPPreparedToolRead(text: $0) }
            #expect(throws: MCPResultBoundaryError.invalidJSON) {
                try MCPModernProviderBinding.prepareReadPages(reads, tool: "query_tasks", operation: operation)
            }
        }
    }

    @Test func generatedFailureKeepsFlagCategoryAndOriginalMetadata() async {
        await withOperation { operation in
            let read = try MCPPreparedToolRead(text: #"{"error":{"code":"READ_BUSY","message":"busy"}}"#,
                isError: true, metadata: .failure(ReadFailureMetadata(requestId: "original-request",
                    category: .busy, read: ReadExecutionMetadata(policy: .cached,
                        refreshOutcome: .notRequested, budgetMs: 5_000))))
            let pages = try MCPModernProviderBinding.prepareReadPages([read], tool: "query_tasks", operation: operation)
            let page = try #require(pages.first)
            #expect(page.source.originalIsError == true)
            #expect(page.presentation.errorCategory == .admissionBusy)
            #expect(page.fragment.encodedResult.range(of: try #require(read.frozenMetadataBytes)) != nil)
        }
    }

    @Test func attachedOwnerSurvivesBothCarrierAttachingPaths() throws {
        let page = try Self.page(#"{"saved":true}"#)
        let read = try MCPPreparedToolRead(text: "[]").attachingPreparedResultPage(page).attaching([])
        #expect(read.preparedResultPage === page)
        #expect(read.result.content.first?.text == "[]")
        #expect(read.encodedToolResult == (try MCPPreparedToolRead(text: "[]")).encodedToolResult)
    }

    @Test func attachedFrozenFragmentRewrapsNewIDsWithoutLegacyReparse() async {
        await withOperation { operation in
            // An intentionally unusable legacy text distinguishes carrier consumption
            // from parsing/reclassifying the immutable saved owner a second time.
            let page = try Self.page(#"{"future":1E+9999,"nullable":null}"#)
            let read = try MCPPreparedToolRead(text: "unusable legacy text")
                .attachingPreparedResultPage(page).attaching([])
            for id in [JSONRPCId.string("first"), .integer(2383)] {
                let actual = try MCPModernProviderBinding.read(read, id: id, tool: "query_tasks", operation: operation)
                let expected = try MCPResultEncoder.encode(fragment: page.fragment, id: id)
                #expect(actual == expected)
            }
        }
    }

    @Test func expiredOriginalOperationRejectsPreparationWithoutNewBudget() async throws {
        let saved = OperationCapture()
        await withOperation { operation in saved.operation = operation }
        let operation = try #require(saved.operation)
        let read = try MCPPreparedToolRead(text: "[]")
        #expect(!operation.shouldContinue())
        #expect(throws: CancellationError.self) {
            try MCPModernProviderBinding.prepareReadPages([read], tool: "query_tasks", operation: operation)
        }
    }

    private func withOperation(_ body: @escaping @MainActor @Sendable (MCPReadOperation) throws -> Void) async {
        let coordinator = MCPReadCoordinator()
        let bytes = await coordinator.execute(timeout: Data("timeout".utf8), busy: Data("busy".utf8)) { operation in
            await MainActor.run {
                do {
                    try body(operation)
                    return Self.result(Data("completed".utf8))
                } catch {
                    Issue.record("Modern private-page preparation failed: \(error)")
                    return Self.result(Data("failed".utf8))
                }
            }
        }
        #expect(bytes == Data("completed".utf8))
        for _ in 0..<100 where coordinator.unfinishedCount != 0 {
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(coordinator.unfinishedCount == 0)
    }

    private static func page(_ text: String) throws -> MCPResultPreparedPage {
        try MCPResultPreparation.page(request: MCPResultPagePreparationRequest(text: text, isError: nil,
            origin: .generatedJSON, evidence: .established,
            context: MCPResultContext(tool: "query_tasks", semanticFailure: nil,
                mutationRecovery: nil, entityPositions: []), metadataOwner: nil))
    }

    private static var capture: ReadCaptureMetadata {
        ReadCaptureMetadata(asOf: "2026-10-04T09:00:00.000Z", snapshotId: "original-capture",
            freshness: ReadFreshness(syncState: .inactive, assessment: .notApplicable,
                assessedAt: "2026-10-04T09:00:00.000Z", lastImportedAt: nil,
                evidence: .none, recentImportThresholdMs: 60_000),
            read: ReadExecutionMetadata(policy: .cached, refreshOutcome: .notRequested, budgetMs: 5_000))
    }

    nonisolated private static func result(_ bytes: Data) -> PreparedReadResult {
        PreparedReadResult(encodedResponse: bytes, publications: [],
            publicationErrors: .init(busy: Data(), expired: Data(), capacity: Data()))
    }

    private final class OperationCapture {
        var operation: MCPReadOperation?
    }
}
#endif
