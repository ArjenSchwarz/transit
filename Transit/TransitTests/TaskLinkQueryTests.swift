#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct TaskLinkQueryTests {
    @Test(arguments: ["recorded", "empty", "blocked-by", "blocks"])
    func ordinaryGraphFiltersCombineWithSavedSelection(option: String) throws {
        let fixture = try Fixture()
        var args = fixture.arguments
        switch option {
        case "recorded": args["hasLinks"] = true
        case "empty": args["hasLinks"] = false
        default:
            args["linkType"] = option
            args["linkTargetTaskId"] = (option == "blocks" ? fixture.base.source.id : fixture.base.target.id).uuidString
        }
        let records = try fixture.project(args)
        let expected: Set<String> = switch option {
        case "recorded": [fixture.base.source.id.uuidString, fixture.base.target.id.uuidString]
        case "empty": [fixture.unlinked.id.uuidString]
        case "blocks": [fixture.base.target.id.uuidString]
        default: [fixture.base.source.id.uuidString]
        }
        #expect(Set(records.compactMap { $0["taskId"] as? String }) == expected)
    }

    @Test(arguments: ["done", "abandoned", "future-status"])
    func blockedOnlyExcludesUncertifiedAssessment(status: String) throws {
        let fixture = try Fixture()
        fixture.base.target.statusRawValue = status
        try fixture.base.owner.context.save()
        var args = fixture.arguments
        args["unblocked"] = false
        let blocked = try fixture.project(args)
        #expect(blocked.compactMap { $0["taskId"] as? String }
            == (status == "abandoned" ? [fixture.base.source.id.uuidString] : []))
        args["unblocked"] = true
        let unblocked = try fixture.project(args)
        #expect(unblocked.contains { $0["taskId"] as? String == fixture.base.source.id.uuidString }
            == (status == "done"))
    }

    @Test func fullDetailUsesFrozenLabelsIncidenceAndAssessmentAfterSavedEdits() throws {
        let fixture = try Fixture()
        let view = try fixture.capture()
        let before = try fixture.project(fixture.arguments, view: view)
        let source = try #require(before.first { $0["taskId"] as? String == fixture.base.source.id.uuidString })
        let links = try #require(source["links"] as? [[String: Any]])
        #expect(links.count == 1 && links[0]["type"] as? String == "blocked-by")
        #expect(links[0]["targetName"] as? String == "target")
        #expect((source["blockerAssessment"] as? [String: Any])?["assessment"] as? String == "unblocked")
        fixture.base.target.name = "later saved label"
        fixture.base.target.statusRawValue = "abandoned"
        try fixture.base.owner.context.save()
        #expect(try bytes(fixture.project(fixture.arguments, view: view)) == bytes(before))
        let fresh = try fixture.project(fixture.arguments)
        let updated = try #require(fresh.first { $0["taskId"] as? String == fixture.base.source.id.uuidString })
        #expect((updated["blockerAssessment"] as? [String: Any])?["assessment"] as? String == "blocked")
        #expect(updated["revision"] as? String == source["revision"] as? String)
    }

    @Test func missingGraphCaptureExplicitlyReportsUnavailableObservation() throws {
        let fixture = try Fixture()
        let view = try fixture.capture()
        let legacy = CapturedReadView(completeness: view.completeness, captureScope: view.captureScope,
            metadata: view.metadata, createdAt: view.createdAt, retentionDeadline: view.retentionDeadline,
            projects: view.projects, tasks: view.tasks, milestones: view.milestones, comments: view.comments)
        let records = try fixture.project(fixture.arguments, view: legacy)
        #expect(records.allSatisfy { $0["graphCoverage"] as? String == "unavailable" })
        #expect(records.allSatisfy { $0["links"] is NSNull })
    }

    @Test func incomingDuplicateVisibilityDoesNotRedirectOrdinaryTaskIdentity() throws {
        let fixture = try Fixture()
        fixture.base.owner.context.insert(TaskLinkOccurrence(id: UUID(), kindRawValue: "duplicate",
            sourceTaskID: fixture.base.source.id, targetTaskID: fixture.base.target.id, createdAt: Date()))
        try fixture.base.owner.context.save()
        let records = try fixture.project(fixture.arguments)
        let source = try #require(records.first { $0["taskId"] as? String == fixture.base.source.id.uuidString })
        let target = try #require(records.first { $0["taskId"] as? String == fixture.base.target.id.uuidString })
        #expect((source["duplicateResolution"] as? [String: Any])?["canonicalTaskId"] as? String
            == fixture.base.target.id.uuidString)
        let incoming = try #require(target["links"] as? [[String: Any]])
        #expect(incoming.contains {
            $0["type"] as? String == "duplicate-of" && $0["direction"] as? String == "incoming"
        })
    }

    @Test func defaultHandlerCannotReturnUnsavedSourceOrCommentDrafts() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "saved", description: nil, type: .feature, project: project)
        let comment = try env.commentService.addComment(
            to: task, content: "saved comment", authorName: "A", isAgent: true)
        task.name = "draft"
        comment.content = "draft comment"
        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(tool: "query_tasks", arguments: [
            "detailLevel": "full", "includeComments": true, "limit": 100]))
        let records = try MCPTestHelpers.decodeQueryResults(response)
        #expect(records[0]["name"] as? String == "saved")
        #expect((records[0]["comments"] as? [[String: Any]])?.first?["content"] as? String == "saved comment")
        #expect(env.context.hasChanges && task.name == "draft" && comment.content == "draft comment")
    }

    @Test(arguments: ["hasLinks", "unblocked", "linkType", "linkTargetTaskId", "linkDirection"])
    func malformedOptionsAndReusableGraphOptionsAreRejected(key: String) throws {
        let fixture = try Fixture()
        var args = fixture.arguments
        args[key] = 42
        #expect(throws: MCPTaskQueryError.self) { try MCPTaskQueryRequest.parse(args) }
        args[key] = key == "hasLinks" || key == "unblocked" ? true : "duplicate-of"
        args["snapshotId"] = UUID().uuidString
        #expect(throws: MCPSnapshotTaskQueryError.self) { try MCPSnapshotTaskQueryRequest.parse(args) }
    }

    private func bytes(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    }

    @MainActor private struct Fixture {
        let base: TaskLinkCommitDiskFixture
        let unlinked: TransitTask
        let arguments: [String: Any] = ["detailLevel": "full", "includeComments": false, "limit": 100]
        init() throws {
            base = try TaskLinkCommitDiskFixture()
            let project = try #require(base.source.project)
            unlinked = TransitTask(name: "unlinked", type: .feature, project: project,
                                   displayID: .permanent(3))
            base.owner.context.insert(unlinked)
            try base.owner.context.save()
        }
        func capture() throws -> CapturedReadView {
            try MCPReadCaptureBuilder(container: base.owner.container, fence: .actorOnlyTestFixture).capture(
                ReadCaptureRequest(projectSelectors: nil, selection: .tasks(detail: .fullRecord),
                                   completeness: .selectedRead))
        }
        func project(_ args: [String: Any], view: CapturedReadView? = nil) throws -> [[String: Any]] {
            let request = try MCPTaskQueryRequest.parse(args)
            return try MCPReadProjection.tasks(view ?? capture(), request: request, arguments: args)
        }
    }
}
#endif
