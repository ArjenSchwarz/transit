#if os(macOS)
import Foundation
import Testing
@testable import Transit

/// Pure value preparation: actual domain reservation/publication is task17 coverage.
@MainActor
struct MCPResultPreparationBudgetTests {
    @Test func normativeComponentBreakdownPreservesOriginalBacking() throws {
        let text = #"{"a":"é","b":[false,1E-9,null]}"#
        let page = try makePage(text)
        let bundle = try prepare([page], base: 137)
        let charge = bundle.charge
        // Hand-computed tree dynamic payload; embedded root enum handle is excluded.
        let treeDynamic = MemoryLayout<[MCPJSONMember]>.stride + 2 * MemoryLayout<MCPJSONMember>.stride
            + 2 + MemoryLayout<String>.stride + 2 + MemoryLayout<[MCPJSONValue]>.stride
            + 3 * MemoryLayout<MCPJSONValue>.stride + MemoryLayout<Bool>.stride
            + MemoryLayout<MCPJSONNumber>.stride + 4
        #expect(charge.originalCaptureIndexBytes == 137)
        #expect(charge.originalTextBytes == text.utf8.count)
        #expect(charge.sourceDocumentBytes == text.utf8.count)
        #expect(charge.sourceValueBytes == MemoryLayout<MCPResultSource>.stride + treeDynamic)
        #expect(charge.presentationValueBytes == MemoryLayout<MCPResultPresentation>.stride)
        #expect(charge.fragmentBytes == page.fragment.encodedResult.count + MemoryLayout<MCPResultToolFragment>.stride)
        #expect(charge.metadataDocumentBytes == 0)
        #expect(charge.metadataValueBytes == 0)
        // Page array header and every reference slot, plus each unique page's
        // metadata pointer. Source/presentation/fragment headers are above.
        #expect(charge.ownerReferenceBytes == MemoryLayout<[MCPResultPreparedPage]>.stride
            + MemoryLayout<MCPResultPreparedPage>.stride + MemoryLayout<MCPResultPreparedMetadata?>.stride)
        #expect(charge.totalBytes == components(charge))
        #expect(page.source.originalText == text)
        #expect(page.source.document?.originalUTF8 == Data(text.utf8))
        #expect(page.source.originalIsError == false)
        #expect(bundle.pages[0] === page)
        #expect(page.fragment.encodedResult.range(of: Data(text.utf8)) != nil)
    }

    @Test func metadataHasIndependentNonzeroDecodedValueCharge() throws {
        let text = #"{"x":"é","b":[false,1E-9,null]}"#
        let value = try MCPResultMetadata.make(document: MCPJSONDocument.parse(text))
        let metadata = try MCPResultPreparation.metadata(value: value)
        let page = try makePage("null", metadata: metadata)
        let charge = try prepare([page]).charge
        let dynamic = MemoryLayout<[MCPJSONMember]>.stride + 2 * MemoryLayout<MCPJSONMember>.stride
            + 2 + MemoryLayout<String>.stride + 2 + MemoryLayout<[MCPJSONValue]>.stride
            + 3 * MemoryLayout<MCPJSONValue>.stride + MemoryLayout<Bool>.stride
            + MemoryLayout<MCPJSONNumber>.stride + 4
        #expect(charge.metadataDocumentBytes == text.utf8.count)
        #expect(charge.metadataValueBytes == MemoryLayout<MCPResultMetadata>.stride + dynamic)
        #expect(metadata.value.document.originalUTF8 == Data(text.utf8))
        #expect(charge.totalBytes == components(charge))
    }

    @Test func sharedOwnersAreCountedOnceButEqualBytesDistinctOwnersAreNot() throws {
        let value = try MCPResultMetadata.make(
            document: MCPJSONDocument.parse(MCPResultPreparationFixtures.metadataText))
        let shared = try MCPResultPreparation.metadata(value: value)
        let first = try makePage(#"{"future":null}"#, metadata: shared)
        let second = try makePage(#"{"future":null}"#, metadata: shared)
        let unique = try prepare([first])
        let aliased = try prepare([first, first])
        let distinct = try prepare([first, second])
        #expect(aliased.charge.originalTextBytes == unique.charge.originalTextBytes)
        #expect(aliased.charge.sourceValueBytes == unique.charge.sourceValueBytes)
        #expect(aliased.charge.fragmentBytes == unique.charge.fragmentBytes)
        #expect(distinct.charge.originalTextBytes == 2 * unique.charge.originalTextBytes)
        #expect(distinct.charge.sourceValueBytes == 2 * unique.charge.sourceValueBytes)
        #expect(distinct.charge.fragmentBytes == 2 * unique.charge.fragmentBytes)
        #expect(distinct.charge.metadataDocumentBytes == value.document.originalUTF8.count)
        #expect(distinct.charge.metadataValueBytes == unique.charge.metadataValueBytes)
        #expect(first.metadataOwner === second.metadataOwner)
        let separate = try MCPResultPreparation.metadata(value: value)
        let third = try makePage(#"{"future":null}"#, metadata: separate)
        let separateBundle = try prepare([first, third])
        #expect(separateBundle.charge.metadataDocumentBytes == 2 * unique.charge.metadataDocumentBytes)
        #expect(separateBundle.charge.metadataValueBytes == 2 * unique.charge.metadataValueBytes)
        #expect(first.metadataOwner !== third.metadataOwner)
        #expect(aliased.charge.ownerReferenceBytes == unique.charge.ownerReferenceBytes
            + MemoryLayout<MCPResultPreparedPage>.stride)
        #expect(distinct.charge.ownerReferenceBytes == aliased.charge.ownerReferenceBytes
            + MemoryLayout<MCPResultPreparedMetadata?>.stride)
        #expect(aliased.charge.totalBytes == components(aliased.charge))
        #expect(distinct.charge.totalBytes == components(distinct.charge))
    }

    @Test func twoThousandSeededRecordsFourPagesRetainExactFrozenEvidence() throws {
        let texts = try MCPResultPreparationFixtures.pages()
        #expect(texts.count == 4)
        #expect(texts == (try MCPResultPreparationFixtures.pages()))
        let metadata = try MCPResultPreparation.metadata(value: MCPResultMetadata.make(
            document: MCPJSONDocument.parse(MCPResultPreparationFixtures.metadataText)))
        let checks = Checkpoints()
        let pages = try texts.map { try makePage($0, metadata: metadata, checkpoint: { try checks.check() }) }
        let bundle = try MCPResultPreparation.prepare(pages: pages, budget: budget(base: 8_192),
                                             checkpoint: { try checks.check() })
        #expect(bundle.pages.count == 4)
        #expect(bundle.charge.originalCaptureIndexBytes == 8_192)
        #expect(bundle.charge.originalTextBytes == texts.reduce(0) { $0 + $1.utf8.count })
        #expect(bundle.charge.sourceDocumentBytes == bundle.charge.originalTextBytes)
        #expect(bundle.charge.metadataDocumentBytes == MCPResultPreparationFixtures.metadataText.utf8.count)
        #expect(bundle.charge.totalBytes == components(bundle.charge))
        #expect(checks.count > 100)
        for (index, page) in bundle.pages.enumerated() {
            #expect(page.source.originalText == texts[index])
            #expect(page.source.document?.originalUTF8 == Data(texts[index].utf8))
            #expect(page.metadataOwner === metadata)
            #expect(page.fragment.encodedResult.range(of: Data(texts[index].utf8)) != nil)
            #expect(page.fragment.encodedResult.range(of: metadata.value.document.originalUTF8) != nil)
            guard case .array(let records) = page.source.document?.value else {
                Issue.record("Original decoded array missing"); continue
            }
            #expect(records.count == 500)
        }
    }

    @Test func fixedSeparateStoreBoundariesIncludeVisibleAndPendingBytes() throws {
        let page = try makePage("null")
        let measured = try prepare([page]).charge.totalBytes
        for store in MCPResultRetentionStore.allCases {
            let limit = MCPResultRetentionBudget.limitBytes
            let exact = try MCPResultPreparation.prepare(pages: [page],
                budget: budget(store: store, base: 23, visible: limit - measured - 30, pending: 7))
            #expect(exact.charge.totalBytes == measured + 23)
            #expect(throwsPreparation(.retentionCapacity) {
                _ = try MCPResultPreparation.prepare(pages: [page],
                    budget: budget(store: store, base: 23, visible: limit - measured - 30, pending: 8))
            })
            #expect(throwsPreparation(.retentionCapacity) {
                _ = try MCPResultPreparation.prepare(pages: [page], budget: budget(store: store, base: limit))
            })
        }
        // One store's observed usage is never added to the other's budget.
        #expect(try MCPResultPreparation.prepare(
            pages: [page], budget: budget(store: .ordinary)).charge.totalBytes == measured)
        #expect(try MCPResultPreparation.prepare(
            pages: [page], budget: budget(store: .reusable)).charge.totalBytes == measured)
    }

    @Test func invalidAndOverflowAccountingFailWithoutPartialBundle() throws {
        let page = try makePage("false")
        for value in [budget(base: -1), budget(visible: -1), budget(pending: -1)] {
            #expect(throwsPreparation(.invalidAccounting) {
                _ = try MCPResultPreparation.prepare(pages: [page], budget: value)
            })
        }
        for value in [budget(base: Int.max), budget(visible: Int.max, pending: 1)] {
            var returned: MCPResultRetainedBundle?
            #expect(throwsPreparation(.arithmeticOverflow) {
                returned = try MCPResultPreparation.prepare(pages: [page], budget: value)
            })
            #expect(returned == nil)
        }
    }

    @Test func originalTypedCancellationAndDeadlineSurviveAllPreparationStages() throws {
        let page = try makePage("null")
        for failure in [Cutoff.cancelled, .deadline] {
            #expect(throwsCutoff(failure) {
                _ = try makePage(try MCPResultPreparationFixtures.pages()[0], origin: .retainedJSON,
                        checkpoint: { throw failure })
            })
            var returned: MCPResultRetainedBundle?
            #expect(throwsCutoff(failure) {
                returned = try MCPResultPreparation.prepare(pages: [page], budget: budget(),
                                                    checkpoint: { throw failure })
            })
            #expect(returned == nil)
        }
        let checks = Checkpoints(cutoff: 5)
        #expect(throwsCutoff(.deadline) {
            _ = try makePage(try MCPResultPreparationFixtures.pages()[0], checkpoint: { try checks.check() })
        })
        #expect(checks.count == 5)
    }

    @Test func lateMeasurementAndPlainTextEncodingCutoffsReturnNoPartialValue() throws {
        let texts = try MCPResultPreparationFixtures.pages()
        let pages = try texts.map { try makePage($0) }
        let measurement = Checkpoints()
        _ = try MCPResultPreparation.prepare(pages: pages, budget: budget(),
                                      checkpoint: { try measurement.check() })
        #expect(measurement.count > 10)
        let late = Checkpoints(cutoff: max(2, measurement.count / 2))
        var bundle: MCPResultRetainedBundle?
        #expect(throwsCutoff(.deadline) {
            bundle = try MCPResultPreparation.prepare(pages: pages, budget: budget(),
                                                checkpoint: { try late.check() })
        })
        #expect(late.count == max(2, measurement.count / 2))
        #expect(bundle == nil)
        // Plain text bypasses JSON scanning and record selection; late work here
        // is the frozen writer over escaped source text, not a parser callback.
        let text = String(repeating: "é\n\"\\", count: 100_000)
        let encoding = Checkpoints()
        _ = try makePage(text, origin: .plainText, checkpoint: { try encoding.check() })
        #expect(encoding.count > 100)
        let encodingCutoff = Checkpoints(cutoff: max(50, encoding.count - 5), failure: .cancelled)
        var page: MCPResultPreparedPage?
        #expect(throwsCutoff(.cancelled) {
            page = try makePage(text, origin: .plainText, checkpoint: { try encodingCutoff.check() })
        })
        #expect(encodingCutoff.count == max(50, encoding.count - 5))
        #expect(page == nil)
    }

    @Test func presentationLinkAndRecoveryBackingIsIncluded() throws {
        let uuid = UUID(uuidString: "AA000000-0000-0000-0000-000000000001")!
        let context = MCPResultContext(tool: "update_task", semanticFailure: nil,
            mutationRecovery: .protectedWrite(.init(tool: "update_task", idempotencyKey: "original-key-é")),
            entityPositions: [.init(entityType: .task, sourcePath: "/record")])
        let text = "{\"record\":{\"taskId\":\"\(uuid)\"},\"accepted\":true}"
        let page = try makePage(text, context: context, evidence: .unestablished)
        let link = try #require(page.presentation.links.first)
        #expect(link.entityId == uuid)
        let charge = try prepare([page]).charge
        let dynamic = MemoryLayout<MCPUnavailableLink>.stride + link.sourcePath.utf8.count
            + link.availability.utf8.count + link.reason.utf8.count
            + "update_task".utf8.count + "original-key-é".utf8.count
        #expect(charge.presentationValueBytes == MemoryLayout<MCPResultPresentation>.stride + dynamic)
    }

}

