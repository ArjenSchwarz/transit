#if os(macOS)
import Foundation

/// A Sendable synchronous function value; no actor isolation or checkpoint is added.
typealias MCPReadPagePreparer = @Sendable ([MCPPreparedToolRead], String, MCPReadOperation)
    throws -> [MCPResultPreparedPage]

nonisolated struct MCPReadImportApplicability: Sendable {
    let inFlightImportIDs: Set<UUID>
    /// Independent evidence of saved-store visibility available before the decision.
    let visibleSavedImportProof: MCPImportCaptureProof?
}

/// Captures and prepares tool values. The outer coordinator alone publishes and chooses RPC bytes.
@MainActor
final class MCPReadService: MCPReadCapturedPreparing {
    let source: any MCPReadCaptureSource
    let monitor: MCPImportEvidenceMonitor
    let snapshots: MCPTaskQuerySnapshotStore
    let diagnostics: MCPReadDiagnosticSink
    let pagePreparer: MCPReadPagePreparer?
    private let applicability: () -> MCPReadImportApplicability
    private let proof: (CapturedReadView) -> MCPImportCaptureProof?

    init(source: any MCPReadCaptureSource, monitor: MCPImportEvidenceMonitor,
         snapshots: MCPTaskQuerySnapshotStore,
         applicability: @escaping () -> MCPReadImportApplicability = {
             MCPReadImportApplicability(inFlightImportIDs: [], visibleSavedImportProof: nil)
         },
         proof: @escaping (CapturedReadView) -> MCPImportCaptureProof? = { _ in nil },
         diagnostics: MCPReadDiagnosticSink = .disabled, pagePreparer: MCPReadPagePreparer? = nil) {
        self.source = source
        self.monitor = monitor
        self.snapshots = snapshots
        self.applicability = applicability
        self.proof = proof
        self.diagnostics = diagnostics
        self.pagePreparer = pagePreparer
    }

    /// Pure optional forwarding seam. Existing paged flow stays inactive until verified binding.
    func preparePrivatePages(_ pages: [MCPPreparedToolRead], tool: String,
                             operation: MCPReadOperation) throws -> [MCPResultPreparedPage]? {
        guard let pagePreparer else { return nil }
        guard operation.shouldContinue() else { throw CancellationError() }
        let prepared = try pagePreparer(pages, tool, operation)
        guard operation.shouldContinue() else { throw CancellationError() }
        guard prepared.count == pages.count else { throw MCPReadCaptureError.incoherentCapture }
        for (original, owner) in zip(pages, prepared) {
            guard operation.shouldContinue() else { throw CancellationError() }
            guard original.result.content.count == 1,
                  let text = original.result.content.first?.text,
                  try MCPReadSourceByteValidation.matches(text, owner.source.originalText, checkpoint: {
                      guard operation.shouldContinue() else { throw CancellationError() }
                  }),
                  original.result.isError == owner.source.originalIsError else {
                throw MCPReadCaptureError.incoherentCapture
            }
        }
        return prepared
    }

    func prepare(tool: String, arguments: [String: Any],
                 operation: MCPReadOperation) async throws -> MCPPreparedToolRead {
        operation.finishActorQueue()
        var policy = MCPReadPolicy.refreshIfNeeded
        do {
            guard operation.shouldContinue() else { throw ReadExecutionError.timeout }
            let query = tool == "query_tasks" ? try MCPTaskQueryRequest.parse(arguments) : nil
            if let raw = arguments["readPolicy"] {
                guard let parsed = MCPReadRefreshPolicy.parse(raw) else {
                    throw MCPTaskQueryError.invalid("readPolicy must be cached or refresh_if_needed")
                }
                policy = parsed
            }
            if let cursor = query?.cursor {
                return try prepareRetainedPage(cursor: cursor, requestedPolicy: query?.readPolicy)
            }
            let selection: ReadCaptureSelection
            switch tool {
            case "query_tasks": selection = .tasks(detail: query?.detailLevel == "full" ? .fullRecord : .summary)
            case "query_milestones":
                selection = arguments["displayId"] == nil ? .milestones : .tasks(detail: .summary)
            case "get_projects": selection = .projectCatalog
            default: throw MCPTaskQueryError.invalid("Unsupported covered read")
            }
            let request = captureRequest(tool: tool, arguments: arguments, selection: selection,
                                         includeComments: query?.includeComments ?? false, query: query)
            let fields = arguments.mapValues(AnyCodable.init)
            let transform: MCPReadCaptureTransform = { @MainActor [self] capsule, operation in
                try prepareProjection(capsule, tool: tool, arguments: fields.mapValues(\.value),
                                      query: query, operation: operation)
            }
            return try await prepareCapturedRead(request: request, policy: policy, operation: operation,
                                                transform: transform)
        } catch {
            return try prepareFailure(error, tool: tool, operation: operation, policy: policy)
        }
    }

