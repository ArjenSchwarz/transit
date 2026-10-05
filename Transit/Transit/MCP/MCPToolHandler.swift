#if os(macOS)
import Foundation
import NIOCore
import SwiftData

// swiftlint:disable file_length

@MainActor
protocol MilestoneDisplayIDFinding {
    func findByDisplayID(_ displayId: Int) throws -> Milestone
}

extension MilestoneService: MilestoneDisplayIDFinding {}

@MainActor
// swiftlint:disable:next type_body_length
final class MCPToolHandler {

    let taskService: TaskService
    let taskFetcher: any TaskFetching
    let projectService: ProjectService
    let commentFetcher: any CommentFetching
    let milestoneService: MilestoneService
    let milestoneFetcher: any MilestoneFetching
    let milestoneDisplayIDFinder: any MilestoneDisplayIDFinding
    private let maintenanceService: DisplayIDMaintenanceService
    private nonisolated let settings: MCPSettings
    private let persistence: PersistenceAvailability
    private let writeCoordinator: MCPWriteCoordinator?

    // Batch provider injection only; Task14 binds dispatch after real-route RED.
    let batchContainer: ModelContainer?
    let batchResultEncoder: MCPResultProviderSelection.EncodeOutcome?

    /// Task14 fault seam declaration; task15 binds only the post-effect provider encoding stage.
    let maintenanceReassignmentEncoder: (@Sendable (ReassignmentResult) throws -> String)?

    let readService: MCPReadService?
    let taskQuerySnapshots: MCPTaskQuerySnapshotStore
    nonisolated let reusableSnapshots: Result<MCPReusableSnapshotStore, Error>
    private(set) var reusableSnapshotLifecycleFailure: Error?
    private(set) var taskQueryAdmissionOpen = true

    func setTaskQueryAdmission(open: Bool) {
        taskQueryAdmissionOpen = open
        clearTaskQuerySnapshots()
    }

    func clearTaskQuerySnapshots() {
        taskQuerySnapshots.clear()
        do { try reusableSnapshots.get().invalidate() } catch { reusableSnapshotLifecycleFailure = error }
    }

    /// Tools that only read.
    private static let readOnlyToolNames: Set<String> = [
        "query_tasks", "query_milestones", "get_projects", "query_project_summaries", "scan_duplicate_display_ids"
    ]

    /// Tools blocked while fallback storage is active. Derived by subtracting the read-only
    /// allow-list from the full tool list, so a newly added tool is treated as mutating
    /// (fails safe) without a second edit here [T-1818].
    private static let mutatingToolNames: Set<String> = Set(
        MCPToolDefinitions.tools(includingMaintenance: true).map(\.name)
    ).subtracting(readOnlyToolNames)

    nonisolated let readCoordinator: MCPReadCoordinator

