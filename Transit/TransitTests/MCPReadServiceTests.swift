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
        init(_ fixture: TestModelContainer) {
            builder = MCPReadCaptureBuilder(container: fixture.container, fence: .actorOnlyTestFixture)
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
        #expect(try errorCode(conflict) == "SNAPSHOT_CONFLICT")
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

    private func execute(_ service: MCPReadService, arguments: [String: Any]) async throws -> [String: Any] {
        let coordinator = MCPReadCoordinator(domain: service.snapshots.domain)
        let fields = arguments.mapValues(AnyCodable.init)
        let bytes = await coordinator.execute(timeout: Data("timeout".utf8), busy: Data("busy".utf8)) { operation in
            do {
                let prepared = try await service.prepare(tool: "query_tasks",
                    arguments: fields.mapValues(\.value), operation: operation)
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
#endif
