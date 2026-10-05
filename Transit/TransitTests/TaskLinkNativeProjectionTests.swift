import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct TaskLinkNativeProjectionTests {
    @Test func savedRelationshipLabelsIgnoreBothSourceAndEndpointDrafts() throws {
        let fixture = try Fixture()
        fixture.source.name = "source draft"
        fixture.target.name = "endpoint draft"
        let detail = try TaskLinkService(container: fixture.owner.container).savedDetail(for: fixture.source.id)
        #expect(detail.source.name == "source")
        #expect(detail.graph.tasksById[fixture.target.id]?.first?.name == "target")
        #expect(fixture.owner.context.hasChanges)
    }

    @Test(arguments: ["missing", "ambiguous", "unsaved"])
    func navigationRequiresExactlyOneSavedDestination(fault: String) throws {
        let fixture = try Fixture()
        let id: UUID
        switch fault {
        case "missing": id = UUID()
        case "ambiguous":
            id = fixture.target.id
            let duplicate = TransitTask(name: "collision", type: .feature, project: fixture.project,
                                        displayID: .permanent(3))
            duplicate.id = id
            fixture.owner.context.insert(duplicate)
            try fixture.owner.context.save()
        default:
            let pending = TransitTask(name: "not saved", type: .feature, project: fixture.project,
                                      displayID: .permanent(3))
            fixture.owner.context.insert(pending)
            id = pending.id
        }
        #expect(try TaskLinkNavigationResolver.resolve(id, in: fixture.owner.context) == nil)
    }

    @Test func uniqueDestinationKeepsExactUUIDAndUnsavedSourceIsUnavailable() throws {
        let fixture = try Fixture()
        let resolved = try #require(TaskLinkNavigationResolver.resolve(fixture.target.id, in: fixture.owner.context))
        #expect(resolved.id == fixture.target.id && resolved.id != fixture.source.id)
        let pending = TransitTask(name: "not saved", type: .feature, project: fixture.project,
                                  displayID: .permanent(3))
        fixture.owner.context.insert(pending)
        #expect(throws: TaskLinkGraphError.ambiguousIdentity) {
            try TaskLinkService(container: fixture.owner.container).savedDetail(for: pending.id)
        }
    }

    @Test(arguments: [false, true])
    func staleOrCanceledNativeRefreshCannotReplaceCurrentSelection(cancel: Bool) async throws {
        let fixture = try Fixture()
        let service = TaskLinkService(container: fixture.owner.container)
        let oldDetail = try service.savedDetail(for: fixture.source.id)
        let newDetail = try service.savedDetail(for: fixture.target.id)
        let state = TaskLinkNativeDetailState()
        let gate = Gate()
        let old = Task { await state.refresh(source: fixture.source.id) { _ in try await gate.wait() } }
        for _ in 0..<100 where gate.continuation == nil { await Task.yield() }
        try #require(gate.continuation != nil)
        if cancel { old.cancel() }
        else { await state.refresh(source: fixture.target.id) { _ in newDetail } }
        gate.continuation?.resume(returning: oldDetail)
        await old.value
        #expect(state.detail?.source.id == (cancel ? nil : fixture.target.id))
        if !cancel { #expect(state.sourceID == fixture.target.id) }
    }

    @MainActor private final class Gate {
        var continuation: CheckedContinuation<TaskLinkSavedDetail, Error>?
        func wait() async throws -> TaskLinkSavedDetail {
            try await withCheckedThrowingContinuation { continuation = $0 }
        }
    }

    @MainActor private struct Fixture {
        let owner: TestModelContainer
        let project: Project
        let source: TransitTask
        let target: TransitTask
        init() throws {
            owner = try TestModelContainer()
            owner.context.autosaveEnabled = false
            project = Project(name: "native", description: "", gitRepo: nil, colorHex: "blue")
            source = TransitTask(name: "source", type: .feature, project: project, displayID: .permanent(1))
            target = TransitTask(name: "target", type: .feature, project: project, displayID: .permanent(2))
            owner.context.insert(project)
            owner.context.insert(source)
            owner.context.insert(target)
            owner.context.insert(TaskLinkOccurrence(id: UUID(), kindRawValue: "association",
                sourceTaskID: source.id, targetTaskID: target.id, createdAt: Date()))
            try owner.context.save()
        }
    }
}
