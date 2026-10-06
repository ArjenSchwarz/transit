#if os(macOS)
import Foundation

@MainActor final class MCPWriteFailure: Error {
    let code: String
    let message: String
    let currentRecord: [String: Any]?
    let currentRevisions: [String: String]?
    let affectedTaskIds: [UUID]?
    private(set) var diagnostics: [[String: String]]?

    init(_ code: String, _ message: String, currentRecord: [String: Any]? = nil,
         currentRevisions: [String: String]? = nil, affectedTaskIds: [UUID]? = nil) {
        self.code = code
        self.message = message
        self.currentRecord = currentRecord
        self.currentRevisions = currentRevisions
        self.affectedTaskIds = affectedTaskIds
    }

    static func selection(_ error: ConsolidationSelectionFailure) -> MCPWriteFailure {
        let result = MCPWriteFailure(error.code, error.message)
        result.diagnostics = error.diagnostics.map(\.json)
        return result
    }

    static func from(_ error: any Error) -> MCPWriteFailure {
        if let failure = error as? MCPWriteFailure { return failure }
        if error is CancellationError { return .init("CANCELLED", "The operation was cancelled") }
        if let error = error as? TaskUpdateValidationError {
            return .init(error.intentError.code, error.mcpMessage)
        }
        if let error = error as? ProjectLookupError {
            let mapped = IntentHelpers.mapProjectLookupError(error)
            return .init(mapped.code, mapped.hint)
        }
        if let error = error as? MilestoneService.Error {
            let mapped = IntentHelpers.mapMilestoneError(error)
            return .init(mapped.code, mapped.hint)
        }
        if let error = error as? TaskService.Error {
            return taskFailure(error)
        }
        if let error = error as? CommentService.Error {
            return .init(error == .taskNotFound ? "TASK_NOT_FOUND" : "INVALID_INPUT", "Invalid comment: \(error)")
        }
        if let error = error as? ProjectMutationError {
            switch error {
            case .invalidName: return .init("INVALID_INPUT", "Project name must not be empty or whitespace-only")
            case .duplicateName(let name):
                return .init("DUPLICATE_PROJECT_NAME", "A project named \"\(name)\" already exists")
            }
        }
        return .init("INTERNAL_ERROR", error.localizedDescription)
    }

    private static func taskFailure(_ error: TaskService.Error) -> MCPWriteFailure {
        switch error {
        case .taskNotFound: return .init("TASK_NOT_FOUND", error.localizedDescription)
        case .projectNotFound: return .init("PROJECT_NOT_FOUND", error.localizedDescription)
        case .milestoneProjectMismatch: return .init("MILESTONE_PROJECT_MISMATCH", error.localizedDescription)
        case .milestoneNotOpen: return .init("MILESTONE_NOT_OPEN", error.localizedDescription)
        case .duplicateDisplayID: return .init("DUPLICATE_TASK_IDENTIFIER", error.localizedDescription)
        default: return .init("INVALID_INPUT", error.localizedDescription)
        }
    }
}

enum MCPWriteOutcome {
    static func failure(
        tool: String, key: String?, failure: MCPWriteFailure,
        accepted: Bool?, outcome: String = "rejected", retryAction: String? = nil
    ) -> [String: Any] {
        var result: [String: Any] = [
            "contractVersion": 1, "tool": tool, "outcome": outcome,
            "accepted": accepted as Any? ?? NSNull(),
            "error": ["code": failure.code, "message": failure.message],
            "retryAction": retryAction ?? "new_request_new_key"
        ]
        if let diagnostics = failure.diagnostics {
            result["error"] = ["code": failure.code, "message": failure.message, "diagnostics": diagnostics]
        }
        result["idempotencyKey"] = key
        result["currentRecord"] = failure.currentRecord
        result["currentRevisions"] = failure.currentRevisions
        result["affectedTaskIds"] = failure.affectedTaskIds?.map(\.uuidString)
        return result
    }

    static func result(_ envelope: [String: Any], isError: Bool) -> MCPToolResult {
        // Envelopes contain only validated JSON values; callers use the throwing
        // encoder before committing terminal receipts.
        let text = (try? encode(envelope)) ?? "{\"error\":{\"code\":\"INTERNAL_ERROR\"},\"outcome\":\"uncertain\"}"
        return MCPToolResult(content: [.text(text)], isError: isError ? true : nil)
    }

    static func encode(_ envelope: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
        guard let string = String(data: data, encoding: .utf8) else { throw MCPCanonicalJSON.Error.invalidValue }
        return string
    }
}
#endif
