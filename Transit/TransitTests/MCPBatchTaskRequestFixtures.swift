#if os(macOS)
import Foundation
import Testing
@testable import Transit

/// JSON and admitted-item counters only; no stores, models or write services.
@MainActor enum MCPBatchTaskRequestFixtures {
    static let revision = "r1:" + String(repeating: "a", count: 64)

    static func taskID(_ index: Int) -> String {
        String(format: "12345678-1234-4123-a123-%012d", index + 1)
    }

    static func item(_ index: Int = 0, operation: String = "update_task") -> [String: Any] {
        var arguments: [String: Any] = ["taskId": taskID(index), "idempotencyKey": "batch.key.\(index)"]
        if operation != "add_comment" { arguments["expectedRevision"] = revision }
        if operation == "update_task" { arguments["name"] = " Original name " }
        if operation == "update_task_status" { arguments["status"] = "done" }
        if operation == "add_comment" {
            arguments["content"] = " Original reason "
            arguments["authorName"] = " Agent "
        }
        return ["itemId": "caller.\(index)", "operation": operation, "arguments": arguments]
    }

    static func document(mode: Any = "execute", items: [[String: Any]]) throws -> MCPJSONDocument {
        try document(["mode": mode, "items": items])
    }

    static func document(_ value: Any) throws -> MCPJSONDocument {
        try MCPJSONDocument.parse(JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]))
    }

    static func valid(_ document: MCPJSONDocument) throws -> MCPBatchTaskRequest {
        switch try MCPBatchTaskRequest.parse(document) {
        case .valid(let request): return request
        case .invalid(let diagnostics):
            Issue.record("Expected valid whole shape, got \(diagnostics.map(\.field))")
            throw MCPResultBoundaryError.unsupportedEvidence
        }
    }

    static func invalid(_ document: MCPJSONDocument, index: Int? = nil, itemId: String? = nil,
                        field: String? = nil) throws {
        switch try MCPBatchTaskRequest.parse(document) {
        case .valid: Issue.record("Malformed whole shape must not be admitted")
        case .invalid(let diagnostics):
            #expect(!diagnostics.isEmpty)
            #expect(diagnostics.allSatisfy { $0.code == "INVALID_INPUT" && !$0.field.isEmpty })
            if let index {
                #expect(diagnostics.contains { $0.index == index && (itemId == nil || $0.itemId == itemId) })
            }
            if let field { #expect(diagnostics.contains { $0.field == field }) }
        }
    }

    static func field(_ name: String, in value: MCPJSONValue?) -> MCPJSONValue? {
        guard case .object(let members) = value else { return nil }
        return members.first { $0.name == name }?.value
    }

    static func array(_ value: MCPJSONValue?) throws -> [MCPJSONValue] {
        guard case .array(let elements) = value else {
            Issue.record("Expected a schema array"); throw MCPResultBoundaryError.unsupportedEvidence
        }
        return elements
    }

    static func names(_ value: MCPJSONValue?) throws -> Set<String> {
        Set(try array(value).compactMap {
            if case .string(let name) = $0 { return name }
            return nil
        })
    }

    static func permuted(_ items: [[String: Any]], seed: UInt64) -> [[String: Any]] {
        var shuffled = items
        var state = seed
        for index in stride(from: shuffled.count - 1, through: 1, by: -1) {
            state = state &* 6_364_136_223_846_793_005 &+ 1
            shuffled.swapAt(index, Int(state % UInt64(index + 1)))
        }
        return shuffled
    }
}
#endif
