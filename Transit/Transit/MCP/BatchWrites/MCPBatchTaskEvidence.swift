#if os(macOS)
import Foundation

/// Establishes supported saved commitment from immutable source evidence only.
/// This does not certify current content, retention or a whole-batch result.
nonisolated enum MCPBatchTaskEvidence {
    nonisolated enum Kind: Sendable { case committed, itemResult, unavailable }

    nonisolated struct Assessment: Sendable {
        let kind: Kind
        let source: MCPResultSource
        var canAdvance: Bool { kind == .committed }
    }

    static func assess(
        source: MCPResultSource, operation: String, originalKey: String,
        taskID: UUID, requiresStatusComment: Bool
    ) -> Assessment {
        Assessment(kind: inspect(source, operation: operation, originalKey: originalKey,
                                 taskID: taskID, requiresStatusComment: requiresStatusComment), source: source)
    }

    private static func inspect(
        _ source: MCPResultSource, operation: String, originalKey: String,
        taskID: UUID, requiresStatusComment: Bool
    ) -> Kind {
        let root = source.document?.value
        guard source.kind == .json, source.evidence == .established,
            MCPBatchTaskEvidenceValidation.numberIsOne(member("contractVersion", in: root)),
            exact(string(member("tool", in: root)), operation),
            exact(string(member("idempotencyKey", in: root)), originalKey)
        else { return .unavailable }
        if let outcome = string(member("outcome", in: root)), outcome != "committed" {
            let supported = supportedFailure(root, outcome: outcome, isError: source.originalIsError)
            return supported ? .itemResult : .unavailable
        }
        guard exact(string(member("outcome", in: root)), "committed"),
            member("accepted", in: root) == .boolean(true), source.originalIsError != true,
            absentOrNull(member("error", in: root)), absentOrNull(member("retryAction", in: root)),
            let entityID = uuid(member("entityId", in: root)),
            let record = member("record", in: root), validRecord(record, taskID: taskID),
            savedIdentityMatches(operation: operation, entityID: entityID, record: record, taskID: taskID),
            !requiresStatusComment || (operation == "update_task_status" &&
                validRecord(member("comment", in: root), taskID: taskID) &&
                uuid(member("id", in: member("comment", in: root))) != nil),
            let completed = MCPBatchTaskEvidenceValidation.timestamp(member("completedAt", in: root)),
            let expiry = MCPBatchTaskEvidenceValidation.timestamp(member("replayExpiresAt", in: root)),
            expiry > completed
        else { return .unavailable }
        return .committed
    }

    private static func absentOrNull(_ value: MCPJSONValue?) -> Bool {
        value == nil || value == .null
    }

    private static func supportedFailure(_ root: MCPJSONValue?, outcome: String, isError: Bool?) -> Bool {
        guard isError == true, let error = member("error", in: root),
            let code = string(member("code", in: error)), !code.isEmpty,
            string(member("message", in: error)) != nil,
            let retry = string(member("retryAction", in: root))
        else { return false }
        let accepted = member("accepted", in: root)
        switch outcome {
        case "rejected":
            return (accepted == .boolean(false) || accepted == .boolean(true)) &&
                ["new_request_new_key", "retry_same_request"].contains(retry)
        case "in_progress":
            return accepted == .boolean(true) && retry == "retry_same_request"
        case "uncertain":
            return (accepted == .boolean(true) || accepted == .null) &&
                retry == "reconcile"
        default: return false
        }
    }

    private static func savedIdentityMatches(
        operation: String, entityID: UUID, record: MCPJSONValue, taskID: UUID
    ) -> Bool {
        switch operation {
        case "update_task", "update_task_status": return entityID == taskID
        case "add_comment": return uuid(member("id", in: record)) == entityID
        default: return false
        }
    }

    private static func validRecord(_ value: MCPJSONValue?, taskID: UUID) -> Bool {
        uuid(member("taskId", in: value)) == taskID &&
            MCPBatchTaskEvidenceValidation.revision(member("revision", in: value))
    }

    private static func member(_ name: String, in value: MCPJSONValue?) -> MCPJSONValue? {
        guard case .object(let members) = value else { return nil }
        return members.first { $0.name.unicodeScalars.elementsEqual(name.unicodeScalars) }?.value
    }

    private static func string(_ value: MCPJSONValue?) -> String? {
        guard case .string(let value) = value else { return nil }
        return value
    }

    private static func exact(_ value: String?, _ expected: String) -> Bool {
        value?.unicodeScalars.elementsEqual(expected.unicodeScalars) == true
    }

    private static func uuid(_ value: MCPJSONValue?) -> UUID? {
        string(value).flatMap(UUID.init(uuidString:))
    }
}
#endif
