#if os(macOS)
import Foundation

/// MCP-specific conditional author validation and symbolic status effects.
/// No model, timestamp or comment identity is created by this value boundary.
@MainActor enum MCPTaskMutationValidation {
    nonisolated enum TimestampAction: String, Sendable { case unchanged, update, set, clear }

    nonisolated struct Status: Sendable, Equatable {
        let targetStatus: String
        let statusChanged: Bool
        let comment: CommentInputValidation.Input?
        let lastStatusChange: TimestampAction
        let completion: TimestampAction
    }

    static func status(
        currentStatus: String, targetStatus: String,
        comment: String?, authorName: String?
    ) throws -> Status {
        guard let target = TaskStatus(rawValue: targetStatus) else {
            throw MCPWriteFailure("INVALID_STATUS", "Invalid task status")
        }
        if comment != nil,
           authorName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            throw MCPWriteFailure("INVALID_INPUT", "authorName is required when comment is provided")
        }
        let normalized: CommentInputValidation.Input?
        if let comment, !comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            normalized = try CommentInputValidation.normalize(content: comment, authorName: authorName ?? "")
        } else { normalized = nil }
        let current = TaskStatus(rawValue: currentStatus) ?? .idea
        let changed = current != target
        let completion: TimestampAction
        if !changed {
            completion = .unchanged
        } else if target.isTerminal {
            completion = .set
        } else if current.isTerminal {
            completion = .clear
        } else {
            completion = .unchanged
        }
        return Status(targetStatus: target.rawValue, statusChanged: changed, comment: normalized,
                      lastStatusChange: changed ? .update : .unchanged, completion: completion)
    }
}
#endif
