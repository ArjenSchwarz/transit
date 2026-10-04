#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct MCPBatchTaskExecutionAdapterTests {
    private typealias Fixture = MCPBatchTaskCoordinatorFixture
    private typealias Sequence = MCPBatchTaskCoordinatorSequenceFixtures

    @Test
    func actualAdapterReplaysOriginalEvidenceWhileDirtyWithoutPendingStop() async throws {
        let fixture = try Fixture()
        let request = try fixture.request([fixture.item(0)])
        let batch = MCPBatchTaskCoordinator(preparedResponse: try Sequence.prepared(request),
            writeCoordinator: try #require(fixture.coordinator))
        let first = try await batch.run(request)
        #expect(first.summary == "all_committed")
        let original = try #require(first.entries[0].originalResult)
        fixture.tasks[1].name = "Pending UI name"
        let saves = fixture.saveStages
        let replay = try await batch.run(request)
        #expect(replay.summary == "all_committed" && replay.stop == nil)
        #expect(replay.entries[0].originalResult?.originalText.utf8.elementsEqual(original.originalText.utf8) == true)
        #expect(replay.entries[0].originalResult?.document?.originalUTF8 == original.document?.originalUTF8)
        #expect(replay.entries[0].originalResult?.originalIsError == original.originalIsError)
        #expect(fixture.tasks[1].name == "Pending UI name" && fixture.owner.context.hasChanges)
        #expect(fixture.saveStages == saves && fixture.recoveryCalls == 0)
        #expect(try fixture.durableTasks().first { $0.id == fixture.tasks[1].id }?.name == "Task 1")
    }

    @Test
    func actualAdapterFreshDirtyStopBindsPerInvocationFact() async throws {
        let fixture = try Fixture()
        let request = try fixture.request([fixture.item(0)])
        fixture.tasks[1].name = "Pending UI name"
        let batch = MCPBatchTaskCoordinator(preparedResponse: try Sequence.prepared(request),
            writeCoordinator: try #require(fixture.coordinator))
        let report = try await batch.run(request)
        #expect(report.summary == "stopped" && report.stop?.reason == .pendingEdits)
        #expect(report.confirmedCommittedCount == 0 && report.entries[0].state == .attempted)
        let source = try #require(report.entries[0].originalResult)
        #expect(source.originalIsError == true && source.originalText.contains("reconcile"))
        #expect(fixture.owner.context.hasChanges && fixture.tasks[1].name == "Pending UI name")
        #expect(fixture.saveStages.isEmpty && fixture.recoveryCalls == 0)
        #expect(try fixture.durableTasks().first { $0.id == fixture.tasks[0].id }?.taskDescription == nil)
    }

    @Test
    func localHandlerSelectsPreviewWithoutCapabilityAndRequiresItForExecute() async throws {
        let fixture = try Fixture()
        let item = try fixture.item(0)
        func value(mode: String) throws -> MCPJSONValue {
            try MCPJSONDocument.parse(JSONSerialization.data(withJSONObject:
                ["mode": mode, "items": [item]])).value
        }
        let preview = try await MCPBatchTaskHandler.handle(arguments: value(mode: "dry_run"),
            container: fixture.owner.container, persistence: PersistenceAvailability())
        guard case .preview = preview else { Issue.record("Dry run requires no prepared capability"); return }
        #expect(fixture.saveStages.isEmpty && !fixture.owner.context.hasChanges)
        do {
            _ = try await MCPBatchTaskHandler.handle(arguments: value(mode: "execute"),
                container: fixture.owner.container, persistence: PersistenceAvailability())
            Issue.record("Execute without prepared capability must fail before effects")
        } catch let error as MCPBatchTaskHandler.Error {
            guard case .executionUnavailable = error else { Issue.record("Unexpected availability error"); return }
        }
        #expect(fixture.saveStages.isEmpty && !fixture.owner.context.hasChanges)
        let request = try fixture.request([item])
        let batch = MCPBatchTaskCoordinator(preparedResponse: try Sequence.prepared(request),
            writeCoordinator: try #require(fixture.coordinator))
        let execution = try await MCPBatchTaskHandler.handle(arguments: value(mode: "execute"),
            container: fixture.owner.container, persistence: PersistenceAvailability(), coordinator: batch)
        guard case .execution(_, let report) = execution else { Issue.record("Expected execute mode"); return }
        #expect(report.summary == "all_committed" && report.confirmedCommittedCount == 1)
        #expect(report.entries[0].originalKey.utf8.elementsEqual(request.items[0].command.key.utf8))
        #expect(try fixture.durableTasks().first { $0.id == fixture.tasks[0].id }?.taskDescription ==
            "Canonical description")
    }
}
#endif
