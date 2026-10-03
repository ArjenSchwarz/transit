#if os(macOS)
import Foundation

nonisolated struct MCPReadToolRequest: Sendable {
    let tool: String
    let arguments: [String: AnyCodable]
}

extension MCPToolHandler {
    /// Task 13 routes covered requests here after independent transport admission.
    /// Existing direct dispatch remains the pre-integration baseline until that wiring.
    func prepareCoveredRead(_ request: MCPReadToolRequest,
                            operation: MCPReadOperation) async throws -> MCPPreparedToolRead {
        guard let readService else {
            let metadata = ReadFailureMetadata(requestId: operation.id.uuidString, category: .storageFailure,
                read: ReadExecutionMetadata(policy: .refreshIfNeeded, refreshOutcome: .unavailable, budgetMs: 5_000))
            return try MCPPreparedToolRead(text: "Saved read capture service is unavailable", isError: true,
                                           metadata: .failure(metadata))
        }
        return try await readService.prepare(tool: request.tool,
            arguments: request.arguments.mapValues(\.value), operation: operation)
    }
}
#endif
