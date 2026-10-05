#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct MCPReadServiceTests {
    @MainActor private final class Source: MCPReadCaptureSource {
        let builder: MCPReadCaptureBuilder
        var calls = 0
        var failure: MCPReadCaptureError?
        init(_ fixture: TestModelContainer, builder: MCPReadCaptureBuilder? = nil) {
            self.builder = builder ?? MCPReadCaptureBuilder(container: fixture.container, fence: .actorOnlyTestFixture)
        }
        func capture(_ request: ReadCaptureRequest) throws -> CapturedReadView {
            calls += 1
            if let failure { throw failure }
            return try builder.capture(request)
        }
    }

    @Test func frozenCursorMetadataPolicyAndPayloadSurviveLocalEdit() async throws {
        let fixture = try TestModelContainer()
        let project = Project(name: "P", description: "", gitRepo: nil, colorHex: "blue")
        fixture.context.insert(project)
        for number in 1...2 {
            fixture.context.insert(TransitTask(name: "Task \(number)", type: .feature,
                                              project: project, displayID: .permanent(number)))
        }
        try fixture.context.save()
        let source = Source(fixture)
        let store = MCPTaskQuerySnapshotStore()
        let service = MCPReadService(source: source, monitor: MCPImportEvidenceMonitor(
            syncActive: true, storeIdentifier: "fixture"), snapshots: store)
        let first = try await execute(service, arguments: ["detailLevel": "summary", "includeComments": false,
                                                           "limit": 1, "readPolicy": "cached"])
        let payload = try object(try #require((first["content"] as? [[String: Any]])?.first?["text"] as? String))
        let cursor = try #require(payload["nextCursor"] as? String)
        let page = try store.retainedPage(for: cursor)
        let originalBytes = try #require(page.metadataBytes)
        project.name = "After"
        try fixture.context.save()
        source.failure = .storageFailure
        for policy in [nil, "cached"] as [String?] {
            var args: [String: Any] = ["cursor": cursor]
            args["readPolicy"] = policy
            let replay = try await execute(service, arguments: args)
            #expect(try metadata(replay) == metadata(first))
            #expect(try store.retainedPage(for: cursor).metadataBytes == originalBytes)
        }
        let conflict = try await execute(service, arguments: ["cursor": cursor, "readPolicy": "refresh_if_needed"])
        #expect(try errorCode(conflict) == "INVALID_INPUT")
        let invalid = try await execute(service, arguments: ["cursor": UUID().uuidString, "readPolicy": true])
        #expect(try errorCode(invalid) == "INVALID_INPUT")
        #expect(source.calls == 1)
        let meta = try object(try #require(String(data: originalBytes, encoding: .utf8)))
        let freshness = try #require(meta["freshness"] as? [String: Any])
        #expect(freshness["assessment"] as? String == "unknown")
        #expect(freshness["lastImportedAt"] is NSNull)
        #expect(meta["asOf"] as? String == freshness["assessedAt"] as? String)
    }

    @Test(arguments: [MCPReadCaptureError.storageFailure, .serializationFailure, .incoherentCapture])
    func requiredCaptureFailureNeverLooksEmpty(failure: MCPReadCaptureError) async throws {
        let fixture = try TestModelContainer()
        let source = Source(fixture)
        source.failure = failure
        let service = MCPReadService(source: source, monitor: MCPImportEvidenceMonitor(
            syncActive: false, storeIdentifier: nil), snapshots: MCPTaskQuerySnapshotStore())
        let result = try await execute(service, arguments: ["detailLevel": "summary", "includeComments": false,
                                                            "limit": 100])
        #expect(result["isError"] as? Bool == true)
        #expect(try errorCode(result) == "QUERY_FAILED")
        let meta = try metadataObject(result)
        #expect(meta["snapshotId"] == nil && meta["asOf"] == nil)
        let expected = failure == .storageFailure ? "storage_failure"
            : failure == .serializationFailure ? "serialization_failure" : "incoherent_capture"
        #expect(meta["category"] as? String == expected)
    }

    @Test func catalogCountsAndMilestoneDetailsUseSavedValuesWithoutComments() async throws {
        let fixture = try TestModelContainer()
        fixture.context.autosaveEnabled = false
        let project = Project(name: "P", description: "", gitRepo: nil, colorHex: "blue")
        let task = TransitTask(name: "Saved", type: .feature, project: project, displayID: .permanent(63))
        fixture.context.insert(project)
        fixture.context.insert(task)
        try fixture.context.save()
        task.name = "Unsaved"
        let builder = MCPReadCaptureBuilder(container: fixture.container, fence: .actorOnlyTestFixture,
                                          fetchComments: { _ in throw CocoaError(.fileReadUnknown) })
        let view = try builder.capture(ReadCaptureRequest(projectSelectors: nil, selection: .projectCatalog,
                                                         completeness: .selectedRead, includeComments: false))
        let projects = try MCPReadProjection.projects(view)
        #expect(projects[0]["activeTaskCount"] as? Int == 1)
        #expect(view.tasks[0].name == "Saved")
        #expect(view.comments.isEmpty)
    }

    @Test(arguments: ["query_tasks", "query_milestones"])
    func projectThenScalarValidationPrecedesDependentFetchFailure(tool: String) async throws {
        let fixture = try TestModelContainer()
        let project = Project(name: "P", description: "", gitRepo: nil, colorHex: "blue")
        fixture.context.insert(project)
        try fixture.context.save()
        var fetched = false
        let builder = MCPReadCaptureBuilder(container: fixture.container, fence: .actorOnlyTestFixture,
            fetchTasks: { _ in fetched = true; throw CocoaError(.fileReadUnknown) },
            fetchMilestones: { _ in fetched = true; throw CocoaError(.fileReadUnknown) })
        let service = MCPReadService(source: Source(fixture, builder: builder),
            monitor: MCPImportEvidenceMonitor(syncActive: false, storeIdentifier: nil),
            snapshots: MCPTaskQuerySnapshotStore())
        var args: [String: Any] = ["project": "Missing", "status": 123]
        if tool == "query_tasks" {
            args.merge(["detailLevel": "summary", "includeComments": false, "limit": 100]) { _, new in new }
        }
        let missing = try await execute(service, arguments: args, tool: tool)
        let missingText = try #require((missing["content"] as? [[String: Any]])?.first?["text"] as? String)
        #expect(missingText.contains("No project named"))
        #expect(!fetched)
        args["project"] = "P"
        let malformed = try await execute(service, arguments: args, tool: tool)
        let malformedText = try #require((malformed["content"] as? [[String: Any]])?.first?["text"] as? String)
        #expect(malformedText.contains("Invalid status"))
        #expect(!fetched)
        args["status"] = tool == "query_tasks" ? "idea" : "open"
        let failed = try await execute(service, arguments: args, tool: tool)
        #expect(try metadataObject(failed)["category"] as? String == "storage_failure")
        #expect(fetched)
    }

    @Test(arguments: ["query_tasks", "query_milestones"])
    func milestoneResolutionPrecedesDependentTaskFetch(tool: String) async throws {
        let fixture = try TestModelContainer()
        let project = Project(name: "P", description: "", gitRepo: nil, colorHex: "blue")
        let first = Milestone(name: "M", project: project, displayID: .permanent(9))
        let duplicate = Milestone(name: "M", project: project, displayID: .permanent(9))
        let task = TransitTask(name: "Task", type: .feature, project: project, displayID: .permanent(63))
        task.milestone = first
        fixture.context.insert(project)
        fixture.context.insert(first)
        fixture.context.insert(duplicate)
        fixture.context.insert(task)
        try fixture.context.save()
        var fetched = false
        let source = Source(fixture, builder: MCPReadCaptureBuilder(container: fixture.container,
            fence: .actorOnlyTestFixture, fetchTasks: { _ in fetched = true; throw CocoaError(.fileReadUnknown) }))
        let service = MCPReadService(source: source, monitor: MCPImportEvidenceMonitor(
            syncActive: false, storeIdentifier: nil), snapshots: MCPTaskQuerySnapshotStore())
        var args: [String: Any] = ["project": "P"]
        if tool == "query_tasks" {
            args.merge(["detailLevel": "summary", "includeComments": false, "limit": 100]) { _, new in new }
        }
        let key = tool == "query_tasks" ? "milestoneDisplayId" : "displayId"
        args[key] = 9
        let ambiguous = try await execute(service, arguments: args, tool: tool)
        let ambiguousText = try #require((ambiguous["content"] as? [[String: Any]])?.first?["text"] as? String)
        #expect(ambiguousText.contains("Duplicate milestone identifier"))
        #expect(!fetched)
        args[key] = 77
        let absent = try await execute(service, arguments: args, tool: tool)
        #expect(absent["isError"] == nil)
        #expect(!fetched)
        fixture.context.delete(duplicate)
        try fixture.context.save()
        args[key] = 9
        if tool == "query_milestones" {
            args["status"] = "done"
            let filtered = try await execute(service, arguments: args, tool: tool)
            #expect(filtered["isError"] == nil && !fetched)
            args.removeValue(forKey: "status")
        }
        let failed = try await execute(service, arguments: args, tool: tool)
        #expect(try metadataObject(failed)["category"] as? String == "storage_failure")
        #expect(fetched)
    }

    @Test(arguments: [true, false])
    func emptyFullTaskReadDoesNotRequireUnrelatedComments(missingMilestone: Bool) async throws {
        let fixture = try TestModelContainer()
        let project = Project(name: "P", description: "", gitRepo: nil, colorHex: "blue")
        fixture.context.insert(project)
        if missingMilestone {
            fixture.context.insert(TransitTask(name: "Unrelated", type: .feature,
                                              project: project, displayID: .permanent(63)))
        }
        try fixture.context.save()
        var commentsFetched = false
        let builder = MCPReadCaptureBuilder(container: fixture.container, fence: .actorOnlyTestFixture,
            fetchComments: { _ in commentsFetched = true; throw CocoaError(.fileReadUnknown) })
        let service = MCPReadService(source: Source(fixture, builder: builder), monitor: MCPImportEvidenceMonitor(
            syncActive: false, storeIdentifier: nil), snapshots: MCPTaskQuerySnapshotStore())
        var arguments: [String: Any] = ["project": "P", "detailLevel": "full", "includeComments": true, "limit": 100]
        if missingMilestone { arguments["milestoneDisplayId"] = 77 }
        let result = try await execute(service, arguments: arguments)
        #expect(result["isError"] == nil)
        #expect(!commentsFetched)
        let text = try #require((result["content"] as? [[String: Any]])?.first?["text"] as? String)
        let payload = try object(text)
        #expect((payload["results"] as? [[String: Any]])?.isEmpty == true)
        #expect(try metadataObject(result)["snapshotId"] != nil)
    }

    @Test func validEmptyInactiveReadHasCaptureMetadata() async throws {
        let fixture = try TestModelContainer()
        let service = MCPReadService(source: Source(fixture), monitor: MCPImportEvidenceMonitor(
            syncActive: false, storeIdentifier: nil), snapshots: MCPTaskQuerySnapshotStore())
        let result = try await execute(service, arguments: ["detailLevel": "summary", "includeComments": false,
                                                            "limit": 100])
        #expect(result["isError"] == nil)
        let meta = try metadataObject(result)
        #expect(meta["snapshotId"] is String && meta["asOf"] is String)
        #expect((meta["freshness"] as? [String: Any])?["assessment"] as? String == "not_applicable")
        #expect((meta["read"] as? [String: Any])?["refreshOutcome"] as? String == "not_requested")
    }

    private func execute(_ service: MCPReadService, arguments: [String: Any],
                         tool: String = "query_tasks") async throws -> [String: Any] {
        let env = try MCPTestHelpers.makeEnv()
        let handler = MCPToolHandler(taskService: env.taskService, projectService: env.projectService,
            commentService: env.commentService, milestoneService: env.milestoneService,
            maintenanceService: env.maintenanceService, settings: env.mcpSettings, readService: service)
        let coordinator = MCPReadCoordinator(domain: service.snapshots.domain)
        let fields = arguments.mapValues(AnyCodable.init)
        let bytes = await coordinator.execute(timeout: Data("timeout".utf8), busy: Data("busy".utf8)) { operation in
            do {
                let prepared = try await handler.prepareCoveredRead(
                    MCPReadToolRequest(tool: tool, arguments: fields), operation: operation)
                let rejection = Data("rejected".utf8)
                return PreparedReadResult(encodedResponse: prepared.encodedToolResult,
                    publications: prepared.publications,
                    publicationErrors: PreencodedPublicationErrors(busy: rejection, expired: rejection,
                                                                  capacity: rejection))
            } catch {
                return PreparedReadResult(encodedResponse: Data("unexpected".utf8), publications: [],
                    publicationErrors: PreencodedPublicationErrors(busy: Data(), expired: Data(), capacity: Data()))
            }
        }
        return try object(try #require(String(data: bytes, encoding: .utf8)))
    }

    private func object(_ text: String) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    private func metadataObject(_ result: [String: Any]) throws -> [String: Any] {
        try #require((result["_meta"] as? [String: Any])?["me.nore.ig.transit/read"] as? [String: Any])
    }

    private func metadata(_ result: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: metadataObject(result), options: [.sortedKeys])
    }

    private func errorCode(_ result: [String: Any]) throws -> String {
        let text = try #require((result["content"] as? [[String: Any]])?.first?["text"] as? String)
        return try #require((try object(text)["error"] as? [String: Any])?["code"] as? String)
    }
}
extension MCPReadServiceTests {
    @Test(arguments: [false, true])
    func emptyPortfolioStillRequiresOrphanCommentEvidence(scoped: Bool) throws {
        let fixture = try TestModelContainer()
        let project = Project(name: "P", description: "", gitRepo: nil, colorHex: "blue")
        fixture.context.insert(project)
        try fixture.context.save()
        var commentsFetched = false
        let builder = MCPReadCaptureBuilder(container: fixture.container, fence: .actorOnlyTestFixture,
            fetchComments: { _ in commentsFetched = true; throw CocoaError(.fileReadUnknown) })
        let request = ReadCaptureRequest(projectSelectors: scoped ? [.id(project.id)] : nil,
            selection: .portfolio, completeness: .completePortfolio, includeComments: false)
        #expect(throws: MCPReadCaptureError.storageFailure) { try builder.capture(request) }
        #expect(commentsFetched)
    }

}
extension MCPReadServiceTests {
    @Test(arguments: ["filtered", "batch", "selected"])
    func taskCanonicalSerializationFollowsTypedSelection(mode: String) async throws {
        let fixture = try TestModelContainer()
        let project = Project(name: "P", description: "", gitRepo: nil, colorHex: "blue")
        let good = TransitTask(name: "Good", type: .feature, project: project, displayID: .permanent(1))
        good.statusRawValue = "done"
        let bad = TransitTask(name: "Bad", type: .feature, project: project, displayID: .permanent(2))
        fixture.context.insert(project)
        fixture.context.insert(good)
        fixture.context.insert(bad)
        try fixture.context.save()
        // Inject corrupt read evidence into the fresh capture context, never into persisted data.
        let builder = MCPReadCaptureBuilder(container: fixture.container, fence: .actorOnlyTestFixture,
            fetchTasks: { context in
                let values = try context.fetch(FetchDescriptor<TransitTask>())
                let corrupt = try #require(values.first { $0.permanentDisplayId == 2 })
                corrupt.creationDate = Date(timeIntervalSinceReferenceDate: .nan)
                #expect(throws: (any Error).self) { try MCPRecordSnapshot.task(corrupt, incidence: []) { _ in [] } }
                return values
            })
        let service = MCPReadService(source: Source(fixture, builder: builder), monitor: MCPImportEvidenceMonitor(
            syncActive: false, storeIdentifier: nil), snapshots: MCPTaskQuerySnapshotStore())
        var args: [String: Any] = ["detailLevel": "full", "includeComments": false, "limit": 100]
        if mode == "filtered" { args["status"] = "done" }
        if mode == "batch" { args["displayIds"] = [1] }
        if mode == "selected" { args["displayId"] = 2 }
        let result = try await execute(service, arguments: args)
        if mode == "selected" {
            #expect(try errorCode(result) == "QUERY_FAILED")
            #expect(try metadataObject(result)["category"] as? String == "serialization_failure")
        } else {
            #expect(result["isError"] == nil)
            let text = try #require((result["content"] as? [[String: Any]])?.first?["text"] as? String)
            #expect((try object(text)["results"] as? [[String: Any]])?.count == 1)
        }
    }

    @Test(arguments: ["query_tasks", "query_milestones", "get_projects", "selected_milestone"])
    func unrelatedMilestoneCanonicalDatesDoNotPoisonSelectedOutput(tool: String) async throws {
        let fixture = try TestModelContainer()
        let project = Project(name: "P", description: "", gitRepo: nil, colorHex: "blue")
        let good = Milestone(name: "Good", project: project, displayID: .permanent(1))
        let bad = Milestone(name: "Bad", project: project, displayID: .permanent(2))
        bad.statusRawValue = "done"
        let task = TransitTask(name: "Task", type: .feature, project: project, displayID: .permanent(63))
        task.milestone = bad
        fixture.context.insert(project)
        fixture.context.insert(good)
        fixture.context.insert(bad)
        fixture.context.insert(task)
        try fixture.context.save()
        let builder = MCPReadCaptureBuilder(container: fixture.container, fence: .actorOnlyTestFixture,
            fetchMilestones: { context in
                let values = try context.fetch(FetchDescriptor<Milestone>())
                let corrupt = try #require(values.first { $0.permanentDisplayId == 2 })
                corrupt.creationDate = Date(timeIntervalSinceReferenceDate: .nan)
                #expect(throws: (any Error).self) { try MCPRecordSnapshot.milestone(corrupt) }
                return values
            })
        let service = MCPReadService(source: Source(fixture, builder: builder), monitor: MCPImportEvidenceMonitor(
            syncActive: false, storeIdentifier: nil), snapshots: MCPTaskQuerySnapshotStore())
        var args: [String: Any] = [:]
        if tool == "query_milestones" { args["status"] = "open" }
        if tool == "query_tasks" {
            args = ["detailLevel": "full", "includeComments": false, "limit": 100]
        }
        if tool == "selected_milestone" { args["status"] = "done" }
        let actualTool = tool == "selected_milestone" ? "query_milestones" : tool
        let result = try await execute(service, arguments: args, tool: actualTool)
        if tool == "selected_milestone" {
            #expect(result["isError"] as? Bool == true)
            #expect(try metadataObject(result)["category"] as? String == "serialization_failure")
        } else {
            #expect(result["isError"] == nil)
        }
    }
}
#endif