    private func prepareProjection(
        _ capsule: MCPPreparedReadCapture, tool: String, arguments: [String: Any],
        query: MCPTaskQueryRequest?, operation: MCPReadOperation
    ) throws -> MCPPreparedToolRead {
        let captured = capsule.view
        let results: [[String: Any]]
        if let query {
            results = try MCPReadProjection.tasks(captured, request: query, arguments: arguments)
        } else {
            results = tool == "get_projects" ? try MCPReadProjection.projects(captured)
                : try MCPReadProjection.milestones(captured, arguments: arguments)
        }
        if let query {
            return try preparePages(results, query: query, view: captured, operation: operation,
                                    frozenMetadataBytes: capsule.frozenMetadataBytes)
        }
        let prepared = try MCPPreparedToolRead(text: jsonText(results),
                                               frozenMetadataBytes: capsule.frozenMetadataBytes)
        guard let owners = try preparePrivatePages([prepared], tool: tool, operation: operation) else {
            return prepared
        }
        guard owners.count == 1, let owner = owners.first else { throw MCPReadCaptureError.incoherentCapture }
        return prepared.attachingPreparedResultPage(owner)
    }

    func prepareCapturedRead(request: ReadCaptureRequest, policy: MCPReadPolicy,
                             operation: MCPReadOperation, transform: @escaping MCPReadCaptureTransform)
        async throws -> MCPPreparedToolRead {
        guard operation.shouldContinue() else { throw ReadExecutionError.timeout }
        let applicable = await MainActor.run { self.applicability() }
        let observation = try? monitor.beginObservation(applicableImportIDs: applicable.inFlightImportIDs)
        defer { observation?.close() }
        let view = try await capture(request: request, policy: policy, operation: operation,
                                     context: (observation, applicable.visibleSavedImportProof))
        guard operation.shouldContinue() else { throw ReadExecutionError.timeout }
        let transformStarted = ContinuousClock.now
        defer { operation.recordDiagnostic(.transform, startedAt: transformStarted) }
        let metadataBytes = try JSONEncoder().encode(view.metadata)
        return try await transform(MCPPreparedReadCapture(view: view, frozenMetadataBytes: metadataBytes), operation)
    }

