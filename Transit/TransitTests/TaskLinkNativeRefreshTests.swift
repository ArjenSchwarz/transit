import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct TaskLinkNativeRefreshTests {
    @Test func refreshBurstCapturesLatestCompleteSavedGraphOnce() async throws {
        let owner = try TestModelContainer()
        owner.context.autosaveEnabled = false
        let project = Project(name: "native", description: "", gitRepo: nil, colorHex: "blue")
        let source = TransitTask(name: "before", type: .feature, project: project, displayID: .permanent(1))
        owner.context.insert(project)
        owner.context.insert(source)
        try owner.context.save()
        let service = TaskLinkService(container: owner.container)
        let state = TaskLinkNativeDetailState()
        await state.refresh(source: source.id) { try service.savedDetail(for: $0) }
        try #require(state.detail?.source.name == "before")
        let gates = [Gate(), Gate(), Gate()]
        var captures = 0
        var jobs: [Task<Void, Never>] = []
        for gate in gates {
            jobs.append(Task {
                await state.refresh(source: source.id, wait: { try await gate.wait() }, provider: {
                    captures += 1
                    return try service.savedDetail(for: $0)
                })
            })
            for _ in 0..<100 where gate.continuation == nil { await Task.yield() }
            try #require(gate.continuation != nil)
            #expect(state.detail == nil)
        }
        jobs[1].cancel()
        let peer = ModelContext(owner.container)
        peer.autosaveEnabled = false
        let saved = try #require(peer.fetch(FetchDescriptor<TransitTask>()).first)
        saved.name = "latest saved source"
        let unrelatedProject = Project(name: "elsewhere", description: "", gitRepo: nil, colorHex: "red")
        let unrelated = TransitTask(name: "outside", type: .feature, project: unrelatedProject,
                                    displayID: .permanent(2))
        let endpoint = TransitTask(name: "outside endpoint", type: .feature, project: unrelatedProject,
                                  displayID: .permanent(3))
        let edgeID = UUID()
        peer.insert(unrelatedProject)
        peer.insert(unrelated)
        peer.insert(endpoint)
        peer.insert(TaskLinkOccurrence(id: edgeID, kindRawValue: "association",
            sourceTaskID: unrelated.id, targetTaskID: endpoint.id, createdAt: Date()))
        try peer.save()
        for gate in gates { gate.continuation?.resume() }
        for job in jobs { await job.value }
        #expect(captures == 1)
        #expect(state.detail?.source.name == "latest saved source")
        #expect(state.detail?.graph.tasksById[unrelated.id]?.first?.name == "outside")
        #expect(state.detail?.graph.occurrences.contains { $0.id == edgeID } == true)
    }

    @Test func alreadyCanceledRefreshDoesNotInvalidateCurrentObservation() async throws {
        let owner = try TestModelContainer()
        let project = Project(name: "native", description: "", gitRepo: nil, colorHex: "blue")
        let source = TransitTask(name: "current", type: .feature, project: project, displayID: .permanent(1))
        owner.context.insert(project)
        owner.context.insert(source)
        try owner.context.save()
        let service = TaskLinkService(container: owner.container)
        let state = TaskLinkNativeDetailState()
        await state.refresh(source: source.id) { try service.savedDetail(for: $0) }
        let obsolete = Task {
            await state.refresh(source: UUID(), debounce: .seconds(60)) {
                Issue.record("Canceled request must not capture")
                return try service.savedDetail(for: $0)
            }
        }
        obsolete.cancel()
        await obsolete.value
        #expect(state.sourceID == source.id)
        #expect(state.detail?.source.name == "current")
    }

    @MainActor private final class Gate {
        var continuation: CheckedContinuation<Void, Error>?
        func wait() async throws {
            try await withCheckedThrowingContinuation { continuation = $0 }
        }
    }
}
