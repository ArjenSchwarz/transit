#if os(macOS)
import Foundation
import Synchronization
import Testing
@testable import Transit

/// Synthetic, immutable evidence only: no models, receipt store or live writes.
nonisolated enum MCPBatchTaskResultFixtures {
    static let taskID = UUID(uuidString: "11111111-1111-4111-8111-a11111111111")!
    static let commentID = UUID(uuidString: "22222222-2222-4222-8222-b22222222222")!
    static let revision = "r1:" + String(repeating: "a", count: 64)
    static let key = "batch.original"
    static let taskRecord = """
    {"taskId":"\(taskID.uuidString)","name":"Saved task","description":null,"status":"done",\
    "type":"feature","priority":"medium","metadata":{},"comments":[],\
    "creationDate":"2026-01-01T00:00:00.000Z","lastStatusChangeDate":"2026-01-01T00:00:00.000Z",\
    "revision":"\(revision)"}
    """
    static let commentRecord = """
    {"id":"\(commentID.uuidString)","taskId":"\(taskID.uuidString)","content":"Saved reason",\
    "authorName":"Agent","isAgent":true,"creationDate":"2026-01-01T00:00:00.000Z",\
    "revision":"\(revision)"}
    """

    static func committed(operation: String = "update_task", version: String = "1", extra: String = "") -> String {
        let record = operation == "add_comment" ? commentRecord : taskRecord
        let entity = operation == "add_comment" ? commentID : taskID
        return """
        {"contractVersion":\(version),"tool":"\(operation)","idempotencyKey":"\(key)",\
        "outcome":"committed","accepted":true,"entityId":"\(entity.uuidString)","record":\(record),\
        "completedAt":"2026-01-01T00:00:00.000Z","replayExpiresAt":"2026-01-08T00:00:00.000Z"\(extra)}
        """
    }

    static func source(_ text: String, isError: Bool? = nil, evidence: MCPResultEvidence = .established)
        throws -> MCPResultSource {
        try MCPResultAdapter.source(text: text, isError: isError, origin: .retainedJSON, evidence: evidence)
    }

    static func recoveryItems(itemID: String = "caller-item") -> [MCPBatchRecoveryItem] {
        [.init(index: 0, itemId: itemID, operation: "update_task",
               originalKey: .init(tool: "update_task", idempotencyKey: key), targetTaskId: taskID)]
    }

    static func context(items: [MCPBatchRecoveryItem], diagnostic: String? = nil,
                        links: [MCPResultEntityPosition] = []) -> MCPResultContext {
        .init(tool: "mutate_tasks", semanticFailure: diagnostic.map {
            .init(category: .serializationFailure, diagnostic: $0)
        }, mutationRecovery: .applicationBatch(items: items), entityPositions: links)
    }

    static func metadata() throws -> MCPResultMetadata {
        try MCPResultMetadata.make(document: MCPJSONDocument.parse(
            #"{"example.test/request":{"n":1E+9999,"explicitNull":null}}"#))
    }

    static func field(_ name: String, in value: MCPJSONValue?) -> MCPJSONValue? {
        guard case .object(let members) = value else { return nil }
        return members.first { $0.name == name }?.value
    }

    static func result(_ bytes: Data) throws -> MCPJSONValue {
        let document = try MCPJSONDocument.parse(bytes)
        return try #require(field("result", in: document.value))
    }

    static func reconciliation(_ selected: MCPResultResponseSelection) throws -> Data {
        guard case .reconciliation(let bytes) = selected else {
            Issue.record("Expected ready reconciliation bytes after synthetic effect failure")
            throw MCPResultBoundaryError.unsupportedEvidence
        }
        return bytes
    }

    static func aggregate(original: String, itemID: String = "caller-item", itemIsError: Bool? = nil) throws -> String {
        let quotedText = try #require(String(data: JSONEncoder().encode(original), encoding: .utf8))
        let flag = itemIsError.map { ",\"isError\":\($0)" } ?? ""
        return """
        {"contractVersion":1,"mode":"execute","atomicity":"per_item","summary":"all_committed",\
        "items":[{"index":0,"itemId":"\(itemID)",\
        "originalResult":{"payload":\(original),"text":\(quotedText)\(flag)}}]}
        """
    }

    static func nestedArrays(_ count: Int) -> String {
        String(repeating: "[", count: count) + "0" + String(repeating: "]", count: count)
    }
}

/// Mutex-backed counters can be used by actual @Sendable common checkpoints.
nonisolated final class MCPBatchTaskEncodingCounts: Sendable {
    nonisolated struct Snapshot: Sendable {
        var prepare = 0
        var dispatch = 0
        var encode = 0
        var prepared: Data?
        var events: [String] = []
    }
    private let state = Mutex(Snapshot())

    func record(_ stage: String, prepared: Data? = nil) {
        state.withLock {
            if stage == "prepare" { $0.prepare += 1 }
            if stage == "dispatch" { $0.dispatch += 1 }
            if stage == "encode" { $0.encode += 1 }
            if let prepared { $0.prepared = prepared }
            $0.events.append(stage)
        }
    }

    func snapshot() -> Snapshot { state.withLock { $0 } }
}
#endif
