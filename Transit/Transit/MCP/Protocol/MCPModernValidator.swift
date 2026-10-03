#if os(macOS)
import Foundation

/// Performs only protocol validation and immutable availability classification.
nonisolated enum MCPModernValidator {
    static func validate(
        _ input: MCPModernRequestInput,
        availability: MCPModernAvailability
    ) throws -> MCPModernRequest {
        throw MCPResultBoundaryError.notImplemented
    }
}
#endif
