#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

/// Baseline controls only. No test here certifies graph-write enablement.
/// Independently opened containers observe disk saves; the original owning
/// fixture remains retained, so these are not process-closed migration tests.
@MainActor @Suite(.serialized)
struct TaskLinkCommitBoundaryTests {
    @Test func independentSavedObservationExcludesPendingGraphEdits() throws {
        let fixture = try TaskLinkCommitDiskFixture()
        fixture.source.name = "unsaved draft"
        fixture.owner.context.delete(fixture.edge)
        fixture.owner.context.insert(TaskLinkOccurrence(
            id: UUID(), kindRawValue: "dependency", sourceTaskID: fixture.target.id,
            targetTaskID: fixture.source.id, createdAt: fixture.instant))
        let observer = try fixture.observer()
        #expect(try fixture.task(fixture.source.id, in: observer.context).name == "source")
        let rows = try observer.context.fetch(FetchDescriptor<TaskLinkOccurrence>())
        #expect(rows.count == 1)
        #expect(rows.first?.id == fixture.edge.id)
        #expect(rows.first?.sourceTaskID == fixture.target.id)
        #expect(rows.first?.targetTaskID == fixture.source.id)
        #expect(rows.first?.kindRawValue == "dependency")
        #expect(rows.first?.createdAt == fixture.instant)
        #expect(try fixture.historicReceipt(in: observer.context).resultJSON == fixture.historicJSON)
        #expect(fixture.owner.context.hasChanges)
        #expect(!observer.context.hasChanges)
    }

    @Test func independentSavedObservationSeesPeerChangeAfterRegistration() throws {
        let fixture = try TaskLinkCommitDiskFixture()
        let registered = try fixture.task(fixture.target.id, in: fixture.owner.context)
        #expect(registered.statusRawValue == "done")
        let peer = try fixture.observer()
        let imported = try fixture.task(fixture.target.id, in: peer.context)
        imported.statusRawValue = "abandoned"
        try peer.context.save()
        let observer = try fixture.observer()
        #expect(try fixture.task(fixture.target.id, in: observer.context).statusRawValue == "abandoned")
        #expect(try fixture.historicReceipt(in: observer.context).requestJSON == fixture.historicRequest)
        // Registered-model auto-refresh is deliberately not assumed; the
        // future commit seam must explicitly establish authoritative saved data.
    }