    init(
        taskService: TaskService,
        projectService: ProjectService,
        commentService: CommentService,
        milestoneService: MilestoneService,
        maintenanceService: DisplayIDMaintenanceService,
        settings: MCPSettings,
        persistence: PersistenceAvailability? = nil,
        taskFetcher: (any TaskFetching)? = nil,
        commentFetcher: (any CommentFetching)? = nil,
        milestoneFetcher: (any MilestoneFetching)? = nil,
        milestoneDisplayIDFinder: (any MilestoneDisplayIDFinding)? = nil,
        taskQuerySnapshots: MCPTaskQuerySnapshotStore? = nil,
        writeCoordinator: MCPWriteCoordinator? = nil,
        readService: MCPReadService? = nil,
        readCoordinator: MCPReadCoordinator? = nil,
        reusableSnapshots: MCPReusableSnapshotStore? = nil,
        maintenanceReassignmentEncoder: (@Sendable (ReassignmentResult) throws -> String)? = nil,
        batchContainer: ModelContainer? = nil,
        batchResultEncoder: MCPResultProviderSelection.EncodeOutcome? = nil
    ) {
        self.taskService = taskService
        self.taskFetcher = taskFetcher ?? taskService
        self.projectService = projectService
        self.commentFetcher = commentFetcher ?? commentService
        self.milestoneService = milestoneService
        self.milestoneFetcher = milestoneFetcher ?? milestoneService
        self.milestoneDisplayIDFinder = milestoneDisplayIDFinder ?? milestoneService
        self.maintenanceService = maintenanceService
        self.settings = settings
        self.persistence = persistence ?? .shared
        self.taskQuerySnapshots = taskQuerySnapshots ?? readService?.snapshots ?? MCPTaskQuerySnapshotStore()
        let domain = self.taskQuerySnapshots.domain
        let coordinator = readCoordinator ?? MCPReadCoordinator(
            domain: domain, diagnostics: readService?.diagnostics ?? .disabled)
        self.readCoordinator = coordinator
        self.reusableSnapshots = Result {
            guard coordinator.domain === domain,
                  readService == nil || readService?.snapshots.domain === domain else {
                throw PublicationRejection.busy
            }
            if let reusableSnapshots {
                guard reusableSnapshots.domain === domain else {
                    throw PublicationRejection.busy
                }
                return reusableSnapshots
            }
            return try MCPReusableSnapshotStore(domain: domain)
        }
        self.writeCoordinator = writeCoordinator
        self.batchContainer = batchContainer
        self.batchResultEncoder = batchResultEncoder
        self.maintenanceReassignmentEncoder = maintenanceReassignmentEncoder
        self.readService = readService
    }

    /// One immutable request snapshot; no MainActor hop or defaults access at admission.
    nonisolated var modernMaintenanceEnabled: Bool { settings.maintenanceToolsEnabledSnapshot }

    /// Delegates pure input validation to the existing write validator. Acceptance, receipts,
    /// persistence and effects remain exclusively owned by the write coordinator.
    func modernPreflight(_ request: JSONRPCRequest, tool: String) -> MCPModernProviderPreflight {
        guard let params = request.params?.value as? [String: Any] else {
            return .requestError(JSONRPCError(code: JSONRPCErrorCode.invalidParams,
                message: "Missing tool name", data: nil))
        }
        let arguments: [String: Any]
        switch parseArgumentsEnvelope(params) {
        case .success(let value): arguments = value
        case .failure(.message(let message)):
            return .requestError(JSONRPCError(code: JSONRPCErrorCode.invalidParams, message: message, data: nil))
        }
        var recovery: MCPMutationRecoveryContext?
        if MCPWriteCommand.protectedTools.contains(tool) {
            do {
                let command = try MCPWriteCommand.validate(tool: tool, arguments: arguments)
                recovery = .protectedWrite(MCPProtectedRecoveryKey(tool: tool, idempotencyKey: command.key))
            } catch {
                let result = MCPWriteOutcome.result(MCPWriteOutcome.failure(tool: tool,
                    key: arguments["idempotencyKey"] as? String, failure: MCPWriteFailure.from(error),
                    accepted: false), isError: true)
                return .rejected(result)
            }
        } else if tool == "reassign_duplicate_display_ids" {
            recovery = .unprotectedMaintenance(tool: tool)
        }
        return .ready(MCPResultContext(tool: tool, semanticFailure: nil,
            mutationRecovery: recovery, entityPositions: []))
    }

    // MARK: - JSON-RPC Dispatch

    func subscribeToToolListChanges(
        id: JSONRPCId, toolsListChanged: Bool, channelClose: EventLoopFuture<Void>
    ) throws -> MCPToolListSubscription {
        try settings.subscriptionBroadcaster.subscribe(id: id, toolsListChanged: toolsListChanged,
            channelClose: channelClose)
    }

    func openToolListSubscriptions() { settings.subscriptionBroadcaster.openRequests() }

    func disconnectToolListSubscription(_ registrationID: UUID) {
        settings.subscriptionBroadcaster.disconnect(registrationID)
    }

    func finishToolListChangeSessions() {
        settings.finishToolListChangeSessions()
    }

    var activeToolListChangeStreamCount: Int {
        settings.activeToolListChangeStreamCount
    }

