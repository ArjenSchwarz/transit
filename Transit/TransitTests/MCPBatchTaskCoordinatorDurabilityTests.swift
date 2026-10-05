#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct MCPBatchTaskCoordinatorDurabilityTests {
    private typealias Fixture = MCPBatchTaskCoordinatorFixture
    private typealias Sequence = MCPBatchTaskCoordinatorSequenceFixtures

    private func run(_ request: MCPBatchTaskRequest, fixture: Fixture) async throws -> MCPBatchTaskCoordinator.Report {
        let batch = MCPBatchTaskCoordinator(preparedResponse: try Sequence.prepared(request), executor: {
            try await fixture.execution($0)
        })
        return try await batch.run(request)
    }

    @Test
    func canonicalDescriptionPrecedesDistinctReasonClosures() async throws {
        let fixture = try Fixture()
        let request = try fixture.request([fixture.item(0), fixture.item(1, operation: "update_task_status"),
                                          fixture.item(2, operation: "update_task_status")])
        let report = try await run(request, fixture: fixture)
        #expect(report.summary == "all_committed" && report.confirmedCommittedCount == 3)
        let saved = try fixture.durableTasks()
        #expect(saved.first { $0.id == fixture.tasks[0].id }?.taskDescription == "Canonical description")
        #expect(saved.filter { $0.status == .done }.count == 2)
        let comments = try fixture.durableComments()
        #expect(comments.count == 2 && Set(comments.map(\.id)).count == 2)
        #expect(Set(comments.compactMap { $0.task?.id }) == Set(fixture.tasks.dropFirst().map(\.id)))
        #expect(comments.allSatisfy { $0.content == "Duplicate of canonical" && $0.isAgent })
    }

    @Test(arguments: ["stale", "ambiguous"])
    func freshLaterIdentityOrRevisionFailurePreservesCanonicalPrefix(scenario: String) async throws {
        let fixture = try Fixture()
        let request = try fixture.request([fixture.item(0), fixture.item(1, operation: "update_task_status")])
        if scenario == "stale" { fixture.tasks[1].name = "Saved later edit" } else {
            let duplicate = TransitTask(name: "Duplicate identity", type: .feature,
                project: fixture.project, displayID: .provisional)
            duplicate.id = fixture.tasks[1].id
            fixture.owner.context.insert(duplicate)
        }
        try fixture.owner.context.save()
        let report = try await run(request, fixture: fixture)
        #expect(report.summary == "stopped" && report.confirmedCommittedCount == 1)
        let source = try #require(report.entries[1].originalResult)
        #expect(code(source) == (scenario == "stale" ? "REVISION_CONFLICT" : "DUPLICATE_TASK_IDENTIFIER"))
        #expect(try fixture.durableComments().isEmpty)
        #expect(try fixture.durableTasks().first { $0.id == fixture.tasks[0].id }?.taskDescription
                == "Canonical description")
    }

    @Test(arguments: ["priority", "milestone", "author", "content"])
    func domainFailuresStopWithoutErasingEarlierReceipt(field: String) async throws {
        let fixture = try Fixture()
        let operation = field == "author" ? "update_task_status" : (field == "content" ? "add_comment" : "update_task")
        let changes: [String: Any]
        switch field {
        case "priority": changes = ["priority": "invalid"]
        case "milestone": changes = ["milestoneDisplayId": 999]
        case "author": changes = ["authorName": " \n"]
        default: changes = ["content": " \n"]
        }
        let request = try fixture.request([fixture.item(0), fixture.item(1, operation: operation, changes: changes),
                                          fixture.item(2)])
        let report = try await run(request, fixture: fixture)
        #expect(report.confirmedCommittedCount == 1 && report.summary == "stopped")
        #expect(report.entries[2].state == .notAttempted)
        let source = try #require(report.entries[1].originalResult)
        let expected = field == "priority" ? "INVALID_PRIORITY" :
            (field == "milestone" ? "MILESTONE_NOT_FOUND" : "INVALID_INPUT")
        #expect(code(source) == expected)
        let receipts = try fixture.owner.context.fetch(FetchDescriptor<MCPWriteReceipt>())
        #expect(receipts.contains { $0.key == request.items[0].command.key && $0.stateRawValue == "committed" })
        #expect(!receipts.contains { $0.key == request.items[2].command.key })
    }

    @Test
    func failedStatusCommitPersistsNeitherStatusNorReason() async throws {
        let fixture = try Fixture()
        let request = try fixture.request([fixture.item(0), fixture.item(1, operation: "update_task_status")])
        let batch = MCPBatchTaskCoordinator(preparedResponse: try Sequence.prepared(request), executor: { item in
            fixture.failCommit = item.index == 1
            return try await fixture.execution(item)
        })
        let report = try await batch.run(request)
        #expect(report.confirmedCommittedCount == 1 && report.summary == "stopped")
        #expect(try fixture.durableComments().isEmpty)
        let saved = try fixture.durableTasks()
        #expect(saved.first { $0.id == fixture.tasks[1].id }?.status == .idea)
        #expect(saved.first { $0.id == fixture.tasks[0].id }?.taskDescription == "Canonical description")
    }

    @Test(arguments: ["laterEdit", "deleted"])
    func restartReplayBypassesLiveStateAndPreservesHistoricSource(scenario: String) async throws {
        let fixture = try Fixture()
        let request = try fixture.request([fixture.item(0), fixture.item(1, operation: "update_task_status")])
        let original = try await fixture.source(request.items[0])
        if scenario == "laterEdit" { fixture.tasks[0].taskDescription = "Later canonical contents" } else {
            fixture.owner.context.delete(fixture.tasks[0])
        }
        try fixture.owner.context.save()
        fixture.restart()
        let report = try await run(request, fixture: fixture)
        #expect(report.summary == "all_committed")
        #expect(report.entries[0].originalResult?.originalText == original.originalText)
        #expect(report.entries[0].originalResult?.originalIsError == original.originalIsError)
        let saved = try fixture.durableTasks().first { $0.id == request.items[0].targetTaskId }
        if scenario == "laterEdit" {
            #expect(saved?.taskDescription == "Later canonical contents")
        } else { #expect(saved == nil) }
        #expect(try fixture.durableComments().count == 1)
    }

    @Test
    func regroupingClientMappingDoesNotChangeDirectToolBinding() async throws {
        let fixture = try Fixture()
        var originalItem = try fixture.item(0)
        let direct = try fixture.request([originalItem])
        let original = try await fixture.source(direct.items[0], batchPolicy: nil)
        originalItem["itemId"] = "new caller e\u{301}"
        let regrouped = try fixture.request([fixture.item(1), originalItem])
        let report = try await run(regrouped, fixture: fixture)
        #expect(report.summary == "all_committed")
        #expect(report.entries[1].originalResult?.originalText == original.originalText)
        #expect(report.entries[1].index == 1 && report.entries[1].itemId.utf8.elementsEqual("new caller e\u{301}".utf8))
        #expect(try fixture.owner.context.fetch(FetchDescriptor<MCPWriteReceipt>()).count == 2)
    }

    @Test(arguments: ["payload", "uuidSpelling"])
    func changedOriginalArgumentsUnderRetainedKeyCannotRotateOrReapply(change: String) async throws {
        let fixture = try Fixture()
        let originalItem = try fixture.item(0)
        let originalRequest = try fixture.request([originalItem])
        _ = try await fixture.source(originalRequest.items[0])
        var changed = originalItem
        var arguments = try #require(changed["arguments"] as? [String: Any])
        if change == "payload" { arguments["description"] = "Changed plan" } else {
            arguments["taskId"] = fixture.tasks[0].id.uuidString.lowercased()
        }
        changed["arguments"] = arguments
        let report = try await run(fixture.request([changed, fixture.item(1)]), fixture: fixture)
        #expect(report.summary == "stopped" && report.confirmedCommittedCount == 0)
        #expect(code(try #require(report.entries[0].originalResult)) == "IDEMPOTENCY_KEY_REUSED")
        #expect(report.entries[1].state == .notAttempted)
        #expect(try fixture.owner.context.fetch(FetchDescriptor<MCPWriteReceipt>()).count == 1)
    }

    @Test
    func retainedRejectionNeedsCorrectedFreshKey() async throws {
        let fixture = try Fixture()
        let bad = try fixture.item(0, changes: ["priority": "invalid"])
        let rejectedRequest = try fixture.request([bad])
        let retained = try await fixture.source(rejectedRequest.items[0])
        var corrected = bad
        var arguments = try #require(corrected["arguments"] as? [String: Any])
        arguments["priority"] = "high"
        corrected["arguments"] = arguments
        let reused = try await run(fixture.request([corrected]), fixture: fixture)
        #expect(code(try #require(reused.entries[0].originalResult)) == "IDEMPOTENCY_KEY_REUSED")
        arguments["idempotencyKey"] = "task9.reviewed.correction"
        corrected["arguments"] = arguments
        let result = try await run(fixture.request([corrected]), fixture: fixture)
        #expect(result.summary == "all_committed")
        #expect(MCPBatchTaskResultFixtures.field("retryAction", in: retained.document?.value)
                == .string("new_request_new_key"))
    }

    @Test
    func expiredCommentKeyMayCreateNewEffectWithSameOriginalKey() async throws {
        let fixture = try Fixture()
        let request = try fixture.request([fixture.item(0, operation: "add_comment")])
        let original = try await fixture.source(request.items[0])
        fixture.now = fixture.now.addingTimeInterval(8 * 24 * 60 * 60)
        let report = try await run(request, fixture: fixture)
        #expect(report.summary == "all_committed")
        #expect(report.entries[0].originalKey == request.items[0].command.key)
        #expect(report.entries[0].originalResult?.originalText != original.originalText)
        #expect(try fixture.durableComments().count == 2)
    }

    @Test
    func missingReceiptWhileDirtyRequiresOriginalKeyReconciliation() async throws {
        let fixture = try Fixture()
        let request = try fixture.request([fixture.item(0, operation: "add_comment"), fixture.item(1)])
        _ = try await fixture.source(request.items[0])
        let receipt = try #require(try fixture.owner.context.fetch(FetchDescriptor<MCPWriteReceipt>()).first)
        fixture.owner.context.delete(receipt)
        try fixture.owner.context.save()
        fixture.tasks[0].name = "Pending UI edit"
        let report = try await run(request, fixture: fixture)
        #expect(report.summary == "stopped" && report.confirmedCommittedCount == 0)
        #expect(report.stop?.reason == .pendingEdits)
        let source = try #require(report.entries[0].originalResult)
        #expect(MCPBatchTaskResultFixtures.field("retryAction", in: source.document?.value) == .string("reconcile"))
        #expect(fixture.owner.context.hasChanges && fixture.tasks[0].name == "Pending UI edit")
        #expect(try fixture.durableComments().count == 1)
        #expect(report.entries[1].state == .notAttempted)
    }

    @Test
    func acceptedDirtyPreparationStopDoesNotResumeOrFlushUI() async throws {
        let fixture = try Fixture()
        let request = try fixture.request([fixture.item(0), fixture.item(1)])
        fixture.preparation = { [unowned fixture] _ in fixture.tasks[0].name = "Pending after accept" }
        let report = try await run(request, fixture: fixture)
        #expect(report.summary == "stopped" && report.stop?.reason == .pendingEdits)
        #expect(fixture.owner.context.hasChanges && fixture.tasks[0].name == "Pending after accept")
        let source = try #require(report.entries[0].originalResult)
        #expect(MCPBatchTaskResultFixtures.field("accepted", in: source.document?.value) == .boolean(true))
        #expect(MCPBatchTaskResultFixtures.field("retryAction", in: source.document?.value) == .string("reconcile"))
        #expect(report.entries[1].state == .notAttempted)
        #expect(try fixture.durableTasks().first { $0.id == fixture.tasks[0].id }?.name == "Task 0")
    }

    @Test(arguments: ["milestone", "commentCapture"])
    func realPreApplyReferenceOrCommentCaptureFailurePreservesEarlierCommit(stage: String) async throws {
        let fixture = try Fixture(faultMilestoneReads: stage == "milestone")
        let changes: [String: Any] = stage == "milestone" ? ["milestoneDisplayId": 9] : [:]
        let second = try fixture.item(1, changes: changes)
        let request = try fixture.request([fixture.item(0), second, fixture.item(2)])
        if stage == "commentCapture" {
            fixture.preparation = { [unowned fixture] command in
                if command.arguments["taskId"] as? String == fixture.tasks[1].id.uuidString {
                    _ = try MCPRecordSnapshot.task(fixture.tasks[1], incidence: []) { _ in
                        throw Fixture.Fault.injected }
                }
            }
        }
        let report = try await run(request, fixture: fixture)
        #expect(report.summary == "stopped" && report.confirmedCommittedCount == 1)
        #expect(code(try #require(report.entries[1].originalResult)) == "INTERNAL_ERROR")
        #expect(report.entries[2].state == .notAttempted)
        #expect(try fixture.durableTasks().first { $0.id == fixture.tasks[0].id }?.taskDescription
                == "Canonical description")
        #expect(try fixture.durableComments().isEmpty)
    }

    @Test
    func competingBatchUsesExistingActiveKeyAndDoesNotContinue() async throws {
        let fixture = try Fixture()
        let request = try fixture.request([fixture.item(0, operation: "add_comment"), fixture.item(1)])
        let gate = MCPBatchTaskCoordinatorGate()
        fixture.preparation = { _ in await gate.park() }
        let first = Task { @MainActor in try await fixture.source(request.items[0]) }
        guard await gate.waitForStart() else {
            await gate.release()
            _ = try await first.value
            Issue.record("Existing coordinator failed to reach bounded preparation gate")
            return
        }
        let report: MCPBatchTaskCoordinator.Report
        do { report = try await run(request, fixture: fixture) } catch {
            await gate.release()
            _ = try await first.value
            throw error
        }
        await gate.release()
        _ = try await first.value
        #expect(report.summary == "stopped" && report.confirmedCommittedCount == 0)
        #expect(MCPBatchTaskResultFixtures.field("outcome", in: report.entries[0].originalResult?.document?.value)
                == .string("in_progress"))
        #expect(report.entries[1].state == .notAttempted)
        #expect(try fixture.durableComments().count == 1)
    }

    private func code(_ source: MCPResultSource) -> String? {
        let error = MCPBatchTaskResultFixtures.field("error", in: source.document?.value)
        guard case .string(let code) = MCPBatchTaskResultFixtures.field("code", in: error) else { return nil }
        return code
    }
}
#endif