extension MCPResultPreparationBudgetTests {
    @Test func batchAndMaintenanceRecoveryHaveIndependentDynamicCharges() throws {
        let items = [
            MCPBatchRecoveryItem(index: 0, itemId: "first-é", operation: "update_task",
                originalKey: .init(tool: "update_task", idempotencyKey: "original-one"),
                targetTaskId: UUID(uuidString: "AA000000-0000-0000-0000-000000000001")),
            MCPBatchRecoveryItem(index: 1, itemId: nil, operation: "delete_task",
                originalKey: .init(tool: "delete_task", idempotencyKey: "original-two"), targetTaskId: nil)
        ]
        let context = MCPResultContext(tool: "mutate_tasks", semanticFailure: nil,
            mutationRecovery: .applicationBatch(items: items), entityPositions: [])
        let page = try makePage("null", context: context, evidence: .unestablished)
        let charge = try prepare([page]).charge
        let dynamic = 2 * MemoryLayout<MCPBatchRecoveryItem>.stride + "first-é".utf8.count
            + 2 * "update_task".utf8.count + "original-one".utf8.count
            + 2 * "delete_task".utf8.count + "original-two".utf8.count
        #expect(charge.presentationValueBytes == MemoryLayout<MCPResultPresentation>.stride + dynamic)
        guard case .applicationBatch(let retained) = page.presentation.recovery?.mutation else {
            Issue.record("Original batch recovery missing"); return
        }
        try #require(retained.count == 2)
        #expect(retained.map(\.index) == [0, 1])
        #expect(retained.map(\.originalKey) == items.map(\.originalKey))
        #expect(retained[0].itemId == items[0].itemId)
        #expect(retained[0].targetTaskId == items[0].targetTaskId)
        #expect(retained[1].itemId == nil)
        #expect(retained[1].targetTaskId == nil)
        let maintenance = try makePage("null", context: .init(tool: "repair_links", semanticFailure: nil,
            mutationRecovery: .unprotectedMaintenance(tool: "repair_links"), entityPositions: []),
            evidence: .unestablished)
        #expect(try prepare([maintenance]).charge.presentationValueBytes
            == MemoryLayout<MCPResultPresentation>.stride + "repair_links".utf8.count)
    }

    @Test func blockedParserAndEncoderObserveOriginalFakeCutoff() async throws {
        let text = try MCPResultPreparationFixtures.pages()[0]
        let source = try MCPResultSource.make(text: text, isError: false, origin: .generatedJSON,
                                      evidence: .established)
        let presentation = MCPResultPresentation(evidence: .established, links: [], errorCategory: nil, recovery: nil)
        for encode in [false, true] {
            for cutoff in [Cutoff.cancelled, .deadline] {
                let barrier = Barrier(cutoff: cutoff)
                let worker = Task.detached {
                    do {
                        if encode {
                            _ = try MCPResultEncoder.freeze(source: source, presentation: presentation, metadata: nil,
                                                    checkpoint: { try barrier.check() })
                        } else {
                            _ = try MCPResultSource.make(text: text, isError: false, origin: .retainedJSON,
                        evidence: .established, checkpoint: { try barrier.check() })
                        }
                        return false
                    } catch { return (error as? Cutoff) == cutoff }
                }
                let started = await Task.detached { barrier.waitForEntry() }.value
                // Deterministic fake deadline/cancellation changes only at this boundary.
                barrier.release.signal()
                #expect(started)
                #expect(await worker.value)
            }
        }
    }

}

