#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct TaskLinkQueryBoundaryTests {
    @Test(arguments: ["introduced-by", "duplicate-of", "relates-to"])
    func publicTypeOrientationMatchesBothSavedEndpoints(type: String) throws {
        let base = try TaskLinkCommitDiskFixture()
        let relation = try #require(TaskLinkType(rawValue: type)).normalized(
            source: base.source.id, target: base.target.id)
        base.owner.context.insert(TaskLinkOccurrence(id: UUID(), kindRawValue: relation.kind,
            sourceTaskID: relation.source, targetTaskID: relation.target, createdAt: Date()))
        try base.owner.context.save()
        let view = try builder(base).capture(request())
        for incoming in [false, true] {
            var args = arguments()
            args["linkType"] = type
            if type != "relates-to" { args["linkDirection"] = incoming ? "incoming" : "outgoing" }
            let rows = try MCPReadProjection.tasks(view, request: MCPTaskQueryRequest.parse(args), arguments: args)
            let expected = type == "relates-to" ? Set([base.source.id.uuidString, base.target.id.uuidString])
                : Set([incoming ? base.target.id.uuidString : base.source.id.uuidString])
            #expect(Set(rows.compactMap { $0["taskId"] as? String }) == expected)
        }
    }

    @Test func graphPredicateNarrowsCanonicalBodiesBeforeCopyWithoutWideningClosure() throws {
        let base = try TaskLinkCommitDiskFixture()
        base.target.statusRawValue = "abandoned"
        try base.owner.context.save()
        var args = arguments()
        args["unblocked"] = false
        let query = try MCPTaskQueryRequest.parse(args)
        let source = builder(base)
        let service = MCPReadService(source: source, monitor: MCPImportEvidenceMonitor(syncActive: false,
            storeIdentifier: nil), snapshots: MCPTaskQuerySnapshotStore())
        let capture = service.captureRequest(tool: "query_tasks", arguments: args,
            selection: .tasks(detail: .fullRecord), includeComments: false, query: query)
        let view = try source.capture(capture)
        let candidate = try #require(view.tasks.first { $0.id == base.source.id })
        let closure = try #require(view.tasks.first { $0.id == base.target.id })
        #expect(candidate.fullRecordWithoutCommentsJSON != nil)
        #expect(closure.fullRecordWithoutCommentsJSON == nil)
        let rows = try MCPReadProjection.tasks(view, request: query, arguments: args)
        #expect(rows.count == 1 && rows[0]["taskId"] as? String == base.source.id.uuidString)
        #expect(view.taskLinkGraph?.tasks.count == 2)
    }

    @Test func graphProjectionHonorsSuppliedOriginalDeadline() throws {
        let base = try TaskLinkCommitDiskFixture()
        let view = try builder(base).capture(request())
        let args = arguments()
        #expect(throws: TaskLinkGraphError.deadlineExceeded) {
            try MCPReadProjection.tasks(view, request: MCPTaskQueryRequest.parse(args), arguments: args,
                budget: TaskLinkGraphBudget(deadline: .now - .seconds(1)))
        }
    }

    @Test func modernCursorKeepsExactFrozenGraphPayloadAfterSavedEndpointAndIncidenceEdits() async throws {
        let base = try TaskLinkCommitDiskFixture()
        let snapshots = MCPTaskQuerySnapshotStore()
        let service = MCPReadService(source: builder(base), monitor: MCPImportEvidenceMonitor(syncActive: false,
            storeIdentifier: nil), snapshots: snapshots,
            pagePreparer: { try MCPModernProviderBinding.prepareReadPages($0, tool: $1, operation: $2) })
        var args = arguments()
        args["taskIds"] = [base.source.id.uuidString, base.source.id.uuidString]
        args["limit"] = 1
        let first = try await execute(service, arguments: args)
        let firstPayload = try payload(first)
        let original = try #require((firstPayload["results"] as? [[String: Any]])?.first?["task"] as? [String: Any])
        let cursor = try #require(firstPayload["nextCursor"] as? String)
        base.target.name = "after saved import"
        base.target.statusRawValue = "abandoned"
        base.owner.context.delete(base.edge)
        try base.owner.context.save()
        let next = try await execute(service, arguments: ["cursor": cursor])
        let nextPayload = try payload(next)
        let replayed = try #require((nextPayload["results"] as? [[String: Any]])?.first?["task"] as? [String: Any])
        #expect(try bytes(original) == bytes(replayed))
        #expect((replayed["links"] as? [[String: Any]])?.first?["targetName"] as? String == "target")
        #expect((replayed["blockerAssessment"] as? [String: Any])?["assessment"] as? String == "unblocked")
    }

    private func execute(_ service: MCPReadService, arguments: [String: Any]) async throws -> [String: Any] {
        let coordinator = MCPReadCoordinator(domain: service.snapshots.domain)
        let fields = arguments.mapValues(AnyCodable.init)
        let output = await coordinator.execute(timeout: Data("timeout".utf8), busy: Data("busy".utf8)) { operation in
            do {
                let read = try await service.prepare(tool: "query_tasks", arguments: fields.mapValues(\.value),
                                                     operation: operation)
                let encoded = try MCPModernProviderBinding.read(read, id: .string("link-query"),
                                                               tool: "query_tasks", operation: operation)
                return PreparedReadResult(encodedResponse: encoded, publications: read.publications,
                    publicationErrors: .init(busy: Data("busy".utf8), expired: Data("expired".utf8),
                                             capacity: Data("capacity".utf8)))
            } catch {
                Issue.record("Actual modern graph read failed: \(error)")
                return PreparedReadResult(encodedResponse: Data("failed".utf8), publications: [],
                    publicationErrors: .init(busy: Data(), expired: Data(), capacity: Data()))
            }
        }
        return try #require(JSONSerialization.jsonObject(with: output) as? [String: Any])
    }

    private func payload(_ response: [String: Any]) throws -> [String: Any] {
        let result = try #require(response["result"] as? [String: Any])
        let structured = try #require(result["structuredContent"] as? [String: Any])
        let source = try #require(structured["source"] as? [String: Any])
        let payload = try #require(source["payload"] as? [String: Any])
        let text = try #require((result["content"] as? [[String: Any]])?.first?["text"] as? String)
        #expect(try bytes(payload) == bytes(JSONSerialization.jsonObject(with: Data(text.utf8))))
        return payload
    }

    private func arguments() -> [String: Any] {
        ["detailLevel": "full", "includeComments": false, "limit": 100, "readPolicy": "cached"]
    }
    private func request() -> ReadCaptureRequest {
        ReadCaptureRequest(projectSelectors: nil, selection: .tasks(detail: .fullRecord),
                           completeness: .selectedRead, includeComments: false)
    }
    private func builder(_ base: TaskLinkCommitDiskFixture) -> MCPReadCaptureBuilder {
        MCPReadCaptureBuilder(container: base.owner.container, fence: .actorOnlyTestFixture)
    }
    private func bytes(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    }
}
#endif
