#if os(macOS)
import Foundation

extension MCPBatchTaskCoordinator {
    /// Captures the stop fact for this invocation only. Receipt replay does not
    /// manufacture a pending-edit signal or fetch current domain records.
    convenience init(
        preparedResponse: MCPBatchTaskPreparedResponse, writeCoordinator: MCPWriteCoordinator,
        observedCancellation: @escaping @MainActor () -> Bool = { Task.isCancelled }
    ) {
        self.init(preparedResponse: preparedResponse, executor: { item in
            var pendingEditsStop = false
            let policy = MCPBatchWritePolicy(onPendingEditsStop: { pendingEditsStop = true })
            let result = await writeCoordinator.execute(tool: item.command.tool,
                arguments: item.command.arguments, batchPolicy: policy)
            guard result.content.count == 1, let text = result.content.first?.text else {
                throw MCPResultBoundaryError.unsupportedEvidence
            }
            let source = try MCPResultAdapter.source(text: text, isError: result.isError,
                origin: .retainedJSON, evidence: .established)
            return Execution(source: source, pendingEditsStop: pendingEditsStop)
        }, observedCancellation: observedCancellation)
    }
}
#endif
