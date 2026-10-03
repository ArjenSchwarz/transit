#if os(macOS)
import Foundation

/// Supplemental classification never changes acceptance or retry facts in source.
nonisolated struct MCPResultClassification {
    let evidence: MCPResultEvidence
    let category: MCPResultErrorCategory?
    let recovery: MCPResultRecovery?

    static func inspect(_ source: MCPResultSource, context: MCPResultContext,
                        checkpoint: @Sendable () throws -> Void) throws -> MCPResultClassification {
        let value = source.document?.value
        let error = try MCPResultInspection.member("error", in: value, checkpoint: checkpoint)
        let code = MCPResultInspection.string(try MCPResultInspection.member("code", in: error, checkpoint: checkpoint))
        let outcome = MCPResultInspection.string(
            try MCPResultInspection.member("outcome", in: value, checkpoint: checkpoint))
        let retry = MCPResultInspection.string(
            try MCPResultInspection.member("retryAction", in: value, checkpoint: checkpoint))
        let accepted = MCPResultInspection.boolean(
            try MCPResultInspection.member("accepted", in: value, checkpoint: checkpoint))
        let contradictory = contradicts(outcome: outcome, accepted: accepted,
                                        retry: retry, isError: source.originalIsError)
        let unsupportedOutcome = outcome.map { !["committed", "rejected", "in_progress", "uncertain"].contains($0) }
            ?? false
        let evidence: MCPResultEvidence = contradictory || unsupportedOutcome ? .unestablished : source.evidence
        var category = context.semanticFailure?.category ?? code.flatMap { categories[$0] }
        if category == nil, source.originalIsError == true || code != nil { category = .unclassifiedHistorical }
        if evidence == .unestablished {
            category = context.mutationRecovery == nil ? .unclassifiedHistorical : .outcomeUncertain
        }
        if outcome == "uncertain" { category = .outcomeUncertain }
        if context.mutationRecovery != nil, category == .serializationFailure { category = .outcomeUncertain }
        let recovery = recovery(category: category, evidence: evidence, outcome: outcome, retry: retry,
                                mutation: context.mutationRecovery)
        return MCPResultClassification(evidence: evidence, category: category, recovery: recovery)
    }

    /// Consistency of already reported facts, not a receipt acceptance validator.
    private static func contradicts(outcome: String?, accepted: Bool?, retry: String?, isError: Bool?) -> Bool {
        switch outcome {
        case "committed": return accepted == false || isError == true || retry == "new_request_new_key"
        case "in_progress": return accepted == false || retry == "new_request_new_key"
        case "uncertain": return retry == "new_request_new_key"
        case "rejected": return retry == "reconcile"
        default: return false
        }
    }

    private static func recovery(category: MCPResultErrorCategory?, evidence: MCPResultEvidence,
                                 outcome: String?, retry: String?,
                                 mutation: MCPMutationRecoveryContext?) -> MCPResultRecovery? {
        guard let category else { return nil }
        if let mutation {
            let uncertain = evidence == .unestablished || category == .outcomeUncertain ||
                category == .unclassifiedHistorical || category == .internalFailure
            let sourceRetry = outcome == "rejected" && retry == "new_request_new_key" ||
                ["rejected", "in_progress"].contains(outcome ?? "") && retry == "retry_same_request"
            if !uncertain, sourceRetry {
                return MCPResultRecovery(direction: .followSource, mutation: mutation)
            }
            if case .unprotectedMaintenance = mutation {
                return MCPResultRecovery(direction: .reconcileMaintenance, mutation: mutation)
            }
            return MCPResultRecovery(direction: .reconcileOriginalWrite, mutation: mutation)
        }
        switch category {
        case .invalidCursor, .expiredCursor:
            return MCPResultRecovery(direction: .restartRead, mutation: nil)
        case .storageFailure, .incoherentCapture, .admissionBusy, .deadlineExceeded,
             .retentionCapacity, .serializationFailure:
            return MCPResultRecovery(direction: .retryIdenticalRead, mutation: nil)
        default: return nil
        }
    }

    private static let categories: [String: MCPResultErrorCategory] = [
        "INVALID_INPUT": .invalidInput, "INVALID_STATUS": .invalidInput, "INVALID_TYPE": .invalidInput,
        "INVALID_PRIORITY": .invalidInput, "MILESTONE_PROJECT_MISMATCH": .invalidInput,
        "TASK_NOT_FOUND": .notFound, "PROJECT_NOT_FOUND": .notFound, "MILESTONE_NOT_FOUND": .notFound,
        "AMBIGUOUS_TASK_ID": .ambiguousIdentity, "AMBIGUOUS_PROJECT": .ambiguousIdentity,
        "AMBIGUOUS_MILESTONE": .ambiguousIdentity, "AMBIGUOUS_FILTER": .ambiguousIdentity,
        "DUPLICATE_MILESTONE_NAME": .ambiguousIdentity, "DUPLICATE_PROJECT_NAME": .ambiguousIdentity,
        "DUPLICATE_TASK_IDENTIFIER": .ambiguousIdentity, "MILESTONE_NOT_OPEN": .invalidInput,
        "REVISION_CONFLICT": .revisionConflict, "IDEMPOTENCY_KEY_REUSED": .keyConflict,
        "PERSISTENCE_UNAVAILABLE": .storageFailure, "QUERY_FAILED": .storageFailure,
        "READ_BUSY": .admissionBusy, "QUERY_UNAVAILABLE": .admissionBusy,
        "STORE_BUSY": .admissionBusy, "OPERATION_IN_PROGRESS": .admissionBusy,
        "READ_TIMEOUT": .deadlineExceeded, "QUERY_CAPACITY_EXCEEDED": .retentionCapacity,
        "INVALID_CURSOR": .invalidCursor, "QUERY_EXPIRED": .expiredCursor,
        "OUTCOME_UNCERTAIN": .outcomeUncertain, "INTERNAL_ERROR": .internalFailure,
        "INTERRUPTED_BEFORE_COMMIT": .internalFailure
    ]
}
#endif
