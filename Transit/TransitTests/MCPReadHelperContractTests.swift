#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

/// Generic preparation acceptance only. Actual portfolio modules have separate delivery gates.
@MainActor @Suite(.serialized)
struct MCPReadHelperContractTests {
    @Test func savedCapsulePreservesMetadataAndObservationThroughHelperTransform() async throws {
        let fixture = try TestModelContainer()
        fixture.context.autosaveEnabled = false
        let project = Project(name: "P", description: "", gitRepo: nil, colorHex: "blue")
        let task = TransitTask(name: "Saved", type: .feature, project: project, displayID: .permanent(63))
        fixture.context.insert(project)
        fixture.context.insert(task)
        try fixture.context.save()
        task.name = "Unsaved UI edit"
        let monitor = MCPImportEvidenceMonitor(syncActive: false, storeIdentifier: nil)
        let store = MCPTaskQuerySnapshotStore()
        let service = MCPReadService(source: MCPReadCaptureBuilder(container: fixture.container,
            fence: .actorOnlyTestFixture), monitor: monitor, snapshots: store)
        // Runtime baseline RED, rather than missing-method compile RED. No fake service implementation.
        guard let preparer = (service as Any) as? any MCPReadCapturedPreparing else {
            Issue.record("MCPReadService has not bound the generic captured preparation contract")
            return
        }
        let coordinator = MCPReadCoordinator(domain: store.domain)
        let request = ReadCaptureRequest(projectSelectors: nil, selection: .tasks(detail: .summary),
                                        completeness: .selectedRead, includeComments: false)
        let bytes = await coordinator.execute(timeout: Data("timeout".utf8), busy: Data("busy".utf8)) { operation in
            do {
                let prepared = try await preparer.prepareCapturedRead(request: request, policy: .cached,
                    operation: operation) { capsule, originalOperation in
                    #expect(capsule.view.tasks.map(\.name) == ["Saved"])
                    #expect(originalOperation.id == operation.id)
                    #expect(originalOperation.remainingBudget() > .zero)
                    let metadata = try JSONDecoder().decode(ReadCaptureMetadata.self,
                                                           from: capsule.frozenMetadataBytes)
                    #expect(metadata.snapshotId == capsule.view.metadata.snapshotId)
                    #expect(metadata.asOf == capsule.view.metadata.asOf)
                    try Self.checkObservationCapacity(monitor, available: 7)
                    let tool = try MCPPreparedToolRead(text: "fixture helper",
                                                       frozenMetadataBytes: capsule.frozenMetadataBytes)
                    #expect(tool.frozenMetadataBytes == capsule.frozenMetadataBytes)
                    return tool
                }
                return Self.result(prepared.encodedToolResult)
            } catch {
                Issue.record("Generic captured preparation failed: \(error)")
                return Self.result(Data("failed".utf8))
            }
        }
        let object = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        #expect(object["id"] == nil && object["jsonrpc"] == nil)
        #expect((object["_meta"] as? [String: Any])?["me.nore.ig.transit/read"] != nil)
        try Self.checkObservationCapacity(monitor, available: 8)
    }

    nonisolated private static func checkObservationCapacity(
        _ monitor: MCPImportEvidenceMonitor, available: Int
    ) throws {
        var windows: [MCPImportObservationWindow] = []
        defer { for window in windows { window.close() } }
        for _ in 0..<available { windows.append(try monitor.beginObservation(applicableImportIDs: [])) }
        #expect(throws: MCPImportObservationError.busy) { try monitor.beginObservation(applicableImportIDs: []) }
    }

    nonisolated private static func result(_ bytes: Data) -> PreparedReadResult {
        PreparedReadResult(encodedResponse: bytes, publications: [],
            publicationErrors: .init(busy: Data(), expired: Data(), capacity: Data()))
    }
}
#endif
