import Foundation
import SwiftData

@main
struct MCPWriteFoundationProbe {
    @MainActor static func main() throws {
        for seed in 0..<100 {
            let value: [String: Any] = ["nested": ["b": seed, "a": true], "array": [NSNull(), "x"]]
            let encoded = try MCPCanonicalJSON.encode(value)
            let decoded = try JSONSerialization.jsonObject(with: Data(encoded.utf8))
            let roundtrip = try MCPCanonicalJSON.encode(decoded)
            precondition(encoded == roundtrip)
        }
        let boolean = try MCPCanonicalJSON.encode(true)
        let number = try MCPCanonicalJSON.encode(1)
        let float = try MCPCanonicalJSON.encode(1.0)
        precondition(boolean != number && number == float)
        try numericPrecision()
        let project = Project(name: "P", description: "", gitRepo: nil, colorHex: "red")
        let task = TransitTask(name: "T", type: .feature, project: project, displayID: .permanent(1))
        let comment = Comment(content: "C", authorName: "A", isAgent: false, task: task)
        let original = try MCPRecordSnapshot.task(task) { _ in [comment] }
        project.name = "excluded"
        let excluded = try MCPRecordSnapshot.task(task) { _ in [comment] }
        precondition(original.revision == excluded.revision)
        comment.content = "changed"
        let changed = try MCPRecordSnapshot.task(task) { _ in [comment] }
        precondition(original.revision != changed.revision)
        comment.content = "C"
        let restored = try MCPRecordSnapshot.task(task) { _ in [comment] }
        precondition(original.revision == restored.revision)
        print("PASS canonical roundtrip and content revisions")
        try receiptStorage()
    }

    @MainActor static func numericPrecision() throws {
        let adjacent = [1.0, 1.0000000000000002, 1.0000000000000004]
        let encodings = try adjacent.map { try MCPCanonicalJSON.encode($0) }
        precondition(Set(encodings).count == adjacent.count, "Adjacent finite Doubles must retain distinct identity")
        for value in [1e300, 1e-300, Double.leastNonzeroMagnitude, Double.greatestFiniteMagnitude] {
            let encoded = try MCPCanonicalJSON.encode(value)
            let decoded = try JSONSerialization.jsonObject(with: Data(encoded.utf8), options: [.fragmentsAllowed])
            precondition((decoded as? NSNumber)?.doubleValue == value)
            let roundtrip = try MCPCanonicalJSON.encode(decoded)
            precondition(roundtrip == encoded)
        }
        let negativeZero = try MCPCanonicalJSON.encode(-0.0)
        let zero = try MCPCanonicalJSON.encode(0)
        precondition(negativeZero == zero)
        print("PASS adjacent-double distinction, finite exponent extremes and signed-zero equivalence")
    }

    @MainActor static func receiptStorage() throws {
        let schema = Schema([Project.self, TransitTask.self, Comment.self, Milestone.self,
                             SyncHeartbeat.self, MCPWriteReceipt.self])
        let configuration = ModelConfiguration("receipt-probe", schema: schema,
                                               isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: configuration)
        let context = container.mainContext
        context.autosaveEnabled = false
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let reservations = try MCPLocalReservationStore(directory: directory)
        let store = MCPWriteReceiptStore(context: context, scopeID: reservations.scopeID)
        let binding = try reservations.reserve(tool: "create_project", key: "key", requestJSON: "{}")
        let receipt = try store.insert(binding, acceptedAt: Date(timeIntervalSinceReferenceDate: 0))
        try context.save()
        receipt.stateRawValue = "committed"
        receipt.completedAt = Date(timeIntervalSinceReferenceDate: 10)
        receipt.expiresAt = Date(timeIntervalSinceReferenceDate: 604810)
        let project = Project(name: "P", description: "", gitRepo: nil, colorHex: "#112233")
        let snapshot = try MCPRecordSnapshot.project(project)
        let result: [String: Any] = [
            "contractVersion": 1, "tool": "create_project", "idempotencyKey": "key",
            "outcome": "committed", "accepted": true, "entityId": project.id.uuidString,
            "record": snapshot.record,
            "completedAt": MCPRecordSnapshot.timestamp(receipt.completedAt!),
            "replayExpiresAt": MCPRecordSnapshot.timestamp(receipt.expiresAt!)
        ]
        receipt.resultJSON = String(data: try JSONSerialization.data(withJSONObject: result), encoding: .utf8)!
        receipt.resultIsError = false
        try context.save()
        let durable = try store.lookup(tool: "create_project", key: "key", durable: true)
        precondition(durable?.stateRawValue == "committed")
        try store.cleanup(now: Date(timeIntervalSinceReferenceDate: 20), reservations: reservations)
        let repaired = try reservations.lookup(tool: "create_project", key: "key")
        precondition(repaired?.expiresAt == receipt.expiresAt)
        try store.cleanup(now: Date(timeIntervalSinceReferenceDate: 604810), reservations: reservations)
        try context.save()
        let expired = try store.lookup(tool: "create_project", key: "key", durable: true)
        let removed = try reservations.lookup(tool: "create_project", key: "key")
        precondition(expired == nil && removed == nil)
        print("PASS scoped receipt staging, durable lookup, expiry repair and cleanup")
    }
}