private extension MCPResultPreparationBudgetTests {
    func makePage(_ text: String, metadata: MCPResultPreparedMetadata? = nil,
                  context: MCPResultContext? = nil, origin: MCPResultOrigin = .generatedJSON,
                  evidence: MCPResultEvidence = .established,
                  checkpoint: @escaping @Sendable () throws -> Void = {}) throws -> MCPResultPreparedPage {
        try MCPResultPreparation.page(request: .init(text: text, isError: false, origin: origin,
            evidence: evidence, context: context ?? MCPResultContext(tool: "query_tasks", semanticFailure: nil,
                mutationRecovery: nil, entityPositions: []), metadataOwner: metadata), checkpoint: checkpoint)
    }

    func prepare(_ pages: [MCPResultPreparedPage], base: Int = 0) throws -> MCPResultRetainedBundle {
        try MCPResultPreparation.prepare(pages: pages, budget: budget(base: base))
    }

    func budget(store: MCPResultRetentionStore = .ordinary, base: Int = 0,
                visible: Int = 0, pending: Int = 0) -> MCPResultRetentionBudget {
        .init(store: store, originalCaptureIndexBytes: base, visibleBytes: visible, pendingBytes: pending)
    }

    func components(_ charge: MCPResultRetainedCharge) -> Int {
        charge.originalCaptureIndexBytes + charge.originalTextBytes + charge.sourceDocumentBytes
            + charge.sourceValueBytes + charge.presentationValueBytes + charge.fragmentBytes
            + charge.metadataDocumentBytes + charge.metadataValueBytes + charge.ownerReferenceBytes
    }

