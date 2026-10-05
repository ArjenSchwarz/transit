#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct TaskConsolidationCaptureTests {
    @Test func savedHistoryClosesAllParticipantsWithoutExpandingSelection() async throws {
        let fixture = try TaskConsolidationCommitFixture()
        _ = await fixture.execute()
        let capture = TaskConsolidationSavedCapture(container: fixture.base.owner.container,
            fence: .actorOnlyTestFixture)
        let evidence = try capture.capture(selectedTaskIds: [fixture.base.source.id])
        #expect(evidence.selectedTaskIds == [fixture.base.source.id])
        #expect(Set(evidence.originals.map(\.id))
            == Set([fixture.base.source.id, fixture.base.target.id, fixture.extra.id]))
        #expect(evidence.history.count == 1)
        #expect(evidence.history[0].undoUnavailableReason == nil)
        #expect(evidence.history[0].undoAvailable)
        #expect(evidence.events.count == 1 && evidence.graph.occurrences.count == 3)
        let original = try #require(evidence.originals.first { $0.id == fixture.base.source.id })
        #expect((String(bytes: original.recordJSON, encoding: .utf8) ?? "").contains("original comment"))
        #expect(evidence.encodedByteCount > original.recordJSON.count)
    }

    @Test func pendingUIChangesNeverEnterSavedOriginals() throws {
        let fixture = try TaskConsolidationCommitFixture()
        fixture.base.source.taskDescription = "unsaved draft"
        fixture.base.owner.context.delete(fixture.extra)
        let capture = TaskConsolidationSavedCapture(container: fixture.base.owner.container,
            fence: .actorOnlyTestFixture)
        let evidence = try capture.capture(selectedTaskIds: [fixture.base.source.id, fixture.extra.id])
        #expect(evidence.originals.count == 2)
        #expect(evidence.originals.first { $0.id == fixture.base.source.id }?.fields.description != "unsaved draft")
        #expect(evidence.history.isEmpty && evidence.events.isEmpty)
        #expect(fixture.base.owner.context.hasChanges)
    }

    @Test func historyFailureAndBoundaryInvalidationNeverBecomeEmptyCoverage() async throws {
        let fixture = try TaskConsolidationCommitFixture()
        _ = await fixture.execute()
        let failing = TaskConsolidationSavedCapture(container: fixture.base.owner.container,
            fence: .actorOnlyTestFixture, hooks: .init(fetchEvents: { _ in throw CaptureFault.injected }))
        #expect(throws: (any Error).self) { try failing.capture(selectedTaskIds: [fixture.base.source.id]) }
        var generation: UInt64 = 0
        let moving = TaskConsolidationSavedCapture(container: fixture.base.owner.container,
            fence: .actorOnlyTestFixture, hooks: .init(generation: { generation }, afterCopy: { generation += 1 }))
        #expect(throws: (any Error).self) { try moving.capture(selectedTaskIds: [fixture.base.source.id]) }
    }

    @Test func malformedImportedHistoryFailsBeforeAvailabilityAssessment() async throws {
        let fixture = try TaskConsolidationCommitFixture()
        _ = await fixture.execute()
        let context = ModelContext(fixture.base.owner.container)
        let valid = try #require(context.fetch(FetchDescriptor<TaskConsolidationEvent>()).first)
        let malformed = TaskConsolidationEvent(id: UUID(), operationId: valid.operationId, kindRawValue: "apply",
            createdAt: valid.createdAt, originScopeId: valid.originScopeId,
            survivorTaskId: valid.survivorTaskId, candidateTaskIds: [fixture.base.source.id], payloadJSON: "{}")
        context.insert(malformed)
        try context.save()
        let capture = TaskConsolidationSavedCapture(container: fixture.base.owner.container,
            fence: .actorOnlyTestFixture)
        #expect(throws: (any Error).self) { try capture.capture(selectedTaskIds: [fixture.base.source.id]) }
    }

    @Test func completeWrapperBudgetAndOriginalDeadlineRejectWithoutPartialHistory() throws {
        let fixture = try TaskConsolidationCommitFixture(fault: "large-unchanged")
        let capture = TaskConsolidationSavedCapture(container: fixture.base.owner.container,
            fence: .actorOnlyTestFixture)
        #expect(throws: (any Error).self) {
            try capture.capture(selectedTaskIds: [fixture.base.source.id],
                budget: TaskLinkGraphBudget(maximumBytes: 64))
        }
        #expect(throws: (any Error).self) {
            try capture.capture(selectedTaskIds: [fixture.base.source.id],
                budget: TaskLinkGraphBudget(deadline: .now - .seconds(1)))
        }
    }
    @Test func missingParticipantRetainsHistoryAndDisablesUndo() async throws {
        let fixture = try TaskConsolidationCommitFixture()
        _ = await fixture.execute()
        let observer = try fixture.base.observer()
        observer.context.delete(try fixture.base.task(fixture.extra.id, in: observer.context))
        try observer.context.save()
        let evidence = try TaskConsolidationSavedCapture(container: fixture.base.owner.container,
            fence: .actorOnlyTestFixture).capture(selectedTaskIds: [fixture.base.source.id])
        #expect(evidence.history.count == 1 && !evidence.history[0].undoAvailable)
        #expect(evidence.history[0].undoUnavailableReason == "CONSOLIDATION_EVIDENCE_UNAVAILABLE")
        #expect(evidence.events.count == 1)
    }

    @Test func duplicatePhysicalEventsRejectAndUnrelatedMalformedHistoryIsNotLoaded() async throws {
        let fixture = try TaskConsolidationCommitFixture()
        _ = await fixture.execute()
        let context = ModelContext(fixture.base.owner.container)
        let valid = try #require(context.fetch(FetchDescriptor<TaskConsolidationEvent>()).first)
        context.insert(TaskConsolidationEvent(id: UUID(), operationId: UUID(), kindRawValue: "apply",
            createdAt: valid.createdAt, originScopeId: valid.originScopeId, survivorTaskId: UUID(),
            candidateTaskIds: [UUID()], payloadJSON: "unrelated malformed payload"))
        try context.save()
        let capture = TaskConsolidationSavedCapture(container: fixture.base.owner.container,
            fence: .actorOnlyTestFixture)
        #expect(try capture.capture(selectedTaskIds: [fixture.base.source.id]).events.count == 1)
        context.insert(TaskConsolidationEvent(id: valid.id, operationId: valid.operationId,
            kindRawValue: valid.kindRawValue, createdAt: valid.createdAt, originScopeId: valid.originScopeId,
            survivorTaskId: valid.survivorTaskId,
            candidateTaskIds: [fixture.base.source.id, fixture.extra.id], payloadJSON: valid.payloadJSON))
        try context.save()
        #expect(throws: (any Error).self) { try capture.capture(selectedTaskIds: [fixture.base.source.id]) }
    }

    @Test func commentStorageFailureDoesNotYieldAnIncompleteReview() throws {
        let fixture = try TaskConsolidationCommitFixture()
        let capture = TaskConsolidationSavedCapture(container: fixture.base.owner.container,
            fence: .actorOnlyTestFixture, hooks: .init(fetchComments: { _, _ in throw CaptureFault.injected }))
        #expect(throws: (any Error).self) { try capture.capture(selectedTaskIds: [fixture.base.source.id]) }
    }

    @Test func currentFullCaptureObservesEmptyHistoryWithoutChangingLegacyCoverage() throws {
        let fixture = try TaskConsolidationCommitFixture()
        let builder = MCPReadCaptureBuilder(container: fixture.base.owner.container, fence: .actorOnlyTestFixture)
        let current = try builder.capture(ReadCaptureRequest(projectSelectors: nil,
            selection: .tasks(detail: .fullRecord),
            completeness: .selectedRead, includeComments: true))
        let evidence = try #require(current.consolidationEvidence)
        #expect(evidence.events.isEmpty && evidence.history.isEmpty)
        let request = try MCPTaskQueryRequest.parse(["taskIds": [fixture.base.source.id.uuidString],
            "detailLevel": "full", "includeComments": true, "limit": 100])
        let record = try MCPReadProjection.task(try #require(current.tasks.first), view: current, request: request)
        #expect((record["consolidationHistory"] as? [Any])?.isEmpty == true)
        let legacy = CapturedReadView(completeness: current.completeness, captureScope: current.captureScope,
            metadata: current.metadata, createdAt: current.createdAt, retentionDeadline: current.retentionDeadline,
            projects: current.projects, tasks: current.tasks, milestones: current.milestones,
            comments: current.comments,
            taskLinkGraph: current.taskLinkGraph)
        let old = try MCPReadProjection.task(try #require(legacy.tasks.first), view: legacy, request: request)
        #expect(old["consolidationHistory"] == nil && old["consolidationHistoryCoverage"] == nil)
    }

    @Test func sixParticipantWrapperIncludesAllLargeOriginalsOrRejectsWholeCapture() throws {
        let fixture = try TaskConsolidationCommitFixture()
        let project = try #require(fixture.base.source.project)
        var ids = [fixture.base.source.id, fixture.base.target.id, fixture.extra.id]
        for index in 4...6 {
            let task = TransitTask(name: "candidate \(index)", type: .feature, project: project,
                displayID: .permanent(index))
            task.taskDescription = String(repeating: "large original", count: 10_000)
            fixture.base.owner.context.insert(task)
            ids.append(task.id)
        }
        try fixture.base.owner.context.save()
        let capture = TaskConsolidationSavedCapture(container: fixture.base.owner.container,
            fence: .actorOnlyTestFixture)
        let complete = try capture.capture(selectedTaskIds: ids)
        #expect(complete.originals.count == 6 && complete.encodedByteCount > 500_000)
        #expect(throws: TaskLinkGraphError.self) {
            try capture.capture(selectedTaskIds: ids,
                budget: TaskLinkGraphBudget(maximumBytes: complete.encodedByteCount - 1))
        }
        #expect(try capture.capture(selectedTaskIds: ids,
            budget: TaskLinkGraphBudget(maximumBytes: complete.encodedByteCount)).originals.count == 6)
    }

}
private enum CaptureFault: Error { case injected }
#endif
