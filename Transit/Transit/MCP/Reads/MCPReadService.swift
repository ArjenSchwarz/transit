#if os(macOS)
import Foundation

nonisolated struct MCPReadImportApplicability: Sendable {
    let inFlightImportIDs: Set<UUID>
    /// Independent evidence of saved-store visibility available before the decision.
    let visibleSavedImportProof: MCPImportCaptureProof?
}

/// Captures and prepares tool values. The outer coordinator alone publishes and chooses RPC bytes.
@MainActor
final class MCPReadService {
    let source: any MCPReadCaptureSource
    let monitor: MCPImportEvidenceMonitor
    let snapshots: MCPTaskQuerySnapshotStore
    private let applicability: () -> MCPReadImportApplicability
    private let proof: (CapturedReadView) -> MCPImportCaptureProof?

    init(source: any MCPReadCaptureSource, monitor: MCPImportEvidenceMonitor,
         snapshots: MCPTaskQuerySnapshotStore,
         applicability: @escaping () -> MCPReadImportApplicability = {
             MCPReadImportApplicability(inFlightImportIDs: [], visibleSavedImportProof: nil)
         },
         proof: @escaping (CapturedReadView) -> MCPImportCaptureProof? = { _ in nil }) {
        self.source = source
        self.monitor = monitor
        self.snapshots = snapshots
        self.applicability = applicability
        self.proof = proof
    }

    // swiftlint:disable:next cyclomatic_complexity
    func prepare(tool: String, arguments: [String: Any],
                 operation: MCPReadOperation) async throws -> MCPPreparedToolRead {
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
                let page = try snapshots.retainedPage(for: cursor)
                if let requested = query?.readPolicy, let retained = page.policy, requested != retained {
                    throw MCPTaskQueryError(code: "INVALID_INPUT",
                                            message: "readPolicy conflicts with retained query")
                }
                return try MCPPreparedToolRead(text: page.text, frozenMetadataBytes: page.metadataBytes)
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
            let applicable = applicability()
            let observation = try? monitor.beginObservation(applicableImportIDs: applicable.inFlightImportIDs)
            defer { observation?.close() }
            let captured = try await capture(request: request,
                                             policy: policy, operation: operation,
                                             context: (observation, applicable.visibleSavedImportProof))
            guard operation.shouldContinue() else { throw ReadExecutionError.timeout }
            let results: [[String: Any]]
            if let query {
                results = try MCPReadProjection.tasks(captured, request: query, arguments: arguments)
            } else {
                results = tool == "get_projects" ? try MCPReadProjection.projects(captured)
                    : try MCPReadProjection.milestones(captured, arguments: arguments)
            }
            if let query {
                return try preparePages(results, query: query, view: captured, operation: operation)
            }
            return try MCPPreparedToolRead(text: jsonText(results), metadata: .capture(captured.metadata))
        } catch {
            return try failure(error, tool: tool, operation: operation, policy: policy)
        }
    }

    private func captureRequest(tool: String, arguments: [String: Any], selection: ReadCaptureSelection,
                                includeComments: Bool, query: MCPTaskQueryRequest?) -> ReadCaptureRequest {
        let fields = arguments.mapValues(AnyCodable.init)
        let state = ValidationState()
        return ReadCaptureRequest(projectSelectors: nil, selection: selection,
                completeness: .selectedRead, includeComments: includeComments,
                validateProjects: { projects in
                    let args = fields.mapValues(\.value)
                    guard tool != "get_projects" else { return }
                    state.project = try MCPReadProjection.projectIdentity(args, projects: projects,
                                                             validateIgnoredName: tool == "query_tasks")
                    if tool == "query_tasks" {
                        try MCPReadProjection.validateTaskScalars(args)
                    } else {
                        try MCPReadProjection.enumeration(args, key: "status", type: MilestoneStatus.self)
                        try MCPReadProjection.string(args, key: "search")
                        try MCPReadProjection.integer(args, key: "displayId")
                    }
                }, validateMilestones: { milestones in
                    let args = fields.mapValues(\.value)
                    state.milestones = milestones
                    if tool == "query_tasks" {
                        if case .noMatch = try MCPReadProjection.milestoneFilter(args, project: state.project,
                                                                               milestones: milestones) { return false }
                        return true
                    }
                    guard tool == "query_milestones", let id = IntentHelpers.parseIntValue(args["displayId"]) else {
                        return tool == "get_projects"
                    }
                    let matches = milestones.filter { $0.permanentDisplayId == id }
                    guard matches.count <= 1 else {
                        throw MCPTaskQueryError(code: "AMBIGUOUS_FILTER",
                            message: "Duplicate milestone identifier detected for displayId \(id)")
                    }
                    guard let match = matches.first else { return false }
                    return MCPReadProjection.matchesMilestone(match, arguments: args, projectID: state.project?.id)
                }, selectTaskBodies: { values in
                    guard let query else { return Set(values.map(\.physicalKey)) }
                    let filters = try MCPReadProjection.taskFilters(fields.mapValues(\.value),
                        project: state.project, milestones: state.milestones)
                    return try MCPReadProjection.taskBodyKeys(values, request: query, filters: filters)
                }, selectMilestoneBodies: { values in
                    guard tool == "query_milestones" else { return [] }
                    return try MCPReadProjection.milestoneBodyKeys(values, arguments: fields.mapValues(\.value),
                        projectID: state.project?.id)
                })
    }

    private final class ValidationState {
        var project: ReadProjectIdentity?
        var milestones: [ReadMilestoneIdentity] = []
    }

    private func capture(request: ReadCaptureRequest,
                         policy: MCPReadPolicy, operation: MCPReadOperation,
                         context: (MCPImportObservationWindow?, MCPImportCaptureProof?))
        async throws -> CapturedReadView {
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
        guard operation.shouldContinue() else { throw ReadExecutionError.timeout }
        let view = try source.capture(request)
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

    private func preparePages(_ results: [[String: Any]], query: MCPTaskQueryRequest,
                              view: CapturedReadView, operation: MCPReadOperation) throws -> MCPPreparedToolRead {
        let count = max(1, (results.count + query.limit - 1) / query.limit)
        let cursors = (0..<(count - 1)).map { _ in snapshots.makeCursor() }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let asOf = formatter.date(from: view.metadata.asOf) else {
            throw MCPReadCaptureError.incoherentCapture
        }
        let expiry = ISO8601DateFormatter().string(from: asOf.addingTimeInterval(300))
        let pages = try (0..<count).map { position in
            let start = position * query.limit
            let end = min(start + query.limit, results.count)
            let next: Any = position < cursors.count ? cursors[position] : NSNull()
            return try jsonText(["results": Array(results[start..<end]), "nextCursor": next, "expiresAt": expiry])
        }
        let first = try MCPPreparedToolRead(text: pages[0], metadata: .capture(view.metadata))
        let reservation = try snapshots.prepare(pages: pages, cursors: cursors, deadline: view.retentionDeadline,
            operationID: operation.id, metadataBytes: first.frozenMetadataBytes, policy: view.metadata.read.policy)
        return first.attaching(reservation.map { [$0] } ?? [])
    }

    private func jsonText(_ value: Any) throws -> String {
        do {
            let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
            guard let text = String(data: data, encoding: .utf8) else { throw MCPReadCaptureError.serializationFailure }
            return text
        } catch { throw MCPReadCaptureError.serializationFailure }
    }

    private func failure(_ error: Error, tool: String, operation: MCPReadOperation,
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
        return try MCPPreparedToolRead(text: text, isError: true, metadata: metadata)
    }

    private enum ReadExecutionError: Error { case timeout }
}
#endif
