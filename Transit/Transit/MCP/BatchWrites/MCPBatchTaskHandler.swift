#if os(macOS)
import Foundation
import SwiftData

/// Feature-local mode selection. Complete response preparation remains a
/// prerequisite; aggregate serialization and modern dispatch are later seams.
@MainActor enum MCPBatchTaskHandler {
    enum Error: Swift.Error { case executionUnavailable }

    enum Result {
        case invalidInput([MCPBatchTaskRequest.Diagnostic])
        case preview(MCPBatchTaskRequest, MCPBatchTaskPreview.Report)
        case execution(MCPBatchTaskRequest, MCPBatchTaskCoordinator.Report)
    }

    static func handle(
        arguments: MCPJSONValue, container: ModelContainer, persistence: PersistenceAvailability,
        coordinator: MCPBatchTaskCoordinator? = nil, includeComments: Bool = true,
        reads: MCPBatchTaskPreview.Reads = .init()
    ) async throws -> Result {
        switch try MCPBatchTaskRequest.parse(validatedValue: arguments) {
        case .invalid(let diagnostics): return .invalidInput(diagnostics)
        case .valid(let request):
            switch request.mode {
            case .dryRun:
                return .preview(request, try MCPBatchTaskPreview.evaluate(request, container: container,
                    persistence: persistence, includeComments: includeComments, reads: reads))
            case .execute:
                guard let coordinator else { throw Error.executionUnavailable }
                return .execution(request, try await coordinator.run(request))
            }
        }
    }
}
#endif
