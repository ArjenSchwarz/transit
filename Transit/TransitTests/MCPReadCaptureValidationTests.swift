#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct MCPReadCaptureValidationTests {
    nonisolated private struct Retained: MCPRetainedViewSource {
        let captured: CapturedReadView
        func view(for snapshotID: String, now: ContinuousClock.Instant) throws -> CapturedReadView {
            guard snapshotID == captured.metadata.snapshotId, now < captured.retentionDeadline else {
                throw MCPTaskQueryError(code: "SNAPSHOT_EXPIRED", message: "Retained capture expired")
            }
            return captured
        }
    }

    @Test func retainedSourceKeepsIdentityAndScopeWithoutDroppingForeignClosure() throws {
        let fixture = try TestModelContainer()
        let project = Project(name: "Selected", description: "", gitRepo: nil, colorHex: "blue")
        let foreign = Project(name: "Foreign", description: "", gitRepo: nil, colorHex: "red")
        let task = TransitTask(name: "Saved", type: .feature, project: project, displayID: .permanent(63))
        let endpoint = TransitTask(name: "Identity", type: .bug, project: foreign, displayID: .permanent(64))
        let comment = Comment(content: "Evidence", authorName: "A", isAgent: true, task: task)
        fixture.context.insert(project)
        fixture.context.insert(foreign)
        fixture.context.insert(task)
        fixture.context.insert(endpoint)
        fixture.context.insert(comment)
        try fixture.context.save()
        let captured = try MCPReadCaptureBuilder(container: fixture.container, fence: .actorOnlyTestFixture)
            .capture(ReadCaptureRequest(projectSelectors: [.id(project.id)], selection: .portfolio,
                                        completeness: .completePortfolio, includeComments: false))
        let source = Retained(captured: captured)
        task.name = "After"
        comment.content = "After"
        try fixture.context.save()
        let view = try source.view(for: captured.metadata.snapshotId, now: .now)
        try MCPReadCaptureValidation.validateReusableCapture(view)
        #expect(view.metadata.snapshotId == captured.metadata.snapshotId)
        #expect(view.metadata.asOf == captured.metadata.asOf)
        #expect(view.tasks.count == 2)
        let ownKey = try #require(view.projects.first { $0.id == project.id }?.physicalKey)
        let foreignKey = try #require(view.projects.first { $0.id == foreign.id }?.physicalKey)
        try MCPReadCaptureValidation.requireScope(view, projectKeys: [ownKey])
        #expect(throws: MCPTaskQueryError.self) {
            try MCPReadCaptureValidation.requireScope(view, projectKeys: [foreignKey])
        }
        let request = try MCPTaskQueryRequest.parse(["detailLevel": "full", "includeComments": false, "limit": 100])
        let records = try MCPReadProjection.tasks(view, request: request, arguments: [:])
        #expect(records.count == 1 && records[0]["name"] as? String == "Saved")
        #expect(records[0]["revision"] as? String == captured.tasks.first { $0.id == task.id }?.revision)
        let noEvidence = replacing(view, tasks: view.tasks, comments: [])
        #expect(throws: MCPReadCaptureError.incoherentCapture) {
            try MCPReadCaptureValidation.validateReusableCapture(noEvidence)
        }
    }

    @Test func selectedSummaryCannotPretendToBeCompleteCanonicalPortfolio() throws {
        let fixture = try TestModelContainer()
        let project = Project(name: "P", description: "", gitRepo: nil, colorHex: "blue")
        fixture.context.insert(project)
        fixture.context.insert(TransitTask(name: "Task", type: .feature, project: project, displayID: .permanent(63)))
        try fixture.context.save()
        let builder = MCPReadCaptureBuilder(container: fixture.container, fence: .actorOnlyTestFixture)
        let complete = try builder.capture(ReadCaptureRequest(projectSelectors: nil, selection: .portfolio,
                                                              completeness: .completePortfolio, includeComments: false))
        let summary = try builder.capture(ReadCaptureRequest(projectSelectors: nil,
                                                             selection: .tasks(detail: .summary),
                                                             completeness: .selectedRead,
                                                             includeComments: false))
        #expect(throws: MCPReadCaptureError.incoherentCapture) {
            try MCPReadCaptureValidation.validateReusableCapture(replacing(complete, tasks: summary.tasks, comments: []))
        }
    }

    private func replacing(_ view: CapturedReadView, tasks: [ReadTask],
                           comments: [ReadCommentEvidence]) -> CapturedReadView {
        CapturedReadView(completeness: view.completeness, captureScope: view.captureScope, metadata: view.metadata,
            createdAt: view.createdAt, retentionDeadline: view.retentionDeadline, projects: view.projects,
            tasks: tasks, milestones: view.milestones, comments: comments)
    }
}
#endif
