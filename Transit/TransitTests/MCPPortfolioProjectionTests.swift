#if os(macOS)
import Foundation
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct MCPPortfolioProjectionTests {
    @Test func fullDetailPreservesEveryCapturedFieldAndCommentCoveredRevision() throws {
        let capture = try MCPPortfolioSavedFixture().capture()
        let task = try #require(capture.tasks.first { !$0.commentKeys.isEmpty })
        let canonical = try object(#require(task.fullRecordWithoutCommentsJSON))
        let output = try object(MCPPortfolioProjection.task(record: task, detail: .full).json)
        for (key, value) in canonical where key != "status" {
            #expect(NSDictionary(dictionary: [key: value]).isEqual(to: [key: output[key] as Any]))
        }
        #expect(output["revision"] as? String == task.revision)
        #expect(task.revision?.hasPrefix("r1:") == true)
        #expect(output["description"] as? String == task.taskDescription)
        #expect(output["metadata"] as? [String: String] == task.metadata)
        #expect(output["comments"] == nil && output["commentKeys"] == nil)
        let rendered = try #require(String(data: JSONSerialization.data(withJSONObject: output), encoding: .utf8))
        #expect(!rendered.contains("Canonical comment coverage"))
    }

    @Test func summaryHasOrdinarySummaryFieldsWithoutFullBodies() throws {
        let capture = try MCPPortfolioSavedFixture().capture()
        let task = try #require(capture.tasks.first { $0.rawStatus == "done" })
        let canonical = try object(#require(task.fullRecordWithoutCommentsJSON))
        let output = try object(MCPPortfolioProjection.task(record: task, detail: .summary).json)
        let expectedKeys: Set<String> = [
            "taskId", "name", "status", "type", "priority", "lastStatusChangeDate",
            "displayId", "projectId", "projectName", "completionDate", "milestone"
        ]
        #expect(Set(output.keys) == Set(canonical.keys).intersection(expectedKeys))
        for key in expectedKeys where canonical[key] != nil {
            #expect(NSDictionary(dictionary: [key: canonical[key] as Any]).isEqual(to: [key: output[key] as Any]))
        }
        #expect(output["description"] == nil && output["metadata"] == nil && output["comments"] == nil)
    }

    @Test(arguments: ["summary", "full"])
    func unknownStoredStatusFallsBackWithoutChangingCanonicalRevision(detail: String) throws {
        let capture = try MCPPortfolioSavedFixture().capture()
        let task = try #require(capture.tasks.first { $0.rawStatus == "unknown" })
        let output = try object(MCPPortfolioProjection.task(
            record: task, detail: detail == "full" ? .full : .summary).json)
        #expect(output["status"] as? String == "idea" && output["storedStatus"] as? String == "unknown")
        if detail == "full" { #expect(output["revision"] as? String == task.revision) }
        let original = try object(#require(task.fullRecordWithoutCommentsJSON))
        #expect(original["status"] as? String == "unknown")
    }

    @Test func knownStatusDoesNotInventStoredStatusField() throws {
        let capture = try MCPPortfolioSavedFixture().capture()
        let task = try #require(capture.tasks.first { $0.rawStatus == "planning" })
        for detail in [SnapshotTaskDetail.summary, .full] {
            let output = try object(MCPPortfolioProjection.task(record: task, detail: detail).json)
            #expect(output["status"] as? String == "planning" && output["storedStatus"] == nil)
        }
    }

    @Test func frozenMetadataBytesAreRetainedExactlyRatherThanReencoded() throws {
        let capture = try MCPPortfolioSavedFixture().capture()
        let helper = MCPReusableSnapshotStoreTests()
        let initial = try helper.bundle(capture)
        // Valid metadata with intentional wire whitespace proves byte preservation.
        let frozen = Data(" \n".utf8) + initial.root.frozenMetadataBytes + Data("\n ".utf8)
        let root = RetainedView(capture: initial.root.capture, frozenMetadataBytes: frozen,
                                window: initial.root.window, initialRequest: initial.root.initialRequest,
                                firstPage: initial.root.firstPage)
        let domain = MCPReadPublicationDomain(testingInstant: capture.createdAt)
        let store = try MCPReusableSnapshotStore(domain: domain)
        let bundle = EncodedViewBundle(root: root, pages: [], cursors: [], encodedCaptureByteCount: 100)
        try helper.commit(helper.stage(bundle, store: store), in: domain)
        let retained = try store.retainedView(for: root.capture.metadata.snapshotId, now: capture.createdAt)
        #expect(retained.frozenMetadataBytes == frozen)
        let plan = try MCPPortfolioProjection.query(root: retained, request: query(retained))
        #expect(plan.frozenMetadataBytes == frozen)
    }

    func object(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func query(_ root: RetainedView, detail: SnapshotTaskDetail = .summary, limit: Int = 2,
               projectId: UUID? = nil, statuses: [String] = []) -> MCPSnapshotTaskQueryRequest {
        .initial(snapshotId: root.capture.metadata.snapshotId, detail: detail, limit: limit,
                 projectId: projectId, statuses: statuses)
    }

    func rows(_ plan: EncodedSnapshotTaskPages) throws -> [[String: Any]] {
        try ([plan.firstPage] + plan.pages).flatMap { try #require(object($0)["results"] as? [[String: Any]]) }
    }

    func args() -> [String: Any] {
        ["snapshotId": UUID().uuidString, "detailLevel": "summary", "includeComments": false, "limit": 2]
    }
}
#endif
