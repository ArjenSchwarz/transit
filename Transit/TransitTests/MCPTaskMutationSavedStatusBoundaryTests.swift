#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct MCPTaskMutationSavedStatusBoundaryTests {
    @Test
    func unknownSavedStatusUsesServiceIdeaFallback() throws {
        let owner = try TestModelContainer()
        owner.context.autosaveEnabled = false
        let project = Project(name: "Status parity project", description: "", gitRepo: nil, colorHex: "#112233")
        owner.context.insert(project)
        let task = TransitTask(name: "Saved unknown status", type: .feature, project: project, displayID: .provisional)
        task.statusRawValue = "unknown-saved-status"
        let fixed = Date(timeIntervalSince1970: 1_700_000_000)
        task.lastStatusChangeDate = fixed
        task.completionDate = fixed
        owner.context.insert(task)
        try owner.context.save()
        #expect(task.status == .idea)
        let service = TaskService(modelContext: owner.context,
            displayIDAllocator: DisplayIDAllocator(store: InMemoryCounterStore(), isCloudSyncActive: false))
        let comment = try service.updateStatus(task: task, to: .idea, comment: nil, commentAuthor: nil,
            commentService: CommentService(modelContext: owner.context), save: false)
        #expect(comment == nil && task.statusRawValue == "unknown-saved-status")
        #expect(task.lastStatusChangeDate == fixed && task.completionDate == fixed)
        #expect(!owner.context.hasChanges)
        let status = try MCPTaskMutationValidation.status(currentStatus: "unknown-saved-status",
            targetStatus: "idea", comment: nil, authorName: nil)
        #expect(!status.statusChanged)
        #expect(status.lastStatusChange == .unchanged && status.completion == .unchanged)
    }

    @Test(arguments: ["task", "comment"])
    func typedRequiredReadFailuresRemainUnavailable(stage: String) throws {
        let fixture = try MCPBatchTaskPreviewFixture()
        var reads = fixture.reads()
        if stage == "task" {
            reads.tasks = { descriptor, context in
                fixture.observe(context, pending: descriptor.includePendingChanges)
                throw TaskService.Error.taskNotFound
            }
        } else {
            reads.comments = { descriptor, context in
                fixture.observe(context, pending: descriptor.includePendingChanges)
                throw MCPWriteFailure("INVALID_INPUT", "Injected required-read failure")
            }
        }
        let report = try MCPBatchTaskPreview.evaluate(fixture.request([fixture.item()]),
            container: fixture.owner.container, persistence: PersistenceAvailability(), reads: reads)
        #expect(report.entries[0].state == .unavailable)
        #expect(report.entries[0].current == nil && report.entries[0].proposedEffects == nil)
        #expect(report.isError == true)
        try fixture.assertUntouched()
    }
}
#endif
