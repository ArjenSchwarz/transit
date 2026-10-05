#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct TaskLinkRemovalEvidenceTests {
    @Test func cleanupDeletesOnlyEligibleEvidenceAndNeverSavesUIDraftsOrActiveRows() throws {
        let base = try TaskLinkCommitDiskFixture()
        let instant = Date()
        let evidence = try row(base, removedAt: instant - TaskLinkGraph.evidenceLifetime - 1)
        base.owner.context.insert(evidence)
        try base.owner.context.save()
        let before = try MCPRecordSnapshot.task(base.source, in: base.owner.context).revision
        base.source.name = "UI draft"
        let removed = try TaskLinkService(container: base.owner.container).cleanupExpiredEvidence(
            evaluationInstant: instant)
        #expect(removed == 1)
        #expect(base.source.name == "UI draft" && base.owner.context.hasChanges)
        let observer = try base.observer()
        #expect(try observer.context.fetchCount(FetchDescriptor<TaskLinkOccurrence>()) == 1)
        #expect(try observer.context.fetchCount(FetchDescriptor<TaskLinkRemovalEvidence>()) == 1)
        let saved = try base.task(base.source.id, in: observer.context)
        let savedRevision = try MCPRecordSnapshot.task(saved, in: observer.context).revision
        #expect(saved.name == "source" && savedRevision == before)
        #expect(try base.historicReceipt(in: observer.context).resultJSON == base.historicJSON)
    }

    @Test(arguments: ["future", "malformed", "ambiguous"])
    func cleanupDefersUnsafeEvidenceIdentityAndDates(fault: String) throws {
        let base = try TaskLinkCommitDiskFixture()
        let now = Date()
        let removedAt = fault == "future" ? now + 1 : now - TaskLinkGraph.evidenceLifetime - 1
        let candidate = try row(base, removedAt: removedAt, revision: fault == "malformed" ? "corrupt" : nil)
        base.owner.context.insert(candidate)
        if fault == "ambiguous" {
            base.owner.context.insert(try row(base, removedAt: now, id: candidate.id))
        }
        try base.owner.context.save()
        #expect(try TaskLinkService(container: base.owner.container).cleanupExpiredEvidence(
            evaluationInstant: now) == 0)
        let observer = try base.observer()
        #expect(try observer.context.fetchCount(FetchDescriptor<TaskLinkRemovalEvidence>())
            == (fault == "ambiguous" ? 3 : 2))
    }

    @Test func cleanupIsBoundedAndExpiredBudgetCannotDeleteAnything() throws {
        let base = try TaskLinkCommitDiskFixture()
        let now = Date()
        for _ in 0..<3 {
            base.owner.context.insert(try row(base, removedAt: now - TaskLinkGraph.evidenceLifetime - 1))
        }
        try base.owner.context.save()
        let service = TaskLinkService(container: base.owner.container)
        #expect(throws: TaskLinkGraphError.deadlineExceeded) {
            try service.cleanupExpiredEvidence(evaluationInstant: now,
                budget: TaskLinkGraphBudget(deadline: .now - .seconds(1)))
        }
        #expect(try base.observer().context.fetchCount(FetchDescriptor<TaskLinkRemovalEvidence>()) == 4)
        #expect(try service.cleanupExpiredEvidence(evaluationInstant: now, limit: 2) == 2)
        #expect(try base.observer().context.fetchCount(FetchDescriptor<TaskLinkRemovalEvidence>()) == 2)
    }

    @Test(arguments: [false, true])
    func bothArrivalOrdersPreserveConflictAndFrozenExpiryWithoutChangingContentToken(evidenceFirst: Bool) throws {
        let base = try TaskLinkCommitDiskFixture()
        let now = Date()
        let edgeID = base.edge.id
        let source = base.edge.sourceTaskID
        let target = base.edge.targetTaskID
        base.owner.context.delete(base.edge)
        try base.owner.context.save()
        let evidence = try row(base, removedAt: now, edgeID: edgeID, source: source, target: target)
        let active = TaskLinkOccurrence(id: edgeID, kindRawValue: "dependency", sourceTaskID: source,
                                        targetTaskID: target, createdAt: base.instant)
        if evidenceFirst { base.owner.context.insert(evidence) } else { base.owner.context.insert(active) }
        try base.owner.context.save()
        if evidenceFirst { base.owner.context.insert(active) } else { base.owner.context.insert(evidence) }
        try base.owner.context.save()
        let frozen = try TaskLinkService.graph(in: base.owner.context, evaluationInstant: now)
        let revision = try MCPRecordSnapshot.task(base.source, in: base.owner.context).revision
        #expect(frozen.diagnostics.contains { $0.code == "active_removal_conflict" && $0.edgeId == edgeID })
        #expect(frozen.assessment(for: target) == .invalid)
        let later = try TaskLinkService.graph(in: base.owner.context,
            evaluationInstant: now + TaskLinkGraph.evidenceLifetime + 1)
        #expect(later.assessment(for: target) == .unblocked)
        #expect(frozen.assessment(for: target) == .invalid)
        #expect(try MCPRecordSnapshot.task(base.source, in: base.owner.context).revision == revision)
        #expect(try base.owner.context.fetchCount(FetchDescriptor<TaskLinkOccurrence>()) == 1)
    }

    private func row(_ base: TaskLinkCommitDiskFixture, removedAt: Date, id: UUID = UUID(),
                     revision: String? = nil, edgeID: UUID? = nil, source: UUID? = nil,
                     target: UUID? = nil) throws -> TaskLinkRemovalEvidence {
        let value = TaskLinkOccurrenceValue(physicalKey: Data(), id: edgeID ?? UUID(), kind: "dependency",
            source: source ?? base.source.id, target: target ?? base.target.id, createdAt: base.instant)
        return try TaskLinkRemovalEvidence(id: id, edgeId: value.id, kindRawValue: value.kind,
            sourceTaskID: value.source, targetTaskID: value.target, createdAt: value.createdAt,
            occurrenceRevision: revision ?? TaskLinkGraph.occurrenceRevision(value), removedAt: removedAt)
    }
}
#endif