    /// Returns `nil` for JSON-RPC notifications (no response required).
    func handle(_ request: JSONRPCRequest, maintenanceEnabled: Bool? = nil) async -> JSONRPCResponse? {
        // MCP 2025-03-26 requires a present request id to be a string or
        // integer. `JSONRPCRequest` preserves presence separately because an
        // omitted id is a notification while an explicit null is invalid.
        guard !request.isNotification, request.id != nil else {
            return JSONRPCResponse.error(
                id: nil,
                code: JSONRPCErrorCode.invalidRequest,
                message: "Invalid Request: id must be a string or integer"
            )
        }

        // JSON-RPC 2.0 §4.2/§5: reject non-"2.0" with -32600, even on notification-shaped envelopes (T-1106).
        guard request.jsonrpc == "2.0" else {
            return JSONRPCResponse.error(
                id: request.id,
                code: JSONRPCErrorCode.invalidRequest,
                message: "Invalid Request: jsonrpc must be \"2.0\""
            )
        }

        let response: JSONRPCResponse
        switch request.method {
        case "initialize":
            response = handleInitialize(id: request.id, params: request.params)
        case "ping":
            response = JSONRPCResponse.success(id: request.id, result: EmptyResult())
        case "tools/list":
            response = handleToolsList(id: request.id)
        case "tools/call":
            response = await handleToolCall(id: request.id, params: request.params,
                maintenanceEnabled: maintenanceEnabled ?? settings.maintenanceToolsEnabledSnapshot)
        default:
            response = JSONRPCResponse.error(
                id: request.id,
                code: JSONRPCErrorCode.methodNotFound,
                message: "Unknown method: \(request.method)"
            )
        }

        // Notifications are method calls whose results are intentionally
        // discarded, not calls that should be skipped. This matters for
        // state-changing tools/call notifications inside a JSON-RPC batch.
        return request.isNotification ? nil : response
    }

    // MARK: - Initialize

    private static let latestSupportedProtocolVersion = "2025-03-26"
    private static let supportedProtocolVersions: Set<String> = [latestSupportedProtocolVersion]

    private struct InvalidInitializeParams: Error {
        let message: String
    }

    private func handleInitialize(id: JSONRPCId?, params: AnyCodable?) -> JSONRPCResponse {
        guard let params else {
            return invalidInitializeParams(id: id, message: "Missing initialize params")
        }
        guard let dict = params.value as? [String: Any] else {
            return invalidInitializeParams(id: id, message: "Initialize params must be an object")
        }

        let requestedProtocolVersion: String
        do {
            requestedProtocolVersion = try initializeProtocolVersion(in: dict)
            try validateInitializeCapabilities(in: dict)
            try validateInitializeClientInfo(in: dict)
        } catch {
            return invalidInitializeParams(id: id, message: error.message)
        }

        let protocolVersion =
            Self.supportedProtocolVersions.contains(requestedProtocolVersion)
            ? requestedProtocolVersion
            : Self.latestSupportedProtocolVersion
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let result = MCPInitializeResult(
            protocolVersion: protocolVersion,
            capabilities: MCPServerCapabilities(tools: MCPToolsCapability(listChanged: true)),
            serverInfo: MCPServerInfo(name: "transit", version: version)
        )
        return JSONRPCResponse.success(id: id, result: result)
    }

    private func initializeProtocolVersion(
        in params: [String: Any]
    ) throws(InvalidInitializeParams) -> String {
        guard params["protocolVersion"] != nil else {
            throw InvalidInitializeParams(message: "Missing protocolVersion")
        }
        guard let protocolVersion = params["protocolVersion"] as? String else {
            throw InvalidInitializeParams(message: "protocolVersion must be a string")
        }
        return protocolVersion
    }

    private func validateInitializeCapabilities(
        in params: [String: Any]
    ) throws(InvalidInitializeParams) {
        guard params["capabilities"] != nil else {
            throw InvalidInitializeParams(message: "Missing capabilities")
        }
        guard params["capabilities"] is [String: Any] else {
            throw InvalidInitializeParams(message: "capabilities must be an object")
        }
    }