    func throwsPreparation(_ expected: MCPResultPreparationError, body: () throws -> Void) -> Bool {
        do { try body(); return false } catch { return (error as? MCPResultPreparationError) == expected }
    }

    private func throwsCutoff(_ expected: Cutoff, body: () throws -> Void) -> Bool {
        do { try body(); return false } catch { return (error as? Cutoff) == expected }
    }

    nonisolated private enum Cutoff: Error, Sendable { case cancelled, deadline }

    nonisolated private final class Barrier: @unchecked Sendable {
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let cutoff: Cutoff
        init(cutoff: Cutoff) { self.cutoff = cutoff }
        func waitForEntry() -> Bool { entered.wait(timeout: .now() + 2) == .success }
        func check() throws {
            entered.signal()
            guard release.wait(timeout: .now() + 2) == .success else { throw Cutoff.deadline }
            throw cutoff
        }
    }

    nonisolated private final class Checkpoints: @unchecked Sendable {
        private let lock = NSLock()
        private var checks = 0
        private let cutoff: Int?
        private let failure: Cutoff
        init(cutoff: Int? = nil, failure: Cutoff = .deadline) {
            self.cutoff = cutoff
            self.failure = failure
        }
        var count: Int { lock.withLock { checks } }
        func check() throws {
            try lock.withLock {
                checks += 1
                if checks == cutoff { throw failure }
            }
        }
    }
}
#endif
