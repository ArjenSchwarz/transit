#if os(macOS)
import Foundation

nonisolated enum MCPModernProviderPreflight: Sendable {
    case ready(MCPResultContext)
    case rejected(MCPToolResult)
    case requestError(JSONRPCError)
}

/// Common value-only binding; providers continue to own storage, receipts and publication.
nonisolated enum MCPModernProviderBinding {
    /// Owner callbacks supply every private page before reserving publication.
    /// Deliberate task16 RED boundary; task17 supplies immutable value preparation.
    static func prepareReadPages(_ pages: [MCPPreparedToolRead], tool: String,
                                 operation: MCPReadOperation) throws -> [MCPResultPreparedPage] {
        throw MCPResultPreparationError.notImplemented
    }

    static func availability(maintenanceEnabled: Bool) -> MCPModernAvailability {
        let covered: Set<String> = ["query_tasks", "query_milestones", "get_projects", "query_project_summaries"]
        return MCPModernAvailability(tools: MCPToolDefinitions.tools(includingMaintenance: maintenanceEnabled).map {
            let execution: MCPModernToolExecution
            if covered.contains($0.name) {
                execution = .coveredRead
            } else if $0.name == "scan_duplicate_display_ids" {
                execution = .ordinaryRead
            } else if $0.name == "reassign_duplicate_display_ids" {
                execution = .unprotectedMaintenance
            } else {
                execution = .protectedWrite
            }
            return MCPModernAvailableTool(name: $0.name, execution: execution)
        })
    }

    static func call(_ request: JSONRPCRequest, tool: String, handler: MCPToolHandler,
                     maintenanceEnabled: Bool) async throws -> MCPResultResponseSelection {
        guard let id = request.id else { throw MCPResultBoundaryError.unsupportedEvidence }
        switch await handler.modernPreflight(request, tool: tool) {
        case .requestError(let error):
            return .normal(try JSONEncoder().encode(JSONRPCResponse(id: id, result: nil, error: error)))
        case .rejected(let result):
            let context = MCPResultContext(tool: tool, semanticFailure: nil,
                mutationRecovery: nil, entityPositions: [])
            let outcome = try MCPResultProviderAdapters.outcome(result: result, context: context,
                origin: .generatedJSON)
            return .normal(try MCPResultProviderSelection.encode(outcome: outcome, id: id, metadata: nil))
        case .ready(let context):
            if context.mutationRecovery != nil {
                let message: String
                if case .unprotectedMaintenance = context.mutationRecovery {
                    message = "Partial effects are possible. Run a fresh scan_duplicate_display_ids "
                        + "and inspect before any further reassignment."
                } else {
                    message = "Reconcile using the original tool and idempotency key; do not retry with a fresh key."
                }
                guard let encodedMessage = String(data: try JSONEncoder().encode(message), encoding: .utf8) else {
                    throw MCPResultBoundaryError.unsupportedEvidence
                }
                let fallbackText = "{\"error\":{\"code\":\"OUTCOME_UNCERTAIN\",\"message\":" + encodedMessage + "}}"
                let fallback = try MCPResultAdapter.source(
                    text: fallbackText,
                    isError: true, origin: .generatedJSON, evidence: .unestablished)
                return try await MCPResultProviderSelection.mutation(id: id, context: context,
                    metadata: nil, fallbackSource: fallback) {
                        try await dispatch(request, context: context, handler: handler,
                            maintenanceEnabled: maintenanceEnabled)
                    }
            }
            let outcome = try await dispatch(request, context: context, handler: handler,
                maintenanceEnabled: maintenanceEnabled)
            return .normal(try MCPResultProviderSelection.encode(outcome: outcome, id: id, metadata: nil))
        }
    }

    private static func dispatch(_ request: JSONRPCRequest, context: MCPResultContext,
                                 handler: MCPToolHandler,
                                 maintenanceEnabled: Bool) async throws -> MCPResultProviderOutcome {
        guard let response = await handler.handle(request, maintenanceEnabled: maintenanceEnabled),
              response.error == nil, let result = response.result?.value as? MCPToolResult else {
            throw MCPResultBoundaryError.unsupportedEvidence
        }
        let origin: MCPResultOrigin
        if case .protectedWrite = context.mutationRecovery {
            origin = .retainedJSON
        } else {
            origin = .generatedJSON
        }
        let outcome = try MCPResultProviderAdapters.outcome(result: result, context: context, origin: origin)
        return try declaringPositions(outcome)
    }

    static func read(_ prepared: MCPPreparedToolRead, id: JSONRPCId, tool: String,
                     operation: MCPReadOperation? = nil) throws -> Data {
        let checkpoint: @Sendable () throws -> Void = {
            if let operation, !operation.shouldContinue() { throw CancellationError() }
            try Task.checkCancellation()
        }
        var failure: MCPResultFailure?
        if case .some(.failure(let value)) = prepared.result.metadata?.read {
            let category: MCPResultErrorCategory
            switch value.category {
            case .storageFailure: category = .storageFailure
            case .serializationFailure: category = .serializationFailure
            case .incoherentCapture: category = .incoherentCapture
            case .timeout: category = .deadlineExceeded
            case .busy: category = .admissionBusy
            }
            failure = MCPResultFailure(category: category, diagnostic: nil)
        }
        let context = MCPResultContext(tool: tool, semanticFailure: failure,
            mutationRecovery: nil, entityPositions: [])
        let outcome = try MCPResultProviderAdapters.outcome(result: prepared.result, context: context,
            origin: .generatedJSON, checkpoint: checkpoint)
        let metadata = try MCPResultProviderAdapters.metadata(result: prepared.result,
            frozenReadBytes: prepared.frozenMetadataBytes, checkpoint: checkpoint)
        let declared = try declaringPositions(outcome, checkpoint: checkpoint)
        let presentation = try MCPResultAdapter.present(declared.source, context: declared.context,
            checkpoint: checkpoint)
        return try MCPResultEncoder.encode(source: outcome.source, presentation: presentation, id: id,
            metadata: metadata, checkpoint: checkpoint)
    }
    /// Explicit current public shapes only. Historical unknown fields are never traversed for IDs.
    private static func declaringPositions(
        _ outcome: MCPResultProviderOutcome, checkpoint: @Sendable () throws -> Void = {}
    ) throws -> MCPResultProviderOutcome {
        guard let value = outcome.source.document?.value else { return outcome }
        let positions: [MCPResultEntityPosition]
        switch outcome.context.tool {
        case "query_project_summaries": positions = try portfolioPositions(value, checkpoint: checkpoint)
        case "scan_duplicate_display_ids": positions = try scanPositions(value, checkpoint: checkpoint)
        case "reassign_duplicate_display_ids": positions = try reassignmentPositions(value, checkpoint: checkpoint)
        default: positions = []
        }
        let context = outcome.context
        return MCPResultProviderOutcome(source: outcome.source, context: MCPResultContext(tool: context.tool,
            semanticFailure: context.semanticFailure, mutationRecovery: context.mutationRecovery,
            entityPositions: context.entityPositions + positions))
    }

    private static func portfolioPositions(_ value: MCPJSONValue, checkpoint: @Sendable () throws -> Void) throws
        -> [MCPResultEntityPosition] {
        guard case .array(let projects) = try MCPResultInspection.member("projects", in: value,
            checkpoint: checkpoint) else { return [] }
        return try projects.indices.map { index in
            try checkpoint()
            return .init(entityType: .project, sourcePath: "/projects/\(index)")
        }
    }

    private static func scanPositions(_ value: MCPJSONValue, checkpoint: @Sendable () throws -> Void) throws
        -> [MCPResultEntityPosition] {
        guard case .array(let groups) = try MCPResultInspection.member("tasks", in: value,
            checkpoint: checkpoint) else { return [] }
        var positions: [MCPResultEntityPosition] = []
        for (index, group) in groups.enumerated() {
            try checkpoint()
            if case .array(let records) = try MCPResultInspection.member("records", in: group,
                checkpoint: checkpoint) {
                for record in records.indices {
                    try checkpoint()
                    positions.append(.init(entityType: .task,
                        sourcePath: "/tasks/\(index)/records/\(record)/id"))
                }
            }
        }
        return positions
    }

    private static func reassignmentPositions(_ value: MCPJSONValue, checkpoint: @Sendable () throws -> Void) throws
        -> [MCPResultEntityPosition] {
        guard case .array(let groups) = try MCPResultInspection.member("groups", in: value,
            checkpoint: checkpoint) else { return [] }
        var positions: [MCPResultEntityPosition] = []
        for (index, group) in groups.enumerated() {
            try checkpoint()
            guard MCPResultInspection.string(try MCPResultInspection.member("type", in: group,
                checkpoint: checkpoint)) == "task" else { continue }
            positions.append(.init(entityType: .task, sourcePath: "/groups/\(index)/winner/id"))
            if case .array(let records) = try MCPResultInspection.member("reassignments", in: group,
                checkpoint: checkpoint) {
                for record in records.indices {
                    try checkpoint()
                    positions.append(.init(entityType: .task,
                        sourcePath: "/groups/\(index)/reassignments/\(record)/id"))
                }
            }
        }
        return positions
    }
}
#endif
