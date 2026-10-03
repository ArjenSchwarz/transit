#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor
extension MCPTestHelpers {
    /// Opt-in fixture for legacy domain tests. Raw protocol and missing-safety tests use toolCallRequest.
    static func protectedToolCallRequest(
        in context: ModelContext, tool: String, arguments: [String: Any], id: Int = 1
    ) throws -> JSONRPCRequest {
        guard MCPWriteCommand.protectedTools.contains(tool) else {
            return toolCallRequest(tool: tool, arguments: arguments, id: id)
        }
        var args = arguments
        args["idempotencyKey"] = args["idempotencyKey"] ?? freshWriteKey()
        if MCPWriteCommand.revisionTools.contains(tool), args["expectedRevision"] == nil {
            // A syntactically valid sentinel lets missing/malformed/ambiguous identifier tests
            // reach domain validation without fabricating a target or swallowing a fetch failure.
            var revision = "r1:" + String(repeating: "0", count: 64)
            if tool == "update_task" || tool == "update_task_status" {
                let records = try context.fetch(FetchDescriptor<TransitTask>()).filter { task in
                    if let displayID = IntentHelpers.parseIntValue(args["displayId"]) {
                        return task.permanentDisplayId == displayID
                    }
                    return task.id.uuidString == args["taskId"] as? String
                }
                if records.count == 1 { revision = try readRevision(records[0], in: context) }
            } else {
                let records = try context.fetch(FetchDescriptor<Milestone>()).filter { milestone in
                    if let displayID = IntentHelpers.parseIntValue(args["displayId"]) {
                        return milestone.permanentDisplayId == displayID
                    }
                    return milestone.id.uuidString == args["milestoneId"] as? String
                }
                if records.count == 1 { revision = try readRevision(records[0]) }
            }
            args["expectedRevision"] = revision
        }
        return toolCallRequest(tool: tool, arguments: args, id: id)
    }

    static func errorCode(_ response: JSONRPCResponse?) throws -> String {
        let result = try decodeResult(response)
        let error = try #require(result["error"] as? [String: Any])
        return try #require(error["code"] as? String)
    }

    /// Asserts the saved-outcome contract before exposing its record for domain assertions.
    static func decodeSavedRecord(_ response: JSONRPCResponse?) throws -> [String: Any] {
        let outcome = try decodeResult(response)
        #expect(outcome["contractVersion"] as? Int == 1)
        #expect(outcome["outcome"] as? String == "committed")
        #expect(outcome["accepted"] as? Bool == true)
        #expect(outcome["idempotencyKey"] is String)
        #expect(outcome["entityId"] is String)
        #expect(outcome["replayExpiresAt"] is String)
        let record = try #require(outcome["record"] as? [String: Any])
        #expect((record["revision"] as? String)?.hasPrefix("r1:") == true)
        return record
    }
}
#endif
