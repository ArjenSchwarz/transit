#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct TaskLinkReadCaptureBoundaryTests {
    @Test func linkOnlySavedChangeInvalidatesPersistentHistoryFence() throws {
        let owner = try diskOwner()
        let project = Project(name: "history", description: "", gitRepo: nil, colorHex: "blue")
        let source = TransitTask(name: "source", type: .feature, project: project, displayID: .permanent(1))
        owner.context.insert(project)
        owner.context.insert(source)
        try owner.context.save()
        let peer = ModelContext(owner.container)
        peer.autosaveEnabled = false
        let builder = MCPReadCaptureBuilder(container: owner.container, afterProjects: {
            peer.insert(TaskLinkOccurrence(id: UUID(), kindRawValue: "dependency", sourceTaskID: UUID(),
                                           targetTaskID: source.id, createdAt: Date()))
            try peer.save()
        })
        #expect(throws: MCPReadCaptureError.incoherentCapture) { try builder.capture(request()) }
        #expect(try owner.context.fetchCount(FetchDescriptor<TaskLinkOccurrence>()) == 1)
    }

    @Test func capturedEndpointMultiplicityRemainsInvalid() throws {
        let owner = try TestModelContainer()
        let project = Project(name: "collision", description: "", gitRepo: nil, colorHex: "blue")
        let first = TransitTask(name: "one", type: .feature, project: project, displayID: .permanent(1))
        let second = TransitTask(name: "two", type: .feature, project: project, displayID: .permanent(2))
        second.id = first.id
        owner.context.insert(project)
        owner.context.insert(first)
        owner.context.insert(second)
        try owner.context.save()
        let builder = MCPReadCaptureBuilder(container: owner.container, fence: .actorOnlyTestFixture)
        let view = try builder.capture(request())
        let graph = try #require(view.taskLinkGraph)
        #expect(graph.tasksById[first.id]?.count == 2)
        #expect(graph.assessment(for: first.id) == .invalid)
        #expect(view.tasks.count == 2)
    }

    @Test func oneFrozenExpiryInstantIsSharedByEveryAssessment() throws {
        let owner = try TestModelContainer()
        let project = Project(name: "expiry", description: "", gitRepo: nil, colorHex: "blue")
        let source = TransitTask(name: "source", type: .feature, project: project, displayID: .permanent(1))
        let target = TransitTask(name: "target", type: .feature, project: project, displayID: .permanent(2))
        source.status = .done
        let instant = Date()
        let edge = TaskLinkOccurrence(id: UUID(), kindRawValue: "dependency", sourceTaskID: source.id,
                                      targetTaskID: target.id, createdAt: instant.addingTimeInterval(-10))
        let value = TaskLinkOccurrenceValue(physicalKey: Data([1]), id: edge.id, kind: edge.kindRawValue,
            source: edge.sourceTaskID, target: edge.targetTaskID, createdAt: edge.createdAt)
        let evidence = TaskLinkRemovalEvidence(id: UUID(), edgeId: edge.id, kindRawValue: edge.kindRawValue,
            sourceTaskID: edge.sourceTaskID, targetTaskID: edge.targetTaskID, createdAt: edge.createdAt,
            occurrenceRevision: try TaskLinkGraph.occurrenceRevision(value), removedAt: instant)
        for task in [source, target] { owner.context.insert(task) }
        owner.context.insert(project)
        owner.context.insert(edge)
        owner.context.insert(evidence)
        try owner.context.save()
        let builder = MCPReadCaptureBuilder(container: owner.container, fence: .actorOnlyTestFixture)
        let view = try builder.capture(request())
        let graph = try #require(view.taskLinkGraph)
        #expect(graph.assessment(for: target.id) == .invalid)
        #expect(view.metadata.asOf == MCPRecordSnapshot.timestamp(graph.evaluationInstant))
        let later = try TaskLinkGraph.project(tasks: graph.tasks, occurrences: graph.occurrences,
            removalEvidence: graph.removalEvidence,
            evaluationInstant: instant.addingTimeInterval(TaskLinkGraph.evidenceLifetime + 1))
        #expect(later.assessment(for: target.id) == .unblocked)
        #expect(graph.assessment(for: target.id) == .invalid)
    }

    @Test func retainedGraphIndicesAndDiagnosticsAreChargedAlongsideCapture() async throws {
        let owner = try TestModelContainer()
        let builder = MCPReadCaptureBuilder(container: owner.container, fence: .actorOnlyTestFixture)
        let view = try builder.capture(request())
        let graph = try #require(view.taskLinkGraph)
        let without = CapturedReadView(completeness: view.completeness, captureScope: view.captureScope,
            metadata: view.metadata, createdAt: view.createdAt, retentionDeadline: view.retentionDeadline,
            projects: view.projects, tasks: view.tasks, milestones: view.milestones, comments: view.comments)
        let metadata = try JSONEncoder().encode(view.metadata)
        let capsule = MCPPreparedReadCapture(view: view, frozenMetadataBytes: metadata)
        let legacy = MCPPreparedReadCapture(view: without, frozenMetadataBytes: metadata)
        let coordinator = MCPReadCoordinator()
        let bytes = await coordinator.execute(timeout: Data("timeout".utf8), busy: Data("busy".utf8)) { operation in
            let response: Data
            do {
                let delta = try MCPPortfolioCaptureCharge.bytes(capsule, operation: operation)
                    - MCPPortfolioCaptureCharge.bytes(legacy, operation: operation)
                response = Data(String(delta).utf8)
            } catch { response = Data(String(describing: error).utf8) }
            return PreparedReadResult(encodedResponse: response, publications: [],
                publicationErrors: PreencodedPublicationErrors(busy: Data(), expired: Data(), capacity: Data()))
        }
        #expect(bytes == Data(String(graph.retainedBytes).utf8))
        #expect(graph.retainedBytes > 0)
        for _ in 0..<100 where coordinator.unfinishedCount != 0 {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(coordinator.unfinishedCount == 0)
    }

    private func request() -> ReadCaptureRequest {
        ReadCaptureRequest(projectSelectors: nil, selection: .portfolio, completeness: .completePortfolio,
                           includeComments: false)
    }

    private func diskOwner() throws -> TestModelContainer {
        let baseline = try TestModelContainer()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("T1734GraphFence-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        let config = ModelConfiguration("T1734GraphFence", schema: baseline.container.schema,
                                        url: root.appendingPathComponent("graph.store"), cloudKitDatabase: .none)
        return try TestModelContainer(schema: baseline.container.schema, configurations: [config])
    }
}
#endif