    @Test(arguments: ["save", "encode"])
    func legacyCoordinatorFailurePreservesSavedDomainAndHistoricalBytes(failure: String) async throws {
        let fixture = try TaskLinkCommitDiskFixture()
        let coordinator = fixture.coordinator(save: { context, stage in
            if case .commit = stage, failure == "save" { throw TaskLinkCommitDiskFixture.Failure.injected }
            try context.save()
        }, encode: { envelope in
            if envelope["outcome"] as? String == "committed", failure == "encode" {
                throw TaskLinkCommitDiskFixture.Failure.injected
            }
            return try MCPWriteOutcome.encode(envelope)
        })
        let result = await coordinator.execute(tool: "update_task", arguments: try fixture.updateArguments())
        #expect(try fixture.decode(result)["outcome"] as? String == "rejected")
        let observer = try fixture.observer()
        #expect(try fixture.task(fixture.source.id, in: observer.context).name == "source")
        #expect(try observer.context.fetch(FetchDescriptor<TaskLinkOccurrence>()).count == 1)
        #expect(try observer.context.fetch(FetchDescriptor<TaskLinkRemovalEvidence>()).count == 1)
        let evidence = try observer.context.fetch(FetchDescriptor<TaskLinkRemovalEvidence>()).first
        #expect(evidence?.kindRawValue == "future-kind")
        #expect(evidence?.occurrenceRevision == "raw-imported-revision")
        #expect(try fixture.historicReceipt(in: observer.context).resultJSON == fixture.historicJSON)
        let key = "boundary-update"
        let receipts = try observer.context.fetch(FetchDescriptor<MCPWriteReceipt>(
            predicate: #Predicate { $0.key == key }))
        let receipt = try #require(receipts.count == 1 ? receipts.first : nil)
        #expect(receipt.stateRawValue == "rejected")
        #expect(receipt.resultIsError == true)
    }

    @Test func legacyRetainedReplayBypassesPreparationAndCommitSave() async throws {
        let fixture = try TaskLinkCommitDiskFixture()
        var commitSaves = 0
        var preparations = 0
        let coordinator = fixture.coordinator(save: { context, stage in
            if case .commit = stage { commitSaves += 1 }
            try context.save()
        }, preparation: { _ in preparations += 1 })
        let arguments = try fixture.updateArguments()
        let original = await coordinator.execute(tool: "update_task", arguments: arguments)
        #expect(try fixture.decode(original)["outcome"] as? String == "committed")
        let replay = await coordinator.execute(tool: "update_task", arguments: arguments)
        #expect(replay.content.first?.text == original.content.first?.text)
        #expect(commitSaves == 1)
        #expect(preparations == 1)
        let observer = try fixture.observer()
        #expect(try fixture.task(fixture.source.id, in: observer.context).name == "committed update")
        #expect(try fixture.historicReceipt(in: observer.context).resultJSON == fixture.historicJSON)
        // Dirty replay/clean-phase guarantees require the handed-off policy;
        // they are not imposed on the unchanged standalone coordinator.
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["T1734_TRANSACTION_DIAGNOSTIC"] == "1"))
    func primitiveTransactionEarlierObservationCanBeInvalidatedByPeerSave() throws {
        let fixture = try TaskLinkCommitDiskFixture()
        let peer = try fixture.observer()
        var validatedDone = false
        try fixture.owner.context.transaction {
            validatedDone = try fixture.task(fixture.target.id, in: fixture.owner.context).statusRawValue == "done"
            let imported = try fixture.task(fixture.target.id, in: peer.context)
            imported.statusRawValue = "abandoned"
            try peer.context.save()
            fixture.source.name = "write after earlier validation"
            try fixture.owner.context.save()
        }
        let observer = try fixture.observer()
        #expect(validatedDone)
        #expect(try fixture.task(fixture.target.id, in: observer.context).statusRawValue == "abandoned")
        #expect(try fixture.task(fixture.source.id, in: observer.context).name == "write after earlier validation")
        // A passing diagnostic is a counterexample, not an atomicity gate PASS.
        // If peer save blocks/fails, retain that evidence for mechanism review.
        // Run only in a bounded isolated parent-owned host slot with sampling.
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["T1734_TRANSACTION_ABORT_DIAGNOSTIC"] == "1"))
    func primitiveTransactionInternalSaveMustRollBackOnClosureAbort() throws {
        let fixture = try TaskLinkCommitDiskFixture()
        let markerID = UUID(), evidenceID = UUID()
        // Fixture-only marker: never an accepted production request, endpoint
        // timestamp, or retained idempotency binding.
        let marker = MCPWriteReceipt(id: markerID, localScopeID: "synthetic-transaction-probe",
            tool: "fixture-only", key: "internal-flush", requestJSON: "{\"probe\":true}",
            acceptedAt: fixture.instant)
        fixture.owner.context.insert(marker)
        try fixture.owner.context.save()
        var internalSaveReturned = false
        var sawInjectedAbort = false
        do {
            try fixture.owner.context.transaction {
                marker.stateRawValue = "fixture-flushed"
                marker.resultJSON = "{\"terminal\":true}"
                fixture.source.name = "internal flush domain"
                fixture.owner.context.delete(fixture.edge)
                fixture.owner.context.insert(TaskLinkRemovalEvidence(id: evidenceID, edgeId: fixture.edge.id,
                    kindRawValue: "dependency", sourceTaskID: fixture.target.id, targetTaskID: fixture.source.id,
                    createdAt: fixture.instant, occurrenceRevision: "fixture-probe", removedAt: fixture.instant))
                try fixture.owner.context.save()
                internalSaveReturned = true
                throw TaskLinkCommitDiskFixture.Failure.injected
            }
        } catch TaskLinkCommitDiskFixture.Failure.injected {
            sawInjectedAbort = true
        }
        try #require(internalSaveReturned && sawInjectedAbort)
        let observer = try fixture.observer()
        let rows = try observer.context.fetch(FetchDescriptor<MCPWriteReceipt>(
            predicate: #Predicate { $0.id == markerID }))
        let savedMarker = try #require(rows.count == 1 ? rows.first : nil)
        #expect(savedMarker.stateRawValue == "accepted")
        #expect(savedMarker.resultJSON == nil)
        #expect(savedMarker.requestJSON == "{\"probe\":true}")
        #expect(try fixture.task(fixture.source.id, in: observer.context).name == "source")
        let edges = try observer.context.fetch(FetchDescriptor<TaskLinkOccurrence>())
        #expect(edges.count == 1 && edges.first?.id == fixture.edge.id)
        let evidence = try observer.context.fetch(FetchDescriptor<TaskLinkRemovalEvidence>())
        #expect(!evidence.contains { $0.id == evidenceID })
        #expect(evidence.count == 1)
        #expect(try fixture.historicReceipt(in: observer.context).resultJSON == fixture.historicJSON)
        // Passing establishes abort durability only. It does not establish
        // saved-read freshness, peer exclusion, phantom protection, or success
        // atomicity. A failure disqualifies this internal-flush candidate.
    }
}

@MainActor
struct TaskLinkCommitDiskFixture {
    enum Failure: Error { case injected, ambiguous }
    let owner: TestModelContainer
    let directory: URL
    let instant = Date(timeIntervalSince1970: 1_700_000_000)
    let source: TransitTask
    let target: TransitTask
    let edge: TaskLinkOccurrence
    let allocator = DisplayIDAllocator(store: InMemoryCounterStore(), isCloudSyncActive: false)
    let historicJSON = "{\n  \"original\": \"café\", \"n\":9007199254740993\n}\n"
    let historicRequest = "{ \"original\" : true }"

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("T1734Commit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let schema = try TestModelContainer().container.schema
        let configuration = ModelConfiguration(schema: schema, url: directory.appendingPathComponent("commit.store"),
                                               cloudKitDatabase: .none)
        owner = try TestModelContainer(schema: schema, configurations: [configuration])
        owner.context.autosaveEnabled = false
        let project = Project(name: "boundary", description: "saved", gitRepo: nil, colorHex: "#123456")
        source = TransitTask(name: "source", type: .feature, project: project, displayID: .permanent(1))
        target = TransitTask(name: "target", type: .feature, project: project, displayID: .permanent(2))
        target.statusRawValue = "done"
        edge = TaskLinkOccurrence(id: UUID(), kindRawValue: "dependency", sourceTaskID: target.id,
                                  targetTaskID: source.id, createdAt: instant)
        let removal = TaskLinkRemovalEvidence(id: UUID(), edgeId: UUID(), kindRawValue: "future-kind",
                                             sourceTaskID: source.id, targetTaskID: target.id, createdAt: instant,
                                             occurrenceRevision: "raw-imported-revision", removedAt: instant)
        let historic = MCPWriteReceipt(localScopeID: "historic-local-scope", tool: "update_task",
                                       key: "historic", requestJSON: historicRequest, acceptedAt: instant)
        historic.stateRawValue = "committed"
        historic.resultJSON = historicJSON
        historic.completedAt = instant
        historic.expiresAt = instant.addingTimeInterval(604800)
        historic.resultIsError = false
        owner.context.insert(project)
        owner.context.insert(source)
        owner.context.insert(target)
        owner.context.insert(edge)
        owner.context.insert(removal)
        owner.context.insert(historic)
        try owner.context.save()
        // All owning containers stay retained; do not unlink an open SQLite store.
    }

    func observer() throws -> TestModelContainer {
        let configuration = ModelConfiguration(schema: owner.container.schema,
                                               url: directory.appendingPathComponent("commit.store"),
                                               cloudKitDatabase: .none)
        let observer = try TestModelContainer(schema: owner.container.schema, configurations: [configuration])
        observer.context.autosaveEnabled = false
        return observer
    }

    func task(_ id: UUID, in context: ModelContext) throws -> TransitTask {
        var descriptor = FetchDescriptor<TransitTask>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 2
        let matches = try context.fetch(descriptor)
        guard matches.count == 1 else { throw Failure.ambiguous }
        return matches[0]
    }

    func historicReceipt(in context: ModelContext) throws -> MCPWriteReceipt {
        let key = "historic"
        let matches = try context.fetch(FetchDescriptor<MCPWriteReceipt>(predicate: #Predicate { $0.key == key }))
        guard matches.count == 1 else { throw Failure.ambiguous }
        return matches[0]
    }

    func updateArguments() throws -> [String: Any] {
        ["taskId": source.id.uuidString, "name": "committed update", "idempotencyKey": "boundary-update",
         "expectedRevision": try MCPRecordSnapshot.task(source, in: owner.context).revision]
    }

    func decode(_ result: MCPToolResult) throws -> [String: Any] {
        let text = try #require(result.content.first?.text)
        return try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    func coordinator(
        save: @escaping @MainActor (ModelContext, MCPWriteCoordinator.SaveStage) throws -> Void,
        encode: @escaping @MainActor ([String: Any]) throws -> String = MCPWriteOutcome.encode,
        preparation: @escaping @MainActor (MCPWriteCommand) async throws -> Void = { _ in },
        recovery: @escaping @MainActor () throws -> Void = {},
        newTaskID: @escaping @MainActor () -> UUID = UUID.init
    ) -> MCPWriteCoordinator {
        let context = owner.context
        let services = MCPWriteCommandServices(
            tasks: TaskService(modelContext: context, displayIDAllocator: allocator),
            projects: ProjectService(modelContext: context), comments: CommentService(modelContext: context),
            milestones: MilestoneService(modelContext: context, displayIDAllocator: allocator), context: context)
        return MCPWriteCoordinator(services: services, sidecarDirectory: directory.appendingPathComponent("guards"),
                                   persistence: PersistenceAvailability(isFallbackStorageActive: false),
                                   save: save, encode: encode, newTaskID: newTaskID,
                                   preparationHook: preparation, recoveryHook: recovery)
    }

    func commitServices(in context: ModelContext) -> MCPWriteCommitServices {
        MCPWriteCommitServices(context: context, taskAllocator: allocator, milestoneAllocator: allocator)
    }
}
#endif
