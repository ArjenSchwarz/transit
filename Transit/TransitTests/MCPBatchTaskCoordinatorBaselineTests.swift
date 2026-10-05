#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

/// Existing protected coordinator controls run independently of the RED loop.
@MainActor @Suite(.serialized)
struct MCPBatchTaskCoordinatorBaselineTests {
    private typealias Fixture = MCPBatchTaskCoordinatorFixture

    @Test
    func terminalReplayAfterRestartIsByteExactWithoutNewComment() async throws {
        let fixture = try Fixture()
        let request = try fixture.request([fixture.item(0, operation: "add_comment")])
        let source = try await fixture.source(request.items[0])
        fixture.restart()
        let replay = try await fixture.source(request.items[0])
        #expect(replay.originalText == source.originalText && replay.originalIsError == source.originalIsError)
        #expect(try fixture.durableComments().count == 1)
    }

    @Test
    func transientStoreBusyRetainsSameRequestRetryWithoutAcceptingKey() async throws {
        let fixture = try Fixture()
        let request = try fixture.request([fixture.item(0)])
        let blocked = MCPWriteCoordinator(services: fixture.services,
            sidecarDirectory: fixture.directory.appendingPathComponent("keys"), persistence: PersistenceAvailability())
        let result = await blocked.execute(tool: request.items[0].operation,
            arguments: request.items[0].command.arguments)
        let value = try MCPJSONDocument.parse(result.content[0].text).value
        #expect(field("outcome", value) == .string("rejected"))
        #expect(field("accepted", value) == .boolean(false))
        #expect(field("retryAction", value) == .string("retry_same_request"))
        #expect(try fixture.owner.context.fetch(FetchDescriptor<MCPWriteReceipt>()).isEmpty)
        fixture.restart()
        let source = try await fixture.source(request.items[0])
        #expect(field("outcome", source.document?.value) == .string("committed"))
    }

    @Test
    func sharedKeyConcurrentSubmissionUsesExistingInProgressAndReplay() async throws {
        let fixture = try Fixture()
        let request = try fixture.request([fixture.item(0, operation: "add_comment")])
        let gate = MCPBatchTaskCoordinatorGate()
        fixture.preparation = { _ in await gate.park() }
        let first = Task { @MainActor in try await fixture.source(request.items[0]) }
        guard await gate.waitForStart() else {
            await gate.release()
            _ = try await first.value
            Issue.record("Existing coordinator failed to reach bounded preparation gate")
            return
        }
        let competing: MCPResultSource
        do { competing = try await fixture.source(request.items[0]) } catch {
            await gate.release()
            _ = try await first.value
            throw error
        }
        #expect(field("outcome", competing.document?.value) == .string("in_progress"))
        #expect(field("retryAction", competing.document?.value) == .string("retry_same_request"))
        await gate.release()
        let committed = try await first.value
        let replay = try await fixture.source(request.items[0])
        #expect(replay.originalText == committed.originalText)
        #expect(try fixture.durableComments().count == 1)
    }

    @Test
    func unresolvedAcceptedOriginalKeyRetryRecoversRejectionWithoutApplying() async throws {
        let fixture = try Fixture()
        let request = try fixture.request([fixture.item(0)])
        fixture.preparation = { [unowned fixture] _ in fixture.tasks[0].name = "Pending accepted UI edit" }
        let stop = try await fixture.source(request.items[0], batchPolicy: MCPBatchWritePolicy())
        #expect(field("outcome", stop.document?.value) == .string("uncertain"))
        #expect(field("accepted", stop.document?.value) == .boolean(true))
        #expect(field("retryAction", stop.document?.value) == .string("reconcile"))
        try fixture.owner.context.save() // Independent owner action; never the batch loop.
        fixture.restart()
        let retry = try await fixture.source(request.items[0])
        #expect(field("outcome", retry.document?.value) == .string("rejected"))
        #expect(field("retryAction", retry.document?.value) == .string("new_request_new_key"))
        #expect(try fixture.durableTasks().first { $0.id == fixture.tasks[0].id }?.taskDescription == nil)
    }

    @Test
    func differentIsolatedLocalStoresDoNotShareRetryNamespace() async throws {
        let first = try Fixture()
        let second = try Fixture()
        let firstRequest = try first.request([first.item(0, operation: "add_comment")])
        let secondRequest = try second.request([second.item(0, operation: "add_comment")])
        #expect(firstRequest.items[0].command.key == secondRequest.items[0].command.key)
        let firstSource = try await first.source(firstRequest.items[0])
        let secondSource = try await second.source(secondRequest.items[0])
        #expect(field("outcome", firstSource.document?.value) == .string("committed"))
        #expect(field("outcome", secondSource.document?.value) == .string("committed"))
        #expect(try first.durableComments().count == 1 && second.durableComments().count == 1)
    }

    @Test(arguments: ["expiry", "receipt"])
    func missingRetentionEvidenceWhileDirtyNeverProvesNoEffect(missing: String) async throws {
        let fixture = try Fixture()
        let request = try fixture.request([fixture.item(0, operation: "add_comment")])
        _ = try await fixture.source(request.items[0])
        let receipt = try #require(try fixture.owner.context.fetch(FetchDescriptor<MCPWriteReceipt>()).first)
        if missing == "expiry" { receipt.expiresAt = nil } else { fixture.owner.context.delete(receipt) }
        try fixture.owner.context.save()
        fixture.tasks[0].name = "Pending retention check"
        let source = try await fixture.source(request.items[0], batchPolicy: MCPBatchWritePolicy())
        #expect(field("outcome", source.document?.value) == .string("uncertain"))
        #expect(field("retryAction", source.document?.value) == .string("reconcile"))
        #expect(fixture.owner.context.hasChanges && fixture.tasks[0].name == "Pending retention check")
        #expect(try fixture.durableComments().count == 1)
    }

    @Test
    func retainedRejectionReplaysExactlyUntilReviewedFreshKeyCorrection() async throws {
        let fixture = try Fixture()
        let bad = try fixture.item(0, changes: ["priority": "invalid"])
        let request = try fixture.request([bad])
        let rejected = try await fixture.source(request.items[0])
        let replay = try await fixture.source(request.items[0])
        #expect(field("outcome", rejected.document?.value) == .string("rejected"))
        #expect(replay.originalText == rejected.originalText && replay.originalIsError == true)
        #expect(field("retryAction", rejected.document?.value) == .string("new_request_new_key"))
        var corrected = bad
        var arguments = try #require(corrected["arguments"] as? [String: Any])
        arguments["priority"] = "high"
        arguments["idempotencyKey"] = "task9.baseline.reviewed.correction"
        corrected["arguments"] = arguments
        let fixedRequest = try fixture.request([corrected])
        let fixed = try await fixture.source(fixedRequest.items[0])
        #expect(field("outcome", fixed.document?.value) == .string("committed"))
    }

    private func field(_ name: String, _ value: MCPJSONValue?) -> MCPJSONValue? {
        MCPBatchTaskResultFixtures.field(name, in: value)
    }
}

actor MCPBatchTaskCoordinatorGate {
    private var parked: CheckedContinuation<Void, Never>?
    private var started = false
    private var released = false

    func park() async {
        started = true
        guard !released else { return }
        await withCheckedContinuation { parked = $0 }
    }

    func waitForStart() async -> Bool {
        for _ in 0..<200 {
            if started { return true }
            do { try await Task.sleep(for: .milliseconds(10)) } catch { return false }
        }
        return false
    }

    func release() {
        released = true
        parked?.resume()
        parked = nil
    }
}
#endif
