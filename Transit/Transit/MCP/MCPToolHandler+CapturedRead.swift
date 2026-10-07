#if os(macOS)
import Foundation

nonisolated struct MCPReadToolRequest: Sendable {
    let tool: String
    let arguments: [String: AnyCodable]

    var hasRetainedReadReference: Bool {
        ["query_tasks", "query_project_summaries"].contains(tool)
            && (arguments["snapshotId"] != nil || arguments["cursor"] != nil)
    }
}

extension MCPToolHandler {
    /// Covered tools prepare privately after independent transport admission.
    func prepareCoveredRead(_ request: MCPReadToolRequest,
                            operation: MCPReadOperation) async throws -> MCPPreparedToolRead {
        operation.finishActorQueue()
        // Retired references preserve their typed no-capture lookup errors.
        guard taskQueryAdmissionOpen || request.hasRetainedReadReference else {
            let metadata = ReadFailureMetadata(requestId: operation.id.uuidString, category: .busy,
                read: ReadExecutionMetadata(policy: .refreshIfNeeded, refreshOutcome: .unavailable, budgetMs: 5_000))
            let text = IntentHelpers.encodeJSON(["error": ["code": "READ_BUSY", "message": "READ_BUSY"]])
            return try MCPPreparedToolRead(text: text, isError: true, metadata: .failure(metadata))
        }
        guard let readService else {
            let metadata = ReadFailureMetadata(requestId: operation.id.uuidString, category: .storageFailure,
                read: ReadExecutionMetadata(policy: .refreshIfNeeded, refreshOutcome: .unavailable, budgetMs: 5_000))
            return try MCPPreparedToolRead(text: "Saved read capture service is unavailable", isError: true,
                                           metadata: .failure(metadata),
                                           providerEvidence: MCPResultProviderEvidence(
                                            origin: .plainText, evidence: .established))
        }
        let arguments = request.arguments.mapValues(\.value)
        if ["preview_task_consolidation", "preview_task_consolidation_undo"].contains(request.tool) {
            do {
                guard let consolidationPreviewAdapter else { throw ConsolidationPlanningError.unavailableEvidence }
                return try await consolidationPreviewAdapter.prepare(tool: request.tool,
                    arguments: arguments, operation: operation)
            } catch {
                return try readService.prepareFailure(error, tool: request.tool, operation: operation,
                    policy: MCPReadRefreshPolicy.parse(arguments["readPolicy"]) ?? .refreshIfNeeded)
            }
        }
        if request.tool == "query_project_summaries" {
            return try await preparePortfolioRead(arguments: arguments, service: readService, operation: operation)
        }
        if request.tool == "query_tasks",
           arguments["snapshotId"] != nil
            || (arguments["cursor"] as? String).map({ MCPCursorFamily.classify($0) == .reusable }) == true {
            return try prepareSnapshotRead(arguments: arguments, service: readService, operation: operation)
        }
        return try await readService.prepare(tool: request.tool, arguments: arguments, operation: operation)
    }
}
#endif
