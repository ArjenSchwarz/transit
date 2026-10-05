#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

/// Owns disk storage, UI context and retry directory for the batch safety suite.
/// Production guard files are never opened by these fixtures.
@MainActor final class MCPBatchTaskSafetyFixture {
    enum Fault: Error { case injected }

    let directory: URL
    let storeURL: URL
    let owner: TestModelContainer
    let services: MCPWriteCommandServices
    let project: Project
    let target: TransitTask
    let pendingDeletion: TransitTask
    let clock = Date(timeIntervalSince1970: 1_800_000_000)
    var coordinator: MCPWriteCoordinator!
    var saves: [MCPWriteCoordinator.SaveStage] = []
    var recoveryCalls = 0
    var identityCalls = 0
    var failingStage: MCPWriteCoordinator.SaveStage?
    private var pendingReceiptEvidence: [UUID: String]?

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("T2384BatchSafety-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        print("T2384_BATCH_SAFETY_DIRECTORY=" + directory.path)
        storeURL = directory.appendingPathComponent("safety.store")
        owner = try Self.diskOwner(at: storeURL)
        project = Project(name: "Saved project", description: "", gitRepo: nil, colorHex: "#112233")
        target = TransitTask(name: "Saved target", type: .feature, project: project, displayID: .permanent(1))
        pendingDeletion = TransitTask(
            name: "Saved deletion", type: .feature, project: project, displayID: .permanent(2))
        owner.context.insert(project)
        owner.context.insert(target)
        owner.context.insert(pendingDeletion)
        try owner.context.save()
        let allocator = DisplayIDAllocator(store: InMemoryCounterStore(), isCloudSyncActive: false)
        services = MCPWriteCommandServices(
            tasks: TaskService(modelContext: owner.context, displayIDAllocator: allocator),
            projects: ProjectService(modelContext: owner.context),
            comments: CommentService(modelContext: owner.context),
            milestones: MilestoneService(modelContext: owner.context, displayIDAllocator: allocator),
            context: owner.context)
        installCoordinator()
    }

    static func diskOwner(at url: URL) throws -> TestModelContainer {
        let schema = Schema([Project.self, TransitTask.self, Comment.self, Milestone.self,
                             SyncHeartbeat.self, MCPWriteReceipt.self])
        let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        let result = try TestModelContainer(schema: schema, configurations: [configuration])
        result.context.autosaveEnabled = false
        return result
    }

    func installCoordinator(
        preparation: @escaping @MainActor (MCPWriteCommand) async throws -> Void = { _ in }
    ) {
        coordinator = nil
        let fixedClock = clock
        coordinator = MCPWriteCoordinator(
            services: services, sidecarDirectory: directory.appendingPathComponent("retry"),
            persistence: PersistenceAvailability(), clock: { fixedClock },
            save: { [weak self] context, stage in
                guard let self else { throw Fault.injected }
                saves.append(stage)
                if stage == failingStage { throw Fault.injected }
                try context.save()
            }, preparationHook: preparation,
            recoveryHook: { [weak self] in self?.recoveryCalls += 1 })
    }

    func arguments(key: String = "item", name: String = "Committed target") throws -> [String: Any] {
        ["taskId": target.id.uuidString, "name": name, "idempotencyKey": key,
         "expectedRevision": try MCPRecordSnapshot.task(target, in: owner.context).revision]
    }

    // RED seam: the optional batch policy and saved-context factory are task 2
    // interfaces, not substitutes for T2383's still-undelivered result API.
    func policy(fetchFailure: Bool = false) -> MCPBatchWritePolicy {
        MCPBatchWritePolicy(validateBeforeApply: { [weak self] command, context in
            guard let self else { throw Fault.injected }
            identityCalls += 1
            if fetchFailure { throw Fault.injected }
            try MCPBatchWritePolicy().validateBeforeApply(command, context)
        })
    }

