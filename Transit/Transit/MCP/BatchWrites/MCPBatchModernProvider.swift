#if os(macOS)
import Foundation

/// One application batch in one admitted tools/call. Transport notification and
/// capability checks stay with the modern owner; no read deadline or retention.
@MainActor enum MCPBatchModernProvider {
    static func call(_ modern: MCPModernRequest, handler: MCPToolHandler) async throws -> MCPResultResponseSelection {
        guard case .callTool(let name, .applicationBatch) = modern.method,
              name.utf8.elementsEqual("mutate_tasks".utf8) else { throw MCPResultBoundaryError.unsupportedEvidence }
        let arguments: MCPJSONValue
        if case .object(let members) = modern.params,
           members.filter({ $0.name.utf8.elementsEqual("arguments".utf8) }).count == 1,
           let supplied = MCPBatchTaskInputValue.member("arguments", in: members) {
            arguments = supplied
        } else { arguments = .null }
        switch try MCPBatchTaskRequest.parse(validatedValue: arguments) {
        case .invalid(let diagnostics):
            let source = try MCPBatchTaskResult.invalidInput(diagnostics)
            return .normal(try MCPResultProviderSelection.encode(outcome: .init(source: source,
                context: .init(tool: "mutate_tasks", semanticFailure: nil, mutationRecovery: nil, entityPositions: [])),
                id: modern.id, metadata: nil))
        case .valid(let request):
            if request.mode == .dryRun {
                let report = try handler.batchPreview(request)
                let source = try MCPBatchTaskResult.preview(request, report: report)
                return .normal(try MCPResultProviderSelection.encode(outcome: .init(source: source,
                    context: MCPBatchTaskContext.normal(request, recovery: nil)), id: modern.id, metadata: nil))
            }
            let items = request.items.map {
                MCPBatchRecoveryItem(index: $0.index, itemId: $0.itemId, operation: $0.operation,
                    originalKey: .init(tool: $0.command.tool, idempotencyKey: $0.command.key),
                    targetTaskId: $0.targetTaskId)
            }
            let prepared = try MCPBatchTaskPreparedResponse.prepare(id: modern.id, items: items, metadata: nil)
            return try await MCPBatchTaskResponse.execute(request, prepared: prepared,
                executor: { item in try await handler.executeBatchItem(item) },
                encodeOutcome: handler.batchResultEncoder ?? MCPResultProviderSelection.encode)
        }
    }
}
#endif
