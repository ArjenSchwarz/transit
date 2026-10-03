#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct MCPReadProjectionTests {
    @Test func summaryUsesSavedValuesAndDoesNotFetchComments() throws {
        let fixture = try TestModelContainer()
        fixture.context.autosaveEnabled = false
        let project = Project(name: "Saved project", description: "", gitRepo: nil, colorHex: "blue")
        let task = TransitTask(name: "Saved task", type: .feature, project: project, displayID: .permanent(63))
        fixture.context.insert(project)
        fixture.context.insert(task)
        try fixture.context.save()
        let expected = IntentHelpers.taskToDict(task, formatter: ISO8601DateFormatter())
        task.name = "Unsaved task"
        project.name = "Unsaved project"
        let source = MCPReadCaptureBuilder(container: fixture.container, fence: .actorOnlyTestFixture,
                                          fetchComments: { _ in throw CocoaError(.fileReadUnknown) })
        let view = try source.capture(request(full: false))
        let results = try MCPReadProjection.tasks(view, request: query(), arguments: [:])
        #expect(try bytes(results[0]) == bytes(expected))
        #expect(fixture.context.hasChanges)
    }

    @Test func fullHiddenCommentsPreserveAuthoritativeRevision() throws {
        let fixture = try TestModelContainer()
        let project = Project(name: "P", description: "", gitRepo: nil, colorHex: "blue")
        let task = TransitTask(name: "Task", type: .bug, project: project, displayID: .permanent(63))
        let comment = Comment(content: "Before", authorName: "A", isAgent: true, task: task)
        fixture.context.insert(project)
        fixture.context.insert(task)
        fixture.context.insert(comment)
        try fixture.context.save()
        let expected = try MCPRecordSnapshot.task(task, in: fixture.context).revision
        let view = try MCPReadCaptureBuilder(container: fixture.container, fence: .actorOnlyTestFixture)
            .capture(request(full: true))
        comment.content = "After"
        try fixture.context.save()
        let results = try MCPReadProjection.tasks(view, request: query(full: true), arguments: [:])
        #expect(results[0]["revision"] as? String == expected)
        #expect(results[0]["comments"] == nil)
        #expect(results[0]["metadata"] == nil)
        #expect(results[0]["description"] is NSNull)
    }

    @Test func duplicateUUIDSelectorRemainsAmbiguousDespitePhysicalKeys() throws {
        let fixture = try TestModelContainer()
        let project = Project(name: "P", description: "", gitRepo: nil, colorHex: "blue")
        let first = TransitTask(name: "First", type: .feature, project: project, displayID: .permanent(1))
        let second = TransitTask(name: "Second", type: .feature, project: project, displayID: .permanent(2))
        second.id = first.id
        fixture.context.insert(project)
        fixture.context.insert(first)
        fixture.context.insert(second)
        try fixture.context.save()
        let view = try MCPReadCaptureBuilder(container: fixture.container, fence: .actorOnlyTestFixture)
            .capture(request(full: false))
        let args: [String: Any] = ["taskIds": [first.id.uuidString.lowercased(), UUID().uuidString],
                                 "detailLevel": "summary", "includeComments": false, "limit": 100]
        let results = try MCPReadProjection.tasks(view, request: MCPTaskQueryRequest.parse(args), arguments: args)
        #expect((results[0]["error"] as? [String: String])?["code"] == "AMBIGUOUS_TASK_ID")
        #expect((results[1]["error"] as? [String: String])?["code"] == "TASK_NOT_FOUND")
        #expect(results.map { $0["index"] as? Int } == [0, 1])
    }

    @Test func malformedPolicyPrecedesCursorLookupAndMatchingPolicyIsAccepted() throws {
        let cursor = UUID().uuidString
        #expect(throws: MCPTaskQueryError.self) {
            try MCPTaskQueryRequest.parse(["cursor": cursor, "readPolicy": 1])
        }
        #expect(try MCPTaskQueryRequest.parse(["cursor": cursor, "readPolicy": "cached"]).readPolicy == .cached)
        #expect(try MCPTaskQueryRequest.parse(["cursor": cursor]).readPolicy == nil)
    }

    private func request(full: Bool) -> ReadCaptureRequest {
        ReadCaptureRequest(projectSelectors: nil, selection: .tasks(detail: full ? .fullRecord : .summary),
                           completeness: .selectedRead, includeComments: false)
    }

    private func query(full: Bool = false) throws -> MCPTaskQueryRequest {
        try MCPTaskQueryRequest.parse(["detailLevel": full ? "full" : "summary",
                                       "includeComments": false, "limit": 100])
    }

    private func bytes(_ value: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    }
}
#endif