    func execute(_ arguments: [String: Any], fetchFailure: Bool = false) async -> MCPToolResult {
        await coordinator.execute(tool: "update_task", arguments: arguments,
                                  batchPolicy: policy(fetchFailure: fetchFailure))
    }

    func decode(_ result: MCPToolResult) throws -> [String: Any] {
        let text = try #require(result.content.first?.text)
        return try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    func receipt(key: String = "item") throws -> MCPWriteReceipt {
        try #require(owner.context.fetch(FetchDescriptor<MCPWriteReceipt>()).first { $0.key == key })
    }

    func guardFiles() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: directory.appendingPathComponent("retry/guards"), includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.sorted { $0.path < $1.path }
    }

    func guardBytes() throws -> [String: Data] {
        // Include modification time: rewriting identical expiry bytes is also
        // forbidden, so byte equality alone cannot prove read-only replay.
        try Dictionary(uniqueKeysWithValues: guardFiles().map { file in
            var evidence = try Data(contentsOf: file)
            let modified = try file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            evidence.append(Data(String(reflecting: modified).utf8))
            return (file.lastPathComponent, evidence)
        })
    }

    func durableReceiptEvidence() throws -> [UUID: String] {
        let durableOwner = try Self.diskOwner(at: storeURL)
        return try Dictionary(uniqueKeysWithValues:
            durableOwner.context.fetch(FetchDescriptor<MCPWriteReceipt>()).map { receipt in
                let fields: [String] = [
                    receipt.localScopeID, receipt.tool, receipt.key, String(receipt.formatVersion),
                    receipt.requestJSON, receipt.stateRawValue, String(reflecting: receipt.acceptedAt),
                    String(reflecting: receipt.completedAt), String(reflecting: receipt.expiresAt),
                    String(reflecting: receipt.resultJSON), String(reflecting: receipt.resultIsError)
                ]
                return (receipt.id, String(reflecting: fields))
            })
    }

    func makePendingEdits() throws -> TransitTask {
        pendingReceiptEvidence = try durableReceiptEvidence()
        target.name = "UI unsaved edit"
        owner.context.delete(pendingDeletion)
        let inserted = TransitTask(name: "UI unsaved insert", type: .feature,
                                   project: project, displayID: .permanent(3))
        owner.context.insert(inserted)
        return inserted
    }

    func assertPendingPreserved(
        _ inserted: TransitTask, savedTargetName: String, expectedAutosave: Bool = false
    ) throws {
        #expect(try durableReceiptEvidence() == #require(pendingReceiptEvidence))
        #expect(owner.context.hasChanges)
        #expect(owner.context.autosaveEnabled == expectedAutosave)
        #expect(target.name == "UI unsaved edit")
        #expect(owner.context.insertedModelsArray.contains { $0.persistentModelID == inserted.persistentModelID })
        #expect(owner.context.deletedModelsArray.contains {
            $0.persistentModelID == pendingDeletion.persistentModelID
        })
        let durableOwner = try Self.diskOwner(at: storeURL)
        let durable = try durableOwner.context.fetch(FetchDescriptor<TransitTask>())
        #expect(durable.first { $0.id == target.id }?.name == savedTargetName)
        #expect(durable.contains { $0.id == pendingDeletion.id })
        #expect(!durable.contains { $0.id == inserted.id })
    }

    func resetSpies() {
        saves = []
        recoveryCalls = 0
        identityCalls = 0
    }
}

/// Bounded wait avoids wedging the suite if admission/preparation changes.
actor MCPBatchSafetyPreparationGate {
    private var started = false
    private var released = false
    private var continuation: CheckedContinuation<Void, Never>?

    func park() async {
        started = true
        if !released { await withCheckedContinuation { continuation = $0 } }
    }

    func waitForStart() async -> Bool {
        let deadline = ContinuousClock.now + .seconds(10)
        while !started && ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
        return started
    }

    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}
#endif
