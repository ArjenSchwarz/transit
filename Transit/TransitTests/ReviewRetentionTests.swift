#if os(macOS)
import Foundation
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct ReviewRetentionTests {
    private func entry(now: ContinuousClock.Instant, size: Int = 256) -> ConsolidationReviewEntry {
        ConsolidationReviewEntry(id: UUID(), kind: .apply, originScopeId: "isolated-store",
            revision: "p1:" + String(repeating: "a", count: 64),
            proposalBytes: Data(repeating: 120, count: size), expiresAt: now + .seconds(300))
    }

    private func bundle(_ entry: ConsolidationReviewEntry) throws -> MCPResultRetainedBundle {
        let page = try MCPResultPreparation.page(request: MCPResultPagePreparationRequest(
            text: "{\"reviewId\":\"\(entry.id)\",\"reviewRevision\":\"\(entry.revision)\"}",
            isError: false, origin: .generatedJSON, evidence: .established,
            context: MCPResultContext(tool: "preview_task_consolidation", semanticFailure: nil,
                                      mutationRecovery: nil, entityPositions: []), metadataOwner: nil))
        return try MCPResultPreparation.prepare(pages: [page], budget: MCPResultRetentionBudget(
            store: .ordinary, originalCaptureIndexBytes: entry.retainedByteCount,
            visibleBytes: 0, pendingBytes: 0))
    }

    private func publish(_ reservation: MCPPublicationReservation, store: MCPTaskQuerySnapshotStore) throws {
        let rejection = store.domain.withLock { () -> PublicationRejection? in
            if let failure = reservation.validateLocked(in: store.domain) {
                reservation.discardLocked(in: store.domain)
                return failure
            }
            reservation.commitLocked(in: store.domain)
            return nil
        }
        #expect(rejection == nil)
    }

    @Test func invisibleUntilGateAndExactScopeKindRevision() throws {
        let now = ContinuousClock.now
        let store = MCPTaskQuerySnapshotStore(now: { now })
        let value = entry(now: now)
        let prepared = try store.prepareReview(value, bundle: bundle(value), operationID: UUID(),
                                                deadline: now + .seconds(5))
        #expect(throws: (any Error).self) {
            try store.review(id: value.id, revision: value.revision, scope: value.originScopeId, kind: .apply)
        }
        try publish(prepared, store: store)
        for _ in 0..<2 {
            #expect(try store.review(id: value.id, revision: value.revision,
                scope: value.originScopeId, kind: .apply).proposalBytes == value.proposalBytes)
        }
        #expect(throws: (any Error).self) {
            try store.review(id: value.id, revision: value.revision, scope: "other-store", kind: .apply)
        }
        #expect(throws: (any Error).self) {
            try store.review(id: value.id, revision: value.revision, scope: value.originScopeId, kind: .undo)
        }
        #expect(throws: (any Error).self) {
            try store.review(id: value.id, revision: "p1:changed", scope: value.originScopeId, kind: .apply)
        }
    }

    @Test func fiveMinuteExpiryClearAndFreshStoreNeverExtend() throws {
        var now = ContinuousClock.now
        let store = MCPTaskQuerySnapshotStore(now: { now })
        let value = entry(now: now)
        try publish(store.prepareReview(value, bundle: bundle(value), operationID: UUID(),
                                        deadline: now + .seconds(5)), store: store)
        now = value.expiresAt - .milliseconds(1)
        _ = try store.review(id: value.id, revision: value.revision, scope: value.originScopeId, kind: .apply)
        now = value.expiresAt
        #expect(throws: (any Error).self) {
            try store.review(id: value.id, revision: value.revision, scope: value.originScopeId, kind: .apply)
        }
        #expect(store.retainedBytes == 0)
        let fresh = MCPTaskQuerySnapshotStore()
        #expect(throws: (any Error).self) {
            try fresh.review(id: value.id, revision: value.revision, scope: value.originScopeId, kind: .apply)
        }
    }

    @Test func ordinaryRebuildAndClearCarryThenRetireReview() throws {
        let now = ContinuousClock.now
        let store = MCPTaskQuerySnapshotStore(now: { now })
        let value = entry(now: now)
        try publish(store.prepareReview(value, bundle: bundle(value), operationID: UUID(),
                                        deadline: now + .seconds(5)), store: store)
        try store.publish(pages: ["first", "second"], cursors: [UUID().uuidString],
                          deadline: now + .seconds(1))
        _ = try store.review(id: value.id, revision: value.revision, scope: value.originScopeId, kind: .apply)
        store.clear()
        #expect(store.retainedBytes == 0)
        #expect(throws: (any Error).self) {
            try store.review(id: value.id, revision: value.revision, scope: value.originScopeId, kind: .apply)
        }
    }

    @Test func eightSharedRootsAndCompleteWrapperBoundary() throws {
        let now = ContinuousClock.now
        let store = MCPTaskQuerySnapshotStore(now: { now })
        for _ in 0..<8 {
            let value = entry(now: now)
            try publish(store.prepareReview(value, bundle: bundle(value), operationID: UUID(),
                                            deadline: now + .seconds(5)), store: store)
        }
        let ninth = entry(now: now)
        #expect(throws: (any Error).self) {
            try store.prepareReview(ninth, bundle: bundle(ninth), operationID: UUID(),
                                    deadline: now + .seconds(5))
        }
        let value = entry(now: now)
        let prepared = try bundle(value)
        #expect(prepared.charge.totalBytes > value.proposalBytes.count)
        let tooSmall = MCPTaskQuerySnapshotStore(now: { now }, maxBytes: prepared.charge.totalBytes - 1)
        #expect(throws: (any Error).self) {
            try tooSmall.prepareReview(value, bundle: prepared, operationID: UUID(), deadline: now + .seconds(5))
        }
        let exact = MCPTaskQuerySnapshotStore(now: { now }, maxBytes: prepared.charge.totalBytes)
        try publish(exact.prepareReview(value, bundle: prepared, operationID: UUID(),
                                        deadline: now + .seconds(5)), store: exact)
        #expect(exact.retainedBytes == prepared.charge.totalBytes)
    }
}
#endif
