#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

/// Each stage executes in a separate, drained development test-host process.
@MainActor @Suite(.serialized)
struct TaskConsolidationMigrationTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["T2381_CLOSED_STAGE"] != nil))
    func closedEightEntityStoreStage() throws {
        let env = ProcessInfo.processInfo.environment
        let stage = try #require(env["T2381_CLOSED_STAGE"])
        let token = try #require(env["T2381_CLOSED_TOKEN"].flatMap(UUID.init(uuidString:)))
        _ = try #require(["seed", "legacy", "upgrade", "reopen"].contains(stage))
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        _ = try #require(home.path.hasSuffix("/Library/Containers/me.nore.ig.Transit.development/Data"))
        let root = home.appendingPathComponent("tmp/T2381Closed-\(token.uuidString)", isDirectory: true)
        _ = try #require(root.resolvingSymlinksInPath().path == root.path)
        let isSeed = stage == "seed"
        let isCurrent = stage == "upgrade" || stage == "reopen"
        let old = Schema([Project.self, TransitTask.self, Transit.Comment.self, Milestone.self,
            SyncHeartbeat.self, MCPWriteReceipt.self, TaskLinkOccurrence.self, TaskLinkRemovalEvidence.self])
        let schema = isCurrent ? try TestModelContainer().container.schema : old
        let fixture = try TaskLinkPreFeatureDiskFixture(directory: root, schema: schema, seed: isSeed)
        if isSeed {
            let tasks = try fixture.owner.context.fetch(FetchDescriptor<TransitTask>()).sorted { $0.name < $1.name }
            let instant = Date(timeIntervalSinceReferenceDate: 12345.00000000001)
            fixture.owner.context.insert(TaskLinkOccurrence(id: UUID(), kindRawValue: "association",
                sourceTaskID: tasks[0].id, targetTaskID: UUID(), createdAt: instant))
            fixture.owner.context.insert(TaskLinkRemovalEvidence(id: UUID(), edgeId: UUID(),
                kindRawValue: "duplicate", sourceTaskID: tasks[1].id, targetTaskID: UUID(), createdAt: instant,
                occurrenceRevision: "r1:" + String(repeating: "a", count: 64), removedAt: instant))
            try fixture.owner.context.save()
        }
        let raw = try fixture.savedFields(in: fixture.owner.context)
        let links = try fixture.owner.context.fetch(FetchDescriptor<TaskLinkOccurrence>()).map { row in
            [row.id.uuidString, row.kindRawValue, row.sourceTaskID.uuidString, row.targetTaskID.uuidString,
             String(row.createdAt.timeIntervalSinceReferenceDate.bitPattern, radix: 16)]
        }
        let removals = try fixture.owner.context.fetch(FetchDescriptor<TaskLinkRemovalEvidence>()).map { row in
            [row.id.uuidString, row.edgeId.uuidString, row.kindRawValue, row.sourceTaskID.uuidString,
             row.targetTaskID.uuidString, String(row.createdAt.timeIntervalSinceReferenceDate.bitPattern, radix: 16),
             row.occurrenceRevision, String(row.removedAt.timeIntervalSinceReferenceDate.bitPattern, radix: 16)]
        }
        let bytes = try JSONSerialization.data(withJSONObject: ["raw": raw.base64EncodedString(),
            "links": links, "removals": removals], options: [.sortedKeys])
        let original = root.appendingPathComponent("original.json")
        if isSeed { try bytes.write(to: original, options: .withoutOverwriting) } else {
            let expected = try Data(contentsOf: original)
            _ = try #require(bytes == expected)
        }
        let names = Set(fixture.owner.container.schema.entities.map(\.name))
        if isCurrent {
            _ = try #require(names == Set(old.entities.map(\.name)).union(["TaskConsolidationEvent"]))
            _ = try #require(try fixture.owner.context.fetchCount(FetchDescriptor<TaskConsolidationEvent>()) == 0)
        } else { _ = try #require(names == Set(old.entities.map(\.name))) }
        try record(stage: stage, token: token, root: root, names: names)
        _ = try #require(!fixture.owner.context.hasChanges)
    }
    private func record(stage: String, token: UUID, root: URL, names: Set<String>) throws {
        let evidence: [String: Any] = ["stage": stage, "token": token.uuidString,
            "pid": ProcessInfo.processInfo.processIdentifier, "root": root.path,
            "rawFieldsPreserved": true, "schemaEntities": names.sorted(), "cloudKit": "none"]
        try JSONSerialization.data(withJSONObject: evidence, options: [.sortedKeys])
            .write(to: root.appendingPathComponent("\(stage).json"), options: .withoutOverwriting)
    }
}
#endif
