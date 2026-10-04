#if os(macOS)
import Foundation

/// Shared admission/capture binding only. Portfolio-owned helpers supply projection and retention.
extension MCPToolHandler {
    func preparePortfolioRead(arguments: [String: Any], service: MCPReadService,
                              operation: MCPReadOperation) async throws -> MCPPreparedToolRead {
        var policy = MCPReadPolicy.refreshIfNeeded
        do {
            let request = try MCPPortfolioSummaryRequest.parse(arguments)
            if case let .initial(_, _, _, requestedPolicy) = request { policy = requestedPolicy }
            if case let .continuation(_, requestedPolicy) = request { policy = requestedPolicy ?? policy }
            try requireReusableReadAvailability()
            switch request {
            case let .initial(_, _, project, requestedPolicy):
                policy = requestedPolicy
                let captureRequest = ReadCaptureRequest(projectSelectors: project.map { [$0] },
                    selection: .portfolio, completeness: .completePortfolio, includeComments: false)
                return try await service.prepareCapturedRead(request: captureRequest, policy: policy,
                    operation: operation) { [self] capsule, operation in
                    // Forward the original capsule, including its exact metadata bytes, without reconstruction.
                    try handlePortfolioSummary(request: request, capture: capsule, operation: operation)
                }
            case .replay:
                return try handlePortfolioSummary(request: request, capture: nil, operation: operation)
            case let .continuation(_, requestedPolicy):
                policy = requestedPolicy ?? policy
                return try handlePortfolioSummary(request: request, capture: nil, operation: operation)
            }
        } catch let error as MCPPortfolioRequestError {
            return try portfolioInputFailure(code: error.code, message: error.message)
        } catch MCPReadCaptureError.projectNotFound {
            return try portfolioInputFailure(code: "PROJECT_NOT_FOUND", message: "Project not found")
        } catch MCPReadCaptureError.ambiguousProject {
            return try portfolioInputFailure(code: "AMBIGUOUS_PROJECT", message: "Project selector is ambiguous")
        } catch {
            return try service.prepareFailure(error, tool: "query_project_summaries",
                                              operation: operation, policy: policy)
        }
    }

    func prepareSnapshotRead(arguments: [String: Any], service: MCPReadService,
                             operation: MCPReadOperation) throws -> MCPPreparedToolRead {
        var policy = MCPReadPolicy.refreshIfNeeded
        do {
            let request = try MCPSnapshotTaskQueryRequest.parse(arguments)
            if case let .continuation(_, requestedPolicy) = request { policy = requestedPolicy ?? policy }
            try requireReusableReadAvailability()
            // Retained snapshot/cursor reads never capture or reassess import freshness.
            return try handleSnapshotTaskQuery(request: request, operation: operation)
        } catch let error as MCPSnapshotTaskQueryError {
            switch error {
            case .invalidInput:
                return try portfolioInputFailure(code: "INVALID_INPUT", message: "Invalid snapshot task arguments")
            case .incompatible:
                return try portfolioInputFailure(code: "SNAPSHOT_INCOMPATIBLE",
                                                  message: "Arguments are incompatible with the retained snapshot")
            case .invalidCursor:
                return try portfolioInputFailure(code: "INVALID_CURSOR", message: "Invalid reusable cursor")
            }
        } catch {
            return try service.prepareFailure(error, tool: "query_tasks", operation: operation, policy: policy)
        }
    }

    private func requireReusableReadAvailability() throws {
        if let error = reusableSnapshotLifecycleFailure { throw error }
        _ = try reusableSnapshots.get()
    }

    private func portfolioInputFailure(code: String, message: String) throws -> MCPPreparedToolRead {
        try MCPPreparedToolRead(text: IntentHelpers.encodeJSON(["error": ["code": code, "message": message]]),
                                isError: true)
    }
}
#endif