    private func validateInitializeClientInfo(
        in params: [String: Any]
    ) throws(InvalidInitializeParams) {
        guard params["clientInfo"] != nil else {
            throw InvalidInitializeParams(message: "Missing clientInfo")
        }
        guard let clientInfo = params["clientInfo"] as? [String: Any] else {
            throw InvalidInitializeParams(message: "clientInfo must be an object")
        }
        guard clientInfo["name"] != nil else {
            throw InvalidInitializeParams(message: "Missing clientInfo.name")
        }
        guard clientInfo["name"] is String else {
            throw InvalidInitializeParams(message: "clientInfo.name must be a string")
        }
        guard clientInfo["version"] != nil else {
            throw InvalidInitializeParams(message: "Missing clientInfo.version")
        }
        guard clientInfo["version"] is String else {
            throw InvalidInitializeParams(message: "clientInfo.version must be a string")
        }
        if clientInfo["title"] != nil, !(clientInfo["title"] is String) {
            throw InvalidInitializeParams(message: "clientInfo.title must be a string")
        }
    }

    private func invalidInitializeParams(id: JSONRPCId?, message: String) -> JSONRPCResponse {
        JSONRPCResponse.error(id: id, code: JSONRPCErrorCode.invalidParams, message: message)
    }

    // MARK: - Tools List

    private func handleToolsList(id: JSONRPCId?) -> JSONRPCResponse {
        let tools = MCPToolsListResult(
            tools: MCPToolDefinitions.tools(includingMaintenance: settings.maintenanceToolsEnabled)
        )
        return JSONRPCResponse.success(id: id, result: tools)
    }

    // MARK: - Tools Call

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private func handleToolCall(
        id: JSONRPCId?,
        params: AnyCodable?,
        maintenanceEnabled: Bool
    ) async -> JSONRPCResponse {
        guard let dict = params?.value as? [String: Any],
            let name = dict["name"] as? String
        else {
            return JSONRPCResponse.error(
                id: id,
                code: JSONRPCErrorCode.invalidParams,
                message: "Missing tool name"
            )
        }

        let arguments: [String: Any]
        switch parseArgumentsEnvelope(dict) {
        case .success(let parsed):
            arguments = parsed
        case .failure(.message(let message)):
            return JSONRPCResponse.error(id: id, code: JSONRPCErrorCode.invalidParams, message: message)
        }

        // Gate maintenance tools behind the settings toggle. Distinct message so
        // callers can tell a disabled tool from an unknown one (AC 5.5). The
        // outer tools/call method is supported; only its tool-name parameter is
        // invalid under the negotiated MCP protocol contract.
        if MCPToolDefinitions.maintenanceToolNames.contains(name), !maintenanceEnabled {
            return JSONRPCResponse.error(
                id: id,
                code: JSONRPCErrorCode.invalidParams,
                message: "Tool '\(name)' is disabled. Enable maintenance tools in Transit Settings."
            )
        }

        if MCPWriteCommand.protectedTools.contains(name) {
            let result = await protectedWriteResult(tool: name, arguments: arguments)
            return JSONRPCResponse.success(id: id, result: result)
        }

        // Reject mutations while Transit is running on the in-memory fallback container. The
        // write would look successful and then vanish on restart, and an MCP client never sees
        // the app's degraded-storage alert, so success is indistinguishable from durable
        // persistence [T-1818]. Reads stay available: they cannot lose data, and every follow-up
        // action that could act on a stale read is blocked by this same gate.
        if Self.mutatingToolNames.contains(name), persistence.isFallbackStorageActive {
            return JSONRPCResponse.success(
                id: id, result: errorResult(PersistenceAvailability.unavailableHint, category: .storageFailure)
            )
        }

        let result: MCPToolResult
        switch name {
        case "query_tasks":
            result = handleQueryTasks(arguments)
        case "get_projects":
            result = handleGetProjects()
        case "query_milestones":
            result = handleQueryMilestones(arguments)
        case "scan_duplicate_display_ids":
            result = handleScanDuplicateDisplayIds()
        case "reassign_duplicate_display_ids":
            result = await handleReassignDuplicateDisplayIds()
        default:
            return JSONRPCResponse.error(
                id: id,
                code: JSONRPCErrorCode.invalidParams,
                message: "Unknown tool: \(name)"
            )
        }

        return JSONRPCResponse.success(id: id, result: result)
    }

