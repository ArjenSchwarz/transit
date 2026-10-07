#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct TaskConsolidationStageRollbackTests {
    @Test func throwInsideStageRollsBackAlreadyStagedOwnedGroup() async throws {
        let fixture = try TaskConsolidationCommitFixture()
        let ids = [fixture.base.target.id, fixture.base.source.id, fixture.extra.id]
        let before = try revisions(ids, fixture: fixture, context: fixture.base.owner.context)
        let originalPolicy = fixture.adapter.policy()
        let factory = try #require(originalPolicy.makeCommitServices)
        var injectedStageFailure = false
        let policy = MCPBatchWritePolicy(makeCommitServices: factory, validateBeforeApply: { command, context in
            try originalPolicy.validateBeforeApply(command, context)
            let service = TaskConsolidationService(context: context, originScopeId: fixture.review.originScopeId,
                reviewSource: { _, _ in fixture.review }, clock: { fixture.base.instant })
            let tasks = try service.resolve(fixture.review, budget: TaskLinkGraphBudget())
            let graph = try TaskLinkService.graph(in: context, evaluationInstant: fixture.base.instant)
            _ = try service.apply(command, reviewId: fixture.review.id)
            #expect(context.hasChanges && context !== fixture.base.owner.context)
            #expect(context.insertedModelsArray.compactMap { $0 as? TaskConsolidationEvent }.count == 1)
            #expect(context.insertedModelsArray.compactMap { $0 as? TaskLinkOccurrence }.count == 2)
            let effects = TaskConsolidationService.OwnedEffects(id: UUID(), changes: [],
                applied: .init(inserted: [], removed: []), graph: graph, instant: fixture.base.instant)
            do {
                // Lower-seam injection after real apply staging; no second domain apply or production hook.
                _ = try service.stage(effects, review: fixture.review, command: command, tasks: tasks,
                    budget: TaskLinkGraphBudget(checkpoint: { throw StageFault.injected }))
                Issue.record("Stage checkpoint did not throw")
            } catch StageFault.injected {
                injectedStageFailure = true
                throw StageFault.injected
            }
        })
        let result = await fixture.coordinator.execute(tool: "consolidate_tasks", arguments: fixture.arguments(),
            batchPolicy: policy)
        let envelope = try fixture.base.decode(result)
        #expect(injectedStageFailure)
        #expect(envelope["outcome"] as? String == "rejected" && envelope["accepted"] as? Bool == true)
        #expect(fixture.observation.commitSaves == 0)
        let observer = try fixture.base.observer()
        #expect(try revisions(ids, fixture: fixture, context: observer.context) == before)
        #expect(try observer.context.fetchCount(FetchDescriptor<TaskConsolidationEvent>()) == 0)
        #expect(try observer.context.fetchCount(FetchDescriptor<TaskLinkOccurrence>()) == 1)
        #expect(try observer.context.fetchCount(FetchDescriptor<Transit.Comment>()) == 1)
        let receipts = try fixture.receipts(in: observer.context)
        #expect(receipts.count == 1 && receipts.first?.stateRawValue == "rejected")
        #expect(try fixture.base.historicReceipt(in: observer.context).resultJSON == fixture.base.historicJSON)
        #expect(!fixture.base.owner.context.hasChanges && !observer.context.hasChanges)
    }

    private func revisions(_ ids: [UUID], fixture: TaskConsolidationCommitFixture,
                           context: ModelContext) throws -> [UUID: String] {
        try Dictionary(uniqueKeysWithValues: ids.map {
            ($0, try MCPRecordSnapshot.task(fixture.base.task($0, in: context), in: context).revision)
        })
    }

    nonisolated private enum StageFault: Error { case injected }
}
#endif
