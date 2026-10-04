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

    @Test func catalogRejectsMissingAndDuplicatePhysicalTaskMatches() throws {
        let view = try catalogView()
        for tasks in [Array(view.tasks.dropFirst()), view.tasks + [view.tasks[0]]] {
            let malformed = replacingTasks(view, tasks: tasks)
            #expect(throws: MCPReadCaptureError.incoherentCapture) {
                try MCPReadProjection.projects(malformed)
            }
            #expect(throws: MCPReadCaptureError.incoherentCapture) {
                try MCPReadProjection.milestones(malformed, arguments: ["displayId": 7])
            }
        }
    }

    @Test func catalogIndexPreservesRelationshipOrderAndActiveCount() throws {
        let view = try catalogView()
        let reordered = replacingTasks(view, tasks: Array(view.tasks.reversed()))
        let projects = try MCPReadProjection.projects(reordered)
        #expect(projects[0]["activeTaskCount"] as? Int == 2)
        let milestones = try MCPReadProjection.milestones(reordered, arguments: ["displayId": 7])
        let summaries = try #require(milestones[0]["tasks"] as? [[String: Any]])
        let expected = try view.milestones[0].taskKeys.map { key in
            try #require(view.tasks.first { $0.physicalKey == key }).id.uuidString
        }
        #expect(summaries.compactMap { $0["taskId"] as? String } == expected)
    }

    @Test func catalogCancellationInterruptsIndexingAndRelationshipTraversal() throws {
        let view = try catalogView()
        for stopAfter in [3, 7] {
            var checkpoints = 0
            #expect(throws: CancellationError.self) {
                try MCPReadProjection.projects(view, checkpoint: {
                    checkpoints += 1
                    if checkpoints == stopAfter { throw CancellationError() }
                })
            }
            #expect(checkpoints == stopAfter)
        }
        for stopAfter in [3, 9] {
            var checkpoints = 0
            #expect(throws: CancellationError.self) {
                try MCPReadProjection.milestones(view, arguments: ["displayId": 7], checkpoint: {
                    checkpoints += 1
                    if checkpoints == stopAfter { throw CancellationError() }
                })
            }
            #expect(checkpoints == stopAfter)
        }
    }

    @Test(arguments: ["milestoneInput", "projectPolicy", "capacity"])
    func freshPlainTextReadFailuresPreserveSemanticCategory(scenario: String) async throws {
        let fixture = try TestModelContainer()
        let store = MCPTaskQuerySnapshotStore()
        let service = MCPReadService(source: MCPReadCaptureBuilder(container: fixture.container,
            fence: .actorOnlyTestFixture), monitor: MCPImportEvidenceMonitor(syncActive: false,
            storeIdentifier: nil), snapshots: store)
        let coordinator = MCPReadCoordinator(domain: store.domain)
        let tool = scenario == "milestoneInput" ? "query_milestones" : "get_projects"
        let bytes = await coordinator.execute(timeout: Data("timeout".utf8), busy: Data("busy".utf8)) { operation in
            do {
                let prepared: MCPPreparedToolRead
                if scenario == "capacity" {
                    prepared = try await service.prepareFailure(MCPResultPreparationError.retentionCapacity,
                        tool: tool, operation: operation, policy: .cached)
                } else {
                    let arguments: [String: Any] = scenario == "milestoneInput"
                        ? ["status": 17, "readPolicy": "cached"] : ["readPolicy": true]
                    prepared = try await service.prepare(tool: tool, arguments: arguments, operation: operation)
                }
                let context = MCPResultContext(tool: tool, semanticFailure: nil, mutationRecovery: nil,
                                               entityPositions: [])
                let outcome = try MCPResultProviderAdapters.outcome(result: prepared.result, context: context,
                                                                    origin: .generatedJSON)
                let presentation = try MCPResultAdapter.present(outcome.source, context: outcome.context)
                #expect(presentation.errorCategory == (scenario == "capacity" ? .retentionCapacity : .invalidInput))
                #expect(outcome.source.originalText == prepared.result.content[0].text)
                #expect(outcome.source.originalIsError == true)
                #expect(outcome.source.kind == .text)
                #expect(prepared.result.providerEvidence?.failure?.diagnostic == nil)
                return PreparedReadResult(encodedResponse: prepared.encodedToolResult, publications: [],
                    publicationErrors: .init(busy: Data(), expired: Data(), capacity: Data()))
            } catch {
                Issue.record("Read failure classification failed: \(error)")
                return PreparedReadResult(encodedResponse: Data(), publications: [],
                    publicationErrors: .init(busy: Data(), expired: Data(), capacity: Data()))
            }
        }
        #expect(!bytes.isEmpty)
    }

    private func catalogView() throws -> CapturedReadView {
        let fixture = try TestModelContainer()
        let project = Project(name: "Catalog", description: "", gitRepo: nil, colorHex: "blue")
        let milestone = Milestone(name: "Milestone", project: project, displayID: .permanent(7))
        fixture.context.insert(project)
        fixture.context.insert(milestone)
        for index in 0..<3 {
            let task = TransitTask(name: "Task \(index)", type: .feature, project: project,
                                   displayID: .permanent(index + 1))
            task.milestone = milestone
            if index == 0 { task.status = .done }
            fixture.context.insert(task)
        }
        try fixture.context.save()
        return try MCPReadCaptureBuilder(container: fixture.container, fence: .actorOnlyTestFixture)
            .capture(ReadCaptureRequest(projectSelectors: nil, selection: .tasks(detail: .summary),
                                        completeness: .selectedRead, includeComments: false))
    }

    private func replacingTasks(_ view: CapturedReadView, tasks: [ReadTask]) -> CapturedReadView {
        CapturedReadView(completeness: view.completeness, captureScope: view.captureScope, metadata: view.metadata,
            createdAt: view.createdAt, retentionDeadline: view.retentionDeadline, projects: view.projects,
            tasks: tasks, milestones: view.milestones, comments: view.comments)
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