    // MARK: - Maintenance Dispatch

    private func handleScanDuplicateDisplayIds() -> MCPToolResult {
        do {
            let report = try maintenanceService.scanDuplicates()
            do { return textResult(try IntentHelpers.encodeAsJSONString(report)) } catch {
                return errorResult("Failed to encode duplicate report: \(error.localizedDescription)",
                category: .serializationFailure) }
        } catch {
            return errorResult("Failed to scan duplicates: \(error.localizedDescription)", category: .storageFailure)
        }
    }

    private func handleReassignDuplicateDisplayIds() async -> MCPToolResult {
        let result = await maintenanceService.reassignDuplicates()
        do {
            let text = try maintenanceReassignmentEncoder?(result) ?? IntentHelpers.encodeAsJSONString(result)
            return textResult(text)
        } catch {
            let message = "Failed to encode reassignment result: \(error.localizedDescription)"
            return MCPToolResult(content: [.text(message)],
                isError: true, providerEvidence: MCPResultProviderEvidence(origin: .plainText,
                    evidence: .unestablished, failure: MCPResultFailure(category: .outcomeUncertain, diagnostic: nil),
                    requiresPreparedReconciliation: true))
        }
    }

    // MARK: - create_task

}

// MARK: - query_milestones

extension MCPToolHandler {

    private func handleQueryMilestones(_ args: [String: Any]) -> MCPToolResult {
        // Validate filter inputs first so a displayId lookup can't bypass validation [T-963].
        // Resolve the project filter once and reuse it for both the displayId match and the
        // full-table filter pass.
        let projectFilter: UUID?
        switch resolveProjectFilter(args) {
        case .resolved(let pid): projectFilter = pid
        case .none: projectFilter = nil
        case .error(let message, let category): return errorResult(message, category: category)
        }

        // Status filter — validate enum values before filtering [T-732]
        if let error = validateEnumFilter(args, key: "status", type: MilestoneStatus.self) { return error }

        // Reject non-string `search` filter [T-1156]. Validated before the displayId branch so a
        // malformed value can't bypass validation by silently dropping through `as? String`.
        if args["search"] != nil, !(args["search"] is String) {
            return errorResult("search must be a string")
        }

        // Single-milestone lookup by displayId. Remaining filters still apply conjunctively —
        // a milestone that does not satisfy them is filtered out, mirroring handleQueryTasks [T-963].
        if args["displayId"] != nil {
            guard let displayId = IntentHelpers.parseIntValue(args["displayId"]) else {
                return errorResult("displayId must be an integer")
            }
            return lookupMilestoneByDisplayId(displayId, args: args, projectFilter: projectFilter)
        }

        // Full query with filters
        let allMilestones: [Milestone]
        do {
            allMilestones = try milestoneService.fetchAllMilestones()
        } catch {
            return errorResult("Failed to fetch milestones: \(error)", category: .storageFailure)
        }

        let filtered = allMilestones.filter { milestoneMatches($0, args: args, projectFilter: projectFilter) }
        let formatter = ISO8601DateFormatter()
        do {
            let results = try filtered.map { try milestoneToDict($0, formatter: formatter) }
            return textResult(IntentHelpers.encodeJSONArray(results))
        } catch { return errorResult("Failed to capture milestones: \(error)", category: .storageFailure) }
    }

