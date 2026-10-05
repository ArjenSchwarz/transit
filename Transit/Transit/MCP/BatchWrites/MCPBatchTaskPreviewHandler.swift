#if os(macOS)
import Foundation
import SwiftData

/// Feature-local value boundary; shared modern dispatch is integrated later.
/// Execute requests deliberately have no coordinator at this preview seam.
@MainActor enum MCPBatchTaskPreviewHandler {
    enum Result {
        case invalidInput([MCPBatchTaskRequest.Diagnostic])
        case preview(MCPBatchTaskRequest, MCPBatchTaskPreview.Report)
        case executionUnavailable
    }

    static func handle(
        arguments: MCPJSONValue, container: ModelContainer,
        persistence: PersistenceAvailability, includeComments: Bool = true,
        reads: MCPBatchTaskPreview.Reads = .init()
    ) throws -> Result {
        switch try MCPBatchTaskRequest.parse(validatedValue: arguments) {
        case .invalid(let diagnostics): return .invalidInput(diagnostics)
        case .valid(let request):
            guard request.mode == .dryRun else { return .executionUnavailable }
            return .preview(request, try MCPBatchTaskPreview.evaluate(request, container: container,
                persistence: persistence, includeComments: includeComments, reads: reads))
        }
    }
}
#endif