    private func capture(request: ReadCaptureRequest,
                         policy: MCPReadPolicy, operation: MCPReadOperation,
                         context: (MCPImportObservationWindow?, MCPImportCaptureProof?))
        async throws -> CapturedReadView {
        let refreshStarted = ContinuousClock.now
        let (observation, decisionProof) = context
        // The active window starts before the decision snapshot and remains through metadata freezing.
        let applicable = observation?.applicableImportIDs ?? []
        let initial = monitor.snapshot(observation: observation)
        let recent = monitor.freshness(initial, proof: decisionProof, asOf: Date(), now: .now)
            .assessment == .recentImport
        let decision = observation == nil && initial.syncActive && policy != .cached
            ? MCPRefreshDecision.skip(.unavailable)
            : MCPReadRefreshPolicy.decision(policy: policy, snapshot: initial, recent: recent,
                remaining: operation.remainingBudget(), applicableInFlightIDs: applicable)
        let skipped: ReadRefreshOutcome?
        switch decision {
        case .skip(let outcome): skipped = outcome
        case .wait(let duration):
            guard let observation else { throw MCPReadCaptureError.incoherentCapture }
            _ = await MCPReadRefreshPolicy.wait(monitor: monitor, initial: initial,
                                                    duration: duration, observation: observation)
            skipped = nil
        }
        operation.recordDiagnostic(.refresh, startedAt: refreshStarted)
        guard operation.shouldContinue() else { throw ReadExecutionError.timeout }
        let captureStarted = ContinuousClock.now
        let view: CapturedReadView
        do { view = try source.capture(request) } catch {
            operation.recordDiagnostic(.capture, startedAt: captureStarted, outcome: .failure)
            throw error
        }
        operation.recordDiagnostic(.capture, startedAt: captureStarted)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: view.metadata.asOf) else { throw MCPReadCaptureError.incoherentCapture }
        let visibility = observation == nil ? nil : proof(view)
        let snapshot = monitor.snapshot(observation: observation)
        let freshness = monitor.freshness(snapshot, proof: visibility, asOf: date, now: view.createdAt)
        let outcome = skipped ?? MCPReadRefreshPolicy.outcome(initial: initial, final: snapshot, proof: visibility,
                                                              applicableInFlightIDs: applicable)
        let metadata = ReadCaptureMetadata(asOf: view.metadata.asOf, snapshotId: view.metadata.snapshotId,
            freshness: freshness, read: ReadExecutionMetadata(policy: policy, refreshOutcome: outcome, budgetMs: 5_000))
        return CapturedReadView(completeness: view.completeness, captureScope: view.captureScope, metadata: metadata,
            createdAt: view.createdAt, retentionDeadline: view.retentionDeadline, projects: view.projects,
            tasks: view.tasks, milestones: view.milestones, comments: view.comments)
    }

    func jsonText(_ value: Any) throws -> String {
        do {
            let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
            guard let text = String(data: data, encoding: .utf8) else { throw MCPReadCaptureError.serializationFailure }
            return text
        } catch { throw MCPReadCaptureError.serializationFailure }
    }

    /// Prepares the existing tool failure shape before outer transport serialization.
    func prepareFailure(_ error: Error, tool: String, operation: MCPReadOperation,
                        policy: MCPReadPolicy) throws -> MCPPreparedToolRead {
        let failureCode = tool == "query_tasks" ? "QUERY_FAILED" : "READ_FAILED"
        let category: ReadFailureCategory?
        let code: String
        let message: String
        switch error {
        case let query as MCPTaskQueryError:
            category = nil; code = query.code; message = query.message
        case MCPReadCaptureError.incoherentCapture:
            category = .incoherentCapture; code = failureCode; message = "Saved capture could not be proved coherent"
        case MCPReadCaptureError.serializationFailure:
            category = .serializationFailure; code = failureCode; message = "Read serialization failed"
        case MCPResultPreparationError.retentionCapacity:
            category = nil; code = "QUERY_CAPACITY_EXCEEDED"
            message = "Query capacity exceeded; reduce scope/comments or retry after expiry"
        case PublicationRejection.busy:
            category = .busy; code = "READ_BUSY"; message = "Read publication changed; retry the request"
        case ReadExecutionError.timeout:
            category = .timeout; code = "READ_TIMEOUT"; message = "Read exceeded its original admission budget"
        default:
            category = .storageFailure; code = failureCode; message = "Saved read storage failed"
        }
        let metadata = category.map { MCPReadResultMetadata.failure(ReadFailureMetadata(
            requestId: operation.id.uuidString, category: $0,
            read: ReadExecutionMetadata(policy: policy, refreshOutcome: .unavailable, budgetMs: 5_000))) }
        let text = tool == "query_tasks"
            ? IntentHelpers.encodeJSON(["error": ["code": code, "message": message]]) : message
        // This error envelope consists only of valid strings and fixed metadata values.
        let evidence = tool == "query_tasks" ? nil
            : MCPResultProviderEvidence(origin: .plainText, evidence: .established)
        return try MCPPreparedToolRead(text: text, isError: true, metadata: metadata, providerEvidence: evidence)
    }

    private enum ReadExecutionError: Error { case timeout }
}
#endif