    /// Returns true when `milestone` satisfies the project/status/search filters in `args`.
    /// Callers must pre-validate filter inputs.
    private func milestoneMatches(
        _ milestone: Milestone, args: [String: Any], projectFilter: UUID?
    ) -> Bool {
        if let projectFilter, milestone.project?.id != projectFilter {
            return false
        }
        if let statusArray = args["status"] as? [String] {
            if !statusArray.contains(milestone.statusRawValue) { return false }
        } else if let statusSingle = args["status"] as? String {
            if milestone.statusRawValue != statusSingle { return false }
        }
        if let search = args["search"] as? String,
            !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let nameMatch = milestone.name.localizedCaseInsensitiveContains(search)
            let descMatch = milestone.milestoneDescription?.localizedCaseInsensitiveContains(search) ?? false
            if !nameMatch && !descMatch { return false }
        }
        return true
    }

    private func lookupMilestoneByDisplayId(
        _ displayId: Int, args: [String: Any], projectFilter: UUID?
    ) -> MCPToolResult {
        do {
            let milestone = try milestoneService.findByDisplayID(displayId)
            guard milestoneMatches(milestone, args: args, projectFilter: projectFilter) else {
                return textResult(IntentHelpers.encodeJSONArray([]))
            }
            let formatter = ISO8601DateFormatter()
            let dict = try milestoneToDict(milestone, formatter: formatter, detailed: true)
            return textResult(IntentHelpers.encodeJSONArray([dict]))
        } catch MilestoneService.Error.milestoneNotFound {
            return textResult(IntentHelpers.encodeJSONArray([]))
        } catch MilestoneService.Error.duplicateDisplayID {
            return errorResult("Duplicate milestone identifier detected for displayId \(displayId)",
                category: .ambiguousIdentity)
        } catch {
            return errorResult("Failed to look up milestone: \(error)", category: .storageFailure)
        }
    }

    private enum ProjectFilterResult {
        case resolved(UUID)
        case none
        case error(String, MCPResultErrorCategory)
    }

    private func resolveProjectFilter(_ args: [String: Any]) -> ProjectFilterResult {
        // Reject malformed or non-string projectId when the key is present
        // [T-665, T-788].
        switch parseProjectIdArgument(args) {
        case .failure(.message(let message)): return .error(message, .invalidInput)
        case .success(let pid?):
            switch projectService.findProject(id: pid) {
            case .success(let project):
                return .resolved(project.id)
            case .failure(let error):
                let mapped = IntentHelpers.mapProjectLookupError(error)
                return .error(mapped.hint, MCPResultClassification.category(for: mapped.code) ?? .internalFailure)
            }
        case .success(nil):
            // Reject non-string `project` filter [T-1116].
            if args["project"] != nil, !(args["project"] is String) {
                return .error("project must be a string", .invalidInput)
            }
            if let name = args["project"] as? String,
                !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                switch projectService.findProject(id: nil, name: name) {
                case .success(let found):
                    return .resolved(found.id)
                case .failure(let err):
                    let mapped = IntentHelpers.mapProjectLookupError(err)
                    return .error(mapped.hint, MCPResultClassification.category(for: mapped.code) ?? .internalFailure)
                }
            }
            return .none
        }
    }
}

// MARK: - get_projects, add_comment & Helpers

extension MCPToolHandler {

    private func projectMetadataDict(_ project: Project) throws -> [String: Any] {
        var dict = try MCPRecordSnapshot.project(project).record
        dict["activeTaskCount"] = projectService.activeTaskCount(for: project)
        return dict
    }

    private func handleGetProjects() -> MCPToolResult {
        let projects: [Project]
        do {
            projects = try projectService.fetchAllProjects(sortedByName: true)
        } catch {
            return errorResult("Failed to fetch projects: \(error)", category: .storageFailure)
        }
        var results: [[String: Any]] = []
        for project in projects {
            var dict: [String: Any]
            do { dict = try projectMetadataDict(project) } catch {
                return errorResult("Failed to capture project: \(error)", category: .storageFailure)
            }

            let milestones: [Milestone]
            do {
                milestones = try milestoneService.milestonesForProject(project)
            } catch {
                return errorResult("Failed to fetch milestones: \(error)", category: .storageFailure)
            }
            if !milestones.isEmpty {
                dict["milestones"] = milestones.map { milestoneSummaryDict($0) }
            }
            results.append(dict)
        }
        return textResult(IntentHelpers.encodeJSONArray(results))
    }

    // MARK: - Helpers

    enum ResolveError: Error {
        case message(String)
    }

