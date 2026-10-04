#if os(macOS)
import Foundation

/// The caller supplies an admitted immutable request and complete capability.
/// No item can run before preparation; later failures only select ready bytes.
@MainActor enum MCPBatchTaskResponse {
    static func execute(
        _ request: MCPBatchTaskRequest, prepared: MCPBatchTaskPreparedResponse,
        writeCoordinator: MCPWriteCoordinator,
        encodeOutcome: MCPResultProviderSelection.EncodeOutcome = MCPResultProviderSelection.encode,
        shouldDeliver: @escaping @Sendable () -> Bool = { !Task.isCancelled }
    ) async throws -> MCPResultResponseSelection {
        let batch = MCPBatchTaskCoordinator(preparedResponse: prepared, writeCoordinator: writeCoordinator)
        return try await select(request, prepared: prepared, batch: batch,
                                encodeOutcome: encodeOutcome, shouldDeliver: shouldDeliver)
    }

    static func execute(
        _ request: MCPBatchTaskRequest, prepared: MCPBatchTaskPreparedResponse,
        executor: @escaping MCPBatchTaskCoordinator.Executor,
        encodeOutcome: MCPResultProviderSelection.EncodeOutcome = MCPResultProviderSelection.encode,
        shouldDeliver: @escaping @Sendable () -> Bool = { !Task.isCancelled }
    ) async throws -> MCPResultResponseSelection {
        let batch = MCPBatchTaskCoordinator(preparedResponse: prepared, executor: executor)
        return try await select(request, prepared: prepared, batch: batch,
                                encodeOutcome: encodeOutcome, shouldDeliver: shouldDeliver)
    }

    private static func select(
        _ request: MCPBatchTaskRequest, prepared: MCPBatchTaskPreparedResponse, batch: MCPBatchTaskCoordinator,
        encodeOutcome: MCPResultProviderSelection.EncodeOutcome,
        shouldDeliver: @escaping @Sendable () -> Bool
    ) async throws -> MCPResultResponseSelection {
        // Normal public positions never enter the fixed compact-fallback context.
        let context = MCPBatchTaskContext.normal(request, recovery: prepared.context.mutationRecovery)
        return try await prepared.select(encodeOutcome: encodeOutcome, shouldDeliver: shouldDeliver,
            dispatch: { @MainActor in
                let report = try await batch.run(request)
                let source = try MCPBatchTaskResult.execution(request, report: report)
                return MCPResultProviderOutcome(source: source, context: context)
            })
    }
}
#endif
