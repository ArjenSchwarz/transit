#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit
@MainActor @Suite(.serialized)
struct TaskConsolidationApplyTests {
    @Test func retainedPreviewCommitsOneOwnedGroupAndReplaysAfterClear() async throws {
        let fixture = try ConsolidationReviewedCommitFixture()
        let reference = try await fixture.previewApply()
        let before = try fixture.capture()
        let result = await fixture.apply(reference)
        let envelope = try fixture.decode(result)
        #expect(envelope["outcome"] as? String == "committed")
        #expect(fixture.preview.base.observation.commitSaves == 1)
        let after = try fixture.capture()
        let operation = try #require(after.events.first?.operationId)
        let apply = try TaskConsolidationHistoryCodec.history(after.events, operationId: operation).apply
        #expect(apply.reason == "reviewed work" && apply.createdOccurrences.count == 2)
        #expect(after.originals.first { $0.id == fixture.survivor }?.fields.description == "merged detail")
        #expect((envelope["mappings"] as? [[String: Any]])?.count == 3)
        for original in after.originals {
            #expect(apply.appliedRevisions[original.id.uuidString] == original.revision)
            let prior = try #require(before.originals.first { $0.id == original.id })
            if original.id != fixture.survivor {
                #expect(original.fields.description == prior.fields.description)
                #expect(original.fields.metadataJSON == prior.fields.metadataJSON)
                #expect(original.fields.statusRawValue == "abandoned")
            } else {
                #expect(original.fields.statusRawValue == prior.fields.statusRawValue)
                #expect(original.fields.lastStatusChangeDate == prior.fields.lastStatusChangeDate)
                #expect(original.fields.completionDate == prior.fields.completionDate)
            }
        }
        let savedOperationRevision = try TaskConsolidationHistoryCodec.revision(after.events)
        #expect(envelope["operationRevision"] as? String == savedOperationRevision)
        fixture.preview.store.clear()
        let replay = await fixture.apply(reference)
        #expect(replay.content.first?.text == result.content.first?.text)
        #expect(fixture.preview.base.observation.commitSaves == 1)
    }
    @Test(arguments: ["ack", "revision", "identity", "clear", "scope"])
    func exactAcknowledgedScopeAndReferenceAreRequired(fault: String) async throws {
        let fixture = try ConsolidationReviewedCommitFixture(scopeFault: fault == "scope")
        var reference = try await fixture.previewApply()
        let before = try fixture.capture()
        if fault == "ack" { reference["preservationAcknowledged"] = false }
        if fault == "revision" { reference["reviewRevision"] = "p1:" + String(repeating: "b", count: 64) }
        if fault == "identity" { reference["reviewId"] = UUID().uuidString }
        if fault == "clear" { fixture.preview.store.clear() }
        #expect(try fixture.decode(await fixture.apply(reference))["outcome"] as? String == "rejected")
        #expect(try ConsolidationPreviewFixture.sameSavedOriginals(before.originals, fixture.capture().originals))
        #expect(try fixture.capture().events.isEmpty && fixture.preview.base.observation.commitSaves == 0)
    }
    @Test(arguments: ["description", "comment", "incidence", "canonical", "project", "project-collision"])
    func anyChangedSavedDependencyRejectsWholeApply(fault: String) async throws {
        let fixture = try ConsolidationReviewedCommitFixture()
        let reference = try await fixture.previewApply()
        try fixture.changeSavedEvidence(fault)
        let before = try fixture.capture()
        let result = await fixture.apply(reference)
        #expect(try fixture.decode(result)["outcome"] as? String == "rejected")
        #expect(try ConsolidationPreviewFixture.sameSavedOriginals(before.originals, fixture.capture().originals))
        #expect(try fixture.capture().events.isEmpty && fixture.preview.base.observation.commitSaves == 0)
    }
    @Test(arguments: ["name", "status"])
    func unrelatedSavedTaskChangesDoNotInvalidateReviewedApply(field: String) async throws {
        let fixture = try ConsolidationReviewedCommitFixture()
        let unrelated = try fixture.seedUnrelated()
        let reference = try await fixture.previewApply()
        try fixture.changeUnrelated(unrelated, field: field)
        #expect(try fixture.decode(await fixture.apply(reference))["outcome"] as? String == "committed")
    }
    @Test func requiredDependencyStatusStillInvalidatesReviewedAuthority() async throws {
        let fixture = try ConsolidationReviewedCommitFixture()
        let blocker = try fixture.seedUnrelated()
        let context = fixture.preview.base.base.owner.context
        context.insert(TaskLinkOccurrence(id: UUID(), kindRawValue: "dependency", sourceTaskID: blocker,
            targetTaskID: fixture.survivor, createdAt: Date(timeIntervalSinceReferenceDate: 33)))
        try context.save()
        let reference = try await fixture.previewApply()
        let before = try fixture.capture()
        try fixture.changeUnrelated(blocker, field: "status")
        let after = try fixture.capture()
        #expect(before.originals.map(\.revision) == after.originals.map(\.revision))
        #expect(try fixture.decode(await fixture.apply(reference))["outcome"] as? String == "rejected")
    }
    @Test func onlyOneCompetingKeyCanApplyTheSameRetainedReview() async throws {
        let fixture = try ConsolidationReviewedCommitFixture()
        _ = try await fixture.previewApply()
        async let left = fixture.applyLast(key: "first-reviewed-apply")
        async let right = fixture.applyLast(key: "second-reviewed-apply")
        let outcomes = try await [left, right].map { try fixture.decode($0)["outcome"] as? String ?? "missing" }
        #expect(outcomes.sorted() == ["committed", "rejected"])
        #expect(fixture.preview.base.observation.commitSaves == 1)
        #expect(try fixture.capture().events.count == 1)
    }
}
@MainActor final class ConsolidationReviewedCommitFixture {
    let preview: ConsolidationPreviewFixture
    let source: ConsolidationRetainedReviewSource
    let adapter: MCPConsolidationWriteAdapter
    private var lastApply: [String: Any] = [:]
    var survivor: UUID { preview.base.base.target.id }
    var candidates: [UUID] { [preview.base.base.source.id, preview.base.extra.id] }
    init(scopeFault: Bool = false) throws {
        preview = try ConsolidationPreviewFixture()
        source = ConsolidationRetainedReviewSource(container: preview.base.base.owner.container,
            store: preview.store, originScopeId: preview.scope + (scopeFault ? "-different" : ""))
        let resolver = source
        adapter = MCPConsolidationWriteAdapter(taskAllocator: preview.base.base.allocator,
            milestoneAllocator: preview.base.base.allocator,
            configuration: .init(originScopeId: preview.scope,
                reviewSource: { id, context in try resolver.resolve(id, in: context) },
                clock: { Date(timeIntervalSinceReferenceDate: 123) }))
    }
    func previewApply() async throws -> [String: Any] {
        var arguments = preview.arguments
        arguments["survivorEdits"] = ["description": "merged detail", "metadata": ["kept": "detail"]]
        let result = try preview.payload(await preview.execute(tool: "preview_task_consolidation",
            arguments: arguments))
        lastApply = ["reviewId": try #require(result["reviewId"] as? String),
                "reviewRevision": try #require(result["reviewRevision"] as? String),
                "preservationAcknowledged": true, "idempotencyKey": "reviewed-apply"]
        return lastApply
    }
    func applyLast(key: String) async -> MCPToolResult {
        var arguments = lastApply
        arguments["idempotencyKey"] = key
        return await apply(arguments)
    }
    func apply(_ arguments: [String: Any]) async -> MCPToolResult {
        await preview.base.coordinator.execute(tool: "consolidate_tasks", arguments: arguments,
            batchPolicy: adapter.policy())
    }
    func capture() throws -> ConsolidationSavedEvidence { try preview.capture() }
    func decode(_ result: MCPToolResult) throws -> [String: Any] { try preview.base.base.decode(result) }
    func seedUnrelated() throws -> UUID {
        let context = preview.base.base.owner.context
        let task = TransitTask(name: "unrelated", type: .feature,
            project: try #require(preview.base.base.source.project), displayID: .permanent(42))
        context.insert(task)
        try context.save()
        return task.id
    }
    func changeUnrelated(_ id: UUID, field: String) throws {
        let owner = try preview.base.base.observer()
        let task = try preview.base.base.task(id, in: owner.context)
        if field == "name" { task.name = "later unrelated name" } else { task.statusRawValue = "done" }
        try owner.context.save()
    }
    func changeSavedEvidence(_ fault: String) throws {
        let observer = try preview.base.base.observer()
        let context = observer.context
        let task = try preview.base.base.task(candidates[0], in: context)
        switch fault {
        case "description": task.taskDescription = "later saved content"
        case "comment":
            context.insert(Comment(content: "later comment", authorName: "fixture", isAgent: true, task: task))
        case "incidence", "canonical":
            context.insert(TaskLinkOccurrence(id: UUID(),
                kindRawValue: fault == "canonical" ? "duplicate" : "association",
                sourceTaskID: fault == "canonical" ? survivor : candidates[0], targetTaskID: candidates[1],
                    createdAt: Date(timeIntervalSinceReferenceDate: 111)))
        case "project":
            let project = Project(name: "other", description: "", gitRepo: nil, colorHex: "red")
            context.insert(project)
            task.project = project
        default:
            let project = Project(name: "collision", description: "", gitRepo: nil, colorHex: "red")
            project.id = try #require(task.project?.id)
            context.insert(project)
        }
        try context.save()
    }
}
#endif