    /// Message for a display ID matched by more than one task. [T-1837]
    func duplicateTaskIdentifierMessage(displayId: Int?) -> String {
        guard let displayId else { return "Duplicate task identifier detected" }
        return "Duplicate task identifier detected for displayId \(displayId)"
    }

    func textResult(_ text: String) -> MCPToolResult {
        MCPToolResult(content: [.text(text)], isError: nil,
            providerEvidence: MCPResultProviderEvidence(origin: .generatedJSON))
    }
    func errorResult(_ message: String, category: MCPResultErrorCategory = .invalidInput,
                     origin: MCPResultOrigin = .plainText) -> MCPToolResult {
        MCPToolResult(content: [.text(message)], isError: true,
            providerEvidence: MCPResultProviderEvidence(origin: origin,
                failure: MCPResultFailure(category: category, diagnostic: nil)))
    }

    /// Validates the `arguments` envelope of a `tools/call` request. Omitting the
    /// key is allowed and yields `[:]` for tools whose inputs are all optional.
    /// A present-but-non-object value (string, array, number, boolean, null)
    /// must be rejected with `invalidParams` rather than silently coerced to
    /// `[:]` — otherwise read tools like `query_tasks` would execute with no
    /// filters and expose all data, while mutation tools would degrade to
    /// misleading "missing required field" errors [T-1247].
    private func parseArgumentsEnvelope(_ params: [String: Any]) -> Result<[String: Any], ResolveError> {
        guard params["arguments"] != nil else { return .success([:]) }
        guard let dict = params["arguments"] as? [String: Any] else {
            return .failure(.message("Invalid arguments: must be a JSON object"))
        }
        return .success(dict)
    }

    /// Validates a UUID-shaped argument by key. Returns `.success(nil)` when the
    /// key is absent, `.success(uuid)` when the value is a valid UUID string,
    /// or `.failure(.message(...))` when the key is present but the value is not
    /// a valid UUID string (covers non-string types too) [T-743, T-788].
    func parseProjectIdArgument(_ args: [String: Any]) -> Result<UUID?, ResolveError> {
        guard args["projectId"] != nil else { return .success(nil) }
        guard let pidStr = args["projectId"] as? String, let pid = UUID(uuidString: pidStr) else {
            return .failure(.message("Invalid projectId: expected a UUID string"))
        }
        return .success(pid)
    }

    /// Validate that all values for a given key are valid raw values of the specified enum.
    /// Returns an error result if any value is invalid, or nil if all are valid (or the key is absent).
    ///
    /// When `allowArray` is true (the default), both array and single-string inputs are accepted —
    /// used for multi-value filters like `status`/`not_status`. When false, only a single string is
    /// accepted and an array is rejected — used for single-value filters like `type`, whose schema
    /// declares a single string enum and whose caller reads it back with `args["type"] as? String`.
    /// Accepting an array there would pass validation and then be silently dropped to `nil`,
    /// returning unfiltered results. [T-1404]
    ///
    /// If the key is present but the value is neither a String nor a [String] (e.g. a number,
    /// boolean, dictionary, or array containing non-string elements), this returns a
    /// field-specific error so malformed shapes cannot be silently treated as absent. [T-809, T-830]
    func validateEnumFilter<E: RawRepresentable & CaseIterable>(
        _ args: [String: Any], key: String, type: E.Type, allowArray: Bool = true
    ) -> MCPToolResult? where E.RawValue == String {
        guard let raw = args[key] else { return nil }

        let expectation = allowArray ? "a string or array of strings" : "a string"

        let values: [String]
        if let single = raw as? String {
            values = [single]
        } else if allowArray, let array = raw as? [String] {
            values = array
        } else if allowArray, let anyArray = raw as? [Any] {
            // Reject arrays that contain non-string elements (e.g. ["idea", 123]).
            // `raw as? [String]` returns nil for mixed-type arrays, so we must inspect
            // the elements explicitly to distinguish "valid string array" from "mixed".
            let strings = anyArray.compactMap { $0 as? String }
            guard strings.count == anyArray.count else {
                return errorResult("Invalid \(key): expected \(expectation)")
            }
            values = strings
        } else {
            return errorResult("Invalid \(key): expected \(expectation)")
        }

        let allRaw = E.allCases.map(\.rawValue)
        let validRaw = Set(allRaw)
        let invalid = values.filter { !validRaw.contains($0) }
        guard invalid.isEmpty else {
            return errorResult(
                "Invalid \(key): \(invalid.joined(separator: ", ")). Must be one of: \(allRaw.joined(separator: ", "))"
            )
        }
        return nil
    }

