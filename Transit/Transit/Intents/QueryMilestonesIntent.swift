import AppIntents
import Foundation
import SwiftData

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
            projectService: projectService,
            modelContext: projectService.context
        )
        return .result(value: result)
    }

    // MARK: - Logic (testable without @Dependency)

    @MainActor
    static func execute(
        input: String,
        milestoneService: MilestoneService,
        projectService: ProjectService,
        modelContext: ModelContext
    ) -> String {
        let json = parseInput(input)
        guard let json else {
            return IntentError.invalidInput(hint: "Expected valid JSON object").json
        }

        // Single-milestone lookup by displayId
        if let displayIdValue = json["displayId"] {
            let displayId: Int
            if let intVal = displayIdValue as? Int {
                displayId = intVal
            } else if let doubleVal = displayIdValue as? Double {
                displayId = Int(doubleVal)
            } else {
                return IntentError.invalidInput(hint: "displayId must be an integer").json
            }

            var descriptor = FetchDescriptor<Milestone>(
                predicate: #Predicate { $0.permanentDisplayId == displayId }
            )
            descriptor.fetchLimit = 1
            let matches = (try? modelContext.fetch(descriptor)) ?? []
            return IntentHelpers.encodeJSONArray(matches.map { milestoneToDict($0, detailed: true) })
        }

        // Fetch all milestones and filter in-memory
        let allMilestones = (try? modelContext.fetch(FetchDescriptor<Milestone>())) ?? []
        let filtered = applyFilters(json, to: allMilestones, projectService: projectService)
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

    @MainActor
    private static func applyFilters(
        _ json: [String: Any],
        to milestones: [Milestone],
        projectService: ProjectService
    ) -> [Milestone] {
        let projectId: UUID? = (json["projectId"] as? String).flatMap(UUID.init)
        let projectName = json["project"] as? String
        let statusFilter = json["status"] as? String
        let searchText = (json["search"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveSearch = (searchText?.isEmpty == true) ? nil : searchText

        // Resolve project filter
        var resolvedProjectId: UUID?
        if let projectId {
            resolvedProjectId = projectId
        } else if let projectName {
            if case .success(let project) = projectService.findProject(name: projectName) {
                resolvedProjectId = project.id
            } else {
                return []
            }
        }

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
                    "type": task.typeRawValue
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
