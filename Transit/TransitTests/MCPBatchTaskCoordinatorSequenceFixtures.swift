#if os(macOS)
import Foundation
import Testing
@testable import Transit

@MainActor enum MCPBatchTaskCoordinatorSequenceFixtures {
    static func request(count: Int = 4) throws -> MCPBatchTaskRequest {
        let values = (0..<count).map { MCPBatchTaskRequestFixtures.item($0) }
        let data = try JSONSerialization.data(withJSONObject: ["mode": "execute", "items": values])
        guard case .valid(let request) = try MCPBatchTaskRequest.parse(MCPJSONDocument.parse(data)) else {
            throw MCPResultBoundaryError.invalidJSON
        }
        return request
    }

    static func prepared(_ request: MCPBatchTaskRequest) throws -> MCPBatchTaskPreparedResponse {
        try MCPBatchTaskPreparedResponse.prepare(id: .string("task9.request"), items: request.items.map {
            MCPBatchRecoveryItem(index: $0.index, itemId: $0.itemId, operation: $0.operation,
                originalKey: .init(tool: $0.command.tool, idempotencyKey: $0.command.key),
                    targetTaskId: $0.targetTaskId)
        }, metadata: nil)
    }

    static func source(_ item: MCPBatchTaskRequest.Item, kind: String = "committed") throws -> MCPResultSource {
        if kind == "malformed" { return try MCPBatchTaskResultFixtures.source("{historic broken", isError: true) }
        if kind == "unknown" {
            return try MCPBatchTaskResultFixtures.source("{\"contractVersion\":2,\"outcome\":\"committed\"}")
        }
        if kind == "committed" || kind == "missingStatusComment" {
            var extra = #", "unknown":{"n":9007199254740993,"huge":1E9999,"null":null}"#
            if item.operation == "update_task_status", kind != "missingStatusComment" {
                extra += ",\"comment\":" + MCPBatchTaskResultFixtures.commentRecord
            }
            let text = MCPBatchTaskResultFixtures.committed(operation: item.operation, extra: extra)
                .replacingOccurrences(of: MCPBatchTaskResultFixtures.taskID.uuidString,
                                      with: item.targetTaskId.uuidString)
                .replacingOccurrences(of: MCPBatchTaskResultFixtures.key, with: item.command.key)
            return try MCPBatchTaskResultFixtures.source(text)
        }
        let uncertain = kind == "pending" || kind == "uncertain"
        let outcome = uncertain ? "uncertain" : kind
        let accepted = kind == "rejected" ? "false" : "true"
        let retry = uncertain ? "reconcile" : (kind == "rejected" ? "new_request_new_key" : "retry_same_request")
        return try MCPBatchTaskResultFixtures.source("""
        {"contractVersion":1,"tool":"\(item.operation)","idempotencyKey":"\(item.command.key)",\
        "outcome":"\(outcome)","accepted":\(accepted),\
        "error":{"code":"TEST_STOP","message":"Original stop"},"retryAction":"\(retry)",\
        "unknown":{"adjacent":9007199254740993,"nullable":null}}
        """, isError: true)
    }

    static func assertMappings(_ report: MCPBatchTaskCoordinator.Report, request: MCPBatchTaskRequest) {
        #expect(report.entries.count == request.items.count)
        for (entry, item) in zip(report.entries, request.items) {
            #expect(entry.index == item.index)
            #expect(entry.itemId.utf8.elementsEqual(item.itemId.utf8))
            #expect(entry.operation.utf8.elementsEqual(item.operation.utf8))
            #expect(entry.originalKey.utf8.elementsEqual(item.command.key.utf8))
            #expect(entry.taskID == item.targetTaskId)
        }
    }
}
#endif