    private func milestoneToDict(
        _ milestone: Milestone, formatter _: ISO8601DateFormatter, detailed: Bool = false
    ) throws -> [String: Any] {
        var dict = try MCPRecordSnapshot.milestone(milestone).record
        let tasks = milestone.tasks ?? []
        dict["taskCount"] = tasks.count
        if detailed {
            dict["tasks"] = tasks.map { task in
                var taskDict: [String: Any] = [
                    "taskId": task.id.uuidString,
                    "name": task.name,
                    "status": task.statusRawValue,
                    "type": task.typeRawValue,
                    // Effective-priority invariant (Req 1.4): computed accessor, NOT priorityRawValue.
                    "priority": task.priority.rawValue
                ]
                if let displayId = task.permanentDisplayId { taskDict["displayId"] = displayId }
                return taskDict
            }
        }
        return dict
    }

    private func milestoneSummaryDict(_ milestone: Milestone) -> [String: Any] {
        var dict: [String: Any] = [
            "milestoneId": milestone.id.uuidString,
            "name": milestone.name,
            "status": milestone.statusRawValue,
            "taskCount": (milestone.tasks ?? []).count
        ]
        if let displayId = milestone.permanentDisplayId { dict["displayId"] = displayId }
        return dict
    }

}

extension MCPToolHandler {
    /// Shared with batch invocation; the default policy preserves standalone behavior.
    func protectedWriteResult(
        tool: String, arguments: [String: Any], batchPolicy: MCPBatchWritePolicy? = nil
    ) async -> MCPToolResult {
        if let writeCoordinator {
            return await writeCoordinator.execute(tool: tool, arguments: arguments, batchPolicy: batchPolicy)
        }
        do {
            let command = try MCPWriteCommand.validate(tool: tool, arguments: arguments)
            return MCPWriteOutcome.result(MCPWriteOutcome.failure(tool: tool, key: command.key,
                failure: .init("PERSISTENCE_UNAVAILABLE", "Protected write storage is not available"),
                accepted: false, retryAction: "retry_same_request"), isError: true)
        } catch {
            return MCPWriteOutcome.result(MCPWriteOutcome.failure(tool: tool,
                key: arguments["idempotencyKey"] as? String, failure: MCPWriteFailure.from(error), accepted: false),
                isError: true)
        }
    }

    func batchPreview(_ request: MCPBatchTaskRequest) throws -> MCPBatchTaskPreview.Report {
        guard let batchContainer else {
            return .init(entries: request.items.map {
                .init(index: $0.index, itemId: $0.itemId, state: .unavailable, code: "PERSISTENCE_UNAVAILABLE",
                      current: nil, proposedEffects: nil)
            }, observation: "saved_local_store", keyState: "unchecked", advisory: true, isError: true)
        }
        return try MCPBatchTaskPreview.evaluate(request, container: batchContainer, persistence: persistence)
    }

    func executeBatchItem(_ item: MCPBatchTaskRequest.Item) async throws -> MCPBatchTaskCoordinator.Execution {
        var pendingEditsStop = false
        let policy = MCPBatchWritePolicy(onPendingEditsStop: { pendingEditsStop = true })
        let result = await protectedWriteResult(tool: item.command.tool,
            arguments: item.command.arguments, batchPolicy: policy)
        guard result.content.count == 1, let text = result.content.first?.text else {
            throw MCPResultBoundaryError.unsupportedEvidence
        }
        let source = try MCPResultAdapter.source(text: text, isError: result.isError,
            origin: .retainedJSON, evidence: .established)
        return .init(source: source, pendingEditsStop: pendingEditsStop)
    }
}

#endif
