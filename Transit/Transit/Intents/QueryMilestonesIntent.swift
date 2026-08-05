import AppIntents
import Foundation

/// Narrow seam over the milestone service's full-table fetch so query intents can be
/// tested against a failing storage layer. `MilestoneService` conforms directly. [T-1566]
@MainActor
protocol MilestoneFetching {
    func fetchAllMilestones() throws -> [Milestone]
}

extension MilestoneService: MilestoneFetching {}

/// Queries milestones with optional filters via JSON input. Exposed as "Transit: Query Milestones"
/// in Shortcuts. [req 13.2]
struct QueryMilestonesIntent: AppIntent {
    nonisolated(unsafe) static var title: LocalizedStringResource = "Transit: Query Milestones"

    nonisolated(unsafe) static var description = IntentDescription(
        "Search and filter milestones. Pass an empty string or {} to return all milestones.",
        categoryName: "Milestones",
        resultValueName: "Milestones JSON"
    )

    nonisolated(unsafe) static var openAppWhenRun: Bool = true

    @Parameter(
        title: "Input JSON",
        description: """
        JSON object with optional filters: "displayId" (integer, for single-milestone lookup with tasks), \
        "project" (name), "projectId" (UUID), "status" (open | done | abandoned), \
        "search" (case-insensitive substring match on name and description). \
        All filters are optional. Example: {"project":"Alpha","status":"open"}
        """
    )
    var input: String

    @Dependency
    private var milestoneService: MilestoneService

    @Dependency
    private var projectService: ProjectService

    @MainActor
    func perform() async throws -> some ReturnsValue<String> {
        let result = QueryMilestonesIntent.execute(
            input: input,
            milestoneService: milestoneService,
            projectService: projectService
        )
        return .result(value: result)
    }

    // MARK: - Logic (testable without @Dependency)

    @MainActor
    static func execute(
        input: String,
        milestoneService: MilestoneService,
        projectService: ProjectService,
        milestoneFetcher: MilestoneFetching? = nil
    ) -> String {
        let json = parseInput(input)
        guard let json else {
            return IntentError.invalidInput(hint: "Expected valid JSON object").json
        }

        let resolvedProjectId: UUID?
        switch resolveValidatedProjectFilter(json, projectService: projectService) {
        case .unfiltered:
            resolvedProjectId = nil
        case .resolved(let projectId):
            resolvedProjectId = projectId
        case .noMatch:
            return IntentHelpers.encodeJSONArray([])
        case .error(let error):
            return error.json
        }

        // Single-milestone lookup by displayId. Remaining filters still apply conjunctively —
        // a milestone that does not satisfy them is filtered out, mirroring QueryTasksIntent [T-963].
        if json["displayId"] != nil {
            // Route through IntentHelpers.parseIntValue so JSON booleans (delivered as
            // NSNumber wrapping CFBoolean) are rejected rather than silently coerced to
            // 1/0 and targeting M-1/M-0. A plain `as? Int` would accept them. [T-1280]
            guard let displayId = IntentHelpers.parseIntValue(json["displayId"]) else {
                return IntentError.invalidInput(hint: "displayId must be an integer").json
            }

            let milestone: Milestone
            do {
                milestone = try milestoneService.findByDisplayID(displayId)
            } catch MilestoneService.Error.duplicateDisplayID {
                return IntentHelpers.mapMilestoneError(.duplicateDisplayID).json
            } catch {
                return IntentHelpers.encodeJSONArray([])
            }
            let filtered = applyFilters(json, to: [milestone], resolvedProjectId: resolvedProjectId)
            return IntentHelpers.encodeJSONArray(filtered.map { milestoneToDict($0, detailed: true) })
        }

        // Fetch all milestones and filter in-memory. Surface storage fetch failures as
        // INTERNAL_ERROR instead of letting `try?` collapse them into a successful empty
        // array, which a caller cannot tell apart from a valid "no milestones match"
        // result. Mirrors the MCP query path. [T-1566]
        let fetcher = milestoneFetcher ?? milestoneService
        let allMilestones: [Milestone]
        do {
            allMilestones = try fetcher.fetchAllMilestones()
        } catch {
            return IntentError.internalError(hint: "Failed to fetch milestones: \(error)").json
        }
        let filtered = applyFilters(json, to: allMilestones, resolvedProjectId: resolvedProjectId)
        return IntentHelpers.encodeJSONArray(filtered.map { milestoneToDict($0) })
    }

    // MARK: - Private Helpers

