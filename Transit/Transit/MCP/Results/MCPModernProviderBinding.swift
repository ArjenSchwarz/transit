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
    /// Fresh sibling pages share one original capture metadata owner, or fail whole.
    static func prepareReadPages(_ pages: [MCPPreparedToolRead], tool: String,
                                 operation: MCPReadOperation) throws -> [MCPResultPreparedPage] {
        let checkpoint = readCheckpoint(operation)
        try checkpoint()
        var prepared: [MCPResultPreparedPage] = []
        var metadataInitialized = false
        var originalMetadata: Data?
        var metadataOwner: MCPResultPreparedMetadata?
        var hasAttachedMetadata = false
        for page in pages {
            try checkpoint()
            if let attached = page.preparedResultPage {
                metadataOwner = attached.metadataOwner
                hasAttachedMetadata = true
                break
            }
        }
        for page in pages {
            try checkpoint()
            if let attached = page.preparedResultPage {
                prepared.append(attached)
                continue
            }
            if metadataInitialized {
                guard try sameMetadata(originalMetadata, page.frozenMetadataBytes, checkpoint: checkpoint) else {
                    throw MCPResultBoundaryError.unsupportedEvidence
                }
            } else {
                originalMetadata = page.frozenMetadataBytes
                let value = try MCPResultProviderAdapters.metadata(result: page.result,
                    frozenReadBytes: originalMetadata, checkpoint: checkpoint)
                if hasAttachedMetadata {
                    guard try sameMetadata(metadataOwner?.value.document.originalUTF8,
                        value?.document.originalUTF8, checkpoint: checkpoint) else {
                        throw MCPResultBoundaryError.unsupportedEvidence
                    }
                } else if let value {
                    try checkpoint()
                    metadataOwner = try MCPResultPreparation.metadata(value: value)
                    try checkpoint()
                }
                metadataInitialized = true
            }
            let outcome = try readOutcome(page, tool: tool, checkpoint: checkpoint)
            prepared.append(try MCPResultPreparation.page(source: outcome.source, context: outcome.context,
                metadataOwner: metadataOwner, checkpoint: checkpoint))
        }
        try checkpoint()
        return prepared
    }

    private static func sameMetadata(_ left: Data?, _ right: Data?,
                                     checkpoint: @Sendable () throws -> Void) throws -> Bool {
        try checkpoint()
        guard let left, let right else { return left == nil && right == nil }
        guard left.count == right.count else { return false }
        for (index, pair) in zip(left, right).enumerated() {
            if index % 1_024 == 0 { try checkpoint() }
            if pair.0 != pair.1 { return false }
        }
        try checkpoint()
        return true
    }

    static func availability(maintenanceEnabled: Bool, consolidationEnabled: Bool = false) -> MCPModernAvailability {
        let covered: Set<String> = ["query_tasks", "query_milestones", "get_projects", "query_project_summaries"]
        return MCPModernAvailability(tools: MCPToolDefinitions.tools(includingMaintenance: maintenanceEnabled,
            includingConsolidation: consolidationEnabled).map {
            let execution: MCPModernToolExecution
            if covered.contains($0.name) || MCPConsolidationToolDefinitions.previewTools.contains($0.name) {
                execution = .coveredRead
            } else if $0.name == "scan_duplicate_display_ids" {
                execution = .ordinaryRead
            } else if $0.name == "mutate_tasks" {
                execution = .applicationBatch
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
                let fallbackText = compactRecoveryText(request, tool: tool, encodedMessage: encodedMessage)
                let fallback = try MCPResultAdapter.source(
                    text: fallbackText,
                    isError: true, origin: .generatedJSON, evidence: .unestablished)
                let encoder = MCPConsolidationWriteDefinition.tools.contains(tool)
                    ? await handler.consolidationResultEncoder : nil
                return try await MCPResultProviderSelection.mutation(id: id, context: context,
                    metadata: nil, fallbackSource: fallback,
                    encodeOutcome: encoder ?? MCPResultProviderSelection.encode) {
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
        let checkpoint = readCheckpoint(operation)
        try checkpoint()
        if let attached = prepared.preparedResultPage {
            return try MCPResultEncoder.encode(fragment: attached.fragment, id: id, checkpoint: checkpoint)
        }
        let outcome = try readOutcome(prepared, tool: tool, checkpoint: checkpoint)
        let metadata = try MCPResultProviderAdapters.metadata(result: prepared.result,
            frozenReadBytes: prepared.frozenMetadataBytes, checkpoint: checkpoint)
        let presentation = try MCPResultAdapter.present(outcome.source, context: outcome.context,
            checkpoint: checkpoint)
        return try MCPResultEncoder.encode(source: outcome.source, presentation: presentation, id: id,
            metadata: metadata, checkpoint: checkpoint)
    }

    private static func readCheckpoint(_ operation: MCPReadOperation?) -> @Sendable () throws -> Void {
        {
            if let operation, !operation.shouldContinue() { throw CancellationError() }
            try Task.checkCancellation()
        }
    }

    private static func readOutcome(_ prepared: MCPPreparedToolRead, tool: String,
                                    checkpoint: @escaping @Sendable () throws -> Void) throws
        -> MCPResultProviderOutcome {
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
        return try declaringPositions(outcome, checkpoint: checkpoint)
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
