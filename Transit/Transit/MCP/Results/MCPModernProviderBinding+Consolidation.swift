#if os(macOS)
import Foundation

extension MCPModernProviderBinding {
    nonisolated static func compactRecoveryText(_ request: JSONRPCRequest, tool: String,
                                                encodedMessage: String) -> String {
        let error = "{\"error\":{\"code\":\"OUTCOME_UNCERTAIN\",\"message\":" + encodedMessage + "}"
        guard tool == "undo_task_consolidation",
              let params = request.params?.value as? [String: Any],
              let arguments = params["arguments"] as? [String: Any],
              let raw = arguments["operationId"] as? String, let operation = UUID(uuidString: raw) else {
            return error + "}"
        }
        return error + ",\"operationId\":\"" + operation.uuidString + "\"}"
    }

}
#endif