    private static func parseInput(_ input: String) -> [String: Any]? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return [:]
        }
        return IntentHelpers.parseJSON(trimmed)
    }

    /// Validates the `status`, `project`, and `search` filters when present. When a key is present
    /// it MUST be a string — a non-string value (e.g. integer, boolean, array, null) would otherwise
    /// be silently dropped by `as? String` and the filter ignored entirely [T-830, T-1116, T-1156].
    private static func validateFilters(_ json: [String: Any]) -> IntentError? {
        if json["status"] != nil {
            guard let status = json["status"] as? String else {
                return .invalidStatus(hint: "status must be a string")
            }
            guard MilestoneStatus(rawValue: status) != nil else {
                return .invalidStatus(hint: "Unknown status: \(status)")
            }
        }
        if json["project"] != nil, !(json["project"] is String) {
            return .invalidInput(hint: "project must be a string")
        }
        // A present non-string `search` would be silently dropped by `as? String` in
        // applyFilters, ignoring the filter entirely. Reject it instead [T-1156].
        if json["search"] != nil, !(json["search"] is String) {
            return .invalidInput(hint: "search must be a string")
        }
        return nil
    }

    /// Validates and resolves the project filter before any milestone read. A valid
    /// `projectId` wins over `project`; ordinary name misses and ambiguity remain
    /// successful empty arrays, while storage failure is an INTERNAL_ERROR [T-1657].
    @MainActor
    private static func resolveValidatedProjectFilter(
        _ json: [String: Any],
        projectService: ProjectService
    ) -> ProjectFilterResolution {
        let projectId: UUID?
        switch IntentHelpers.validateUUIDField("projectId", in: json) {
        case .failure(let error): return .error(error)
        case .success(let parsed): projectId = parsed
        }
        if let validationError = validateFilters(json) {
            return .error(validationError)
        }
        return resolveProjectFilter(json, projectId: projectId, projectService: projectService)
    }

    private enum ProjectFilterResolution {
        case unfiltered
        case resolved(UUID)
        case noMatch
        case error(IntentError)
    }

    @MainActor
    private static func resolveProjectFilter(
        _ json: [String: Any],
        projectId: UUID?,
        projectService: ProjectService
    ) -> ProjectFilterResolution {
        if let projectId {
            switch projectService.findProject(id: projectId) {
            case .success(let project):
                return .resolved(project.id)
            case .failure(let error):
                return .error(IntentHelpers.mapProjectLookupError(error))
            }
        }
        guard let projectName = json["project"] as? String else {
            return .unfiltered
        }
        switch projectService.findProject(name: projectName) {
        case .success(let project):
            return .resolved(project.id)
        case .failure(.storageFailure(let hint)):
            return .error(.internalError(hint: hint))
        case .failure:
            return .noMatch
        }
    }

    @MainActor
    private static func applyFilters(
        _ json: [String: Any],
        to milestones: [Milestone],
        resolvedProjectId: UUID?
    ) -> [Milestone] {
        let statusFilter = json["status"] as? String
        let searchText = (json["search"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveSearch = (searchText?.isEmpty == true) ? nil : searchText

        var result: [Milestone] = []
        for milestone in milestones {
            if let resolvedProjectId, milestone.project?.id != resolvedProjectId {
                continue
            }
            if let statusFilter, milestone.statusRawValue != statusFilter {
                continue
            }
            if let search = effectiveSearch {
                let nameMatch = milestone.name.localizedCaseInsensitiveContains(search)
                let descMatch = milestone.milestoneDescription?.localizedCaseInsensitiveContains(search) ?? false
                if !nameMatch && !descMatch { continue }
            }
            result.append(milestone)
        }
        return result
    }

    @MainActor
    static func milestoneToDict(_ milestone: Milestone, detailed: Bool = false) -> [String: Any] {
        let isoFormatter = ISO8601DateFormatter()
        var dict: [String: Any] = [
            "milestoneId": milestone.id.uuidString,
            "name": milestone.name,
            "status": milestone.statusRawValue,
            "taskCount": milestone.tasks?.count ?? 0,
            "creationDate": isoFormatter.string(from: milestone.creationDate),
            "lastStatusChangeDate": isoFormatter.string(from: milestone.lastStatusChangeDate)
        ]
        if let displayId = milestone.permanentDisplayId {
            dict["displayId"] = displayId
        }
        if let description = milestone.milestoneDescription {
            dict["description"] = description
        }
        if let projectId = milestone.project?.id.uuidString {
            dict["projectId"] = projectId
        }
        if let projectName = milestone.project?.name {
            dict["projectName"] = projectName
        }
        if let completionDate = milestone.completionDate {
            dict["completionDate"] = isoFormatter.string(from: completionDate)
        }

        if detailed {
            let tasks: [[String: Any]] = (milestone.tasks ?? []).compactMap { task in
                var taskDict: [String: Any] = [
                    "taskId": task.id.uuidString,
                    "name": task.name,
                    "status": task.statusRawValue,
                    "type": task.typeRawValue,
                    // Effective-priority invariant (Req 1.4): computed accessor, NOT priorityRawValue.
                    "priority": task.priority.rawValue
                ]
                if let displayId = task.permanentDisplayId {
                    taskDict["displayId"] = displayId
                }
                return taskDict
            }
            dict["tasks"] = tasks
        }

        return dict
    }
}
