import AppIntents
import Foundation

/// Updates a milestone's name, description, or status via JSON input.
/// Exposed as "Transit: Update Milestone" in Shortcuts. [req 13.3]
struct UpdateMilestoneIntent: AppIntent {
    nonisolated(unsafe) static var title: LocalizedStringResource = "Transit: Update Milestone"

    nonisolated(unsafe) static var description = IntentDescription(
        "Update a milestone's name, description, or status.",
        categoryName: "Milestones",
        resultValueName: "Milestone JSON"
    )

    nonisolated(unsafe) static var openAppWhenRun: Bool = true

    @Parameter(
        title: "Input JSON",
        description: """
        JSON object with a milestone identifier and optional update fields. Identify by "displayId" \
        (integer), "milestoneId" (UUID), or "name" + "project"/"projectId". \
        Update fields: "name" (new name when identified by displayId/milestoneId), \
        "newName" (new name when identified by name+project), \
        "description" (new description), "status" (open | done | abandoned). \
        Example: {"displayId": 1, "status": "done"}
        """
    )
    var input: String

    @Dependency
    private var milestoneService: MilestoneService

    @Dependency
    private var projectService: ProjectService

    @MainActor
    func perform() async throws -> some ReturnsValue<String> {
        let result = UpdateMilestoneIntent.execute(
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
        projectService: ProjectService
    ) -> String {
        guard let json = IntentHelpers.parseJSON(input) else {
            return IntentError.invalidInput(hint: "Expected valid JSON object").json
        }

        let milestone: Milestone
        switch IntentHelpers.resolveMilestone(
            from: json, milestoneService: milestoneService, projectService: projectService
        ) {
        case .success(let found): milestone = found
        case .failure(let error): return error.json
        }

        let previousStatus = milestone.statusRawValue

        // Validate all inputs before applying any changes (T-626: avoid partial updates)
        let validated: ValidatedUpdate
        switch validateUpdate(json, milestone: milestone, milestoneService: milestoneService) {
        case .valid(let update): validated = update
        case .invalid(let error): return error
        }

        // Apply all changes in memory, then save atomically
        applyUpdate(validated, to: milestone)

        if validated.hasChanges {
            do {
                try milestoneService.save()
            } catch {
                return IntentError.invalidInput(hint: "Update failed").json
            }
        }

        return buildResponse(milestone, previousStatus: previousStatus)
    }

    // MARK: - Validation

    private struct ValidatedUpdate {
        let status: MilestoneStatus?
        let name: String?
        let description: String?
        var hasChanges: Bool { status != nil || name != nil || description != nil }
    }

    private enum Validation {
        case valid(ValidatedUpdate)
        case invalid(String)
    }

    @MainActor
    private static func validateUpdate(
        _ json: [String: Any],
        milestone: Milestone,
        milestoneService: MilestoneService
    ) -> Validation {
        // Validate status
        var newStatus: MilestoneStatus?
        if let statusString = json["status"] as? String {
            guard let parsed = MilestoneStatus(rawValue: statusString) else {
                return .invalid(IntentError.invalidStatus(hint: "Unknown status: \(statusString)").json)
            }
            newStatus = parsed
        }

        // Validate name
        var trimmedName: String?
        // Only use "name" as a rename when identified by displayId or milestoneId
        let effectiveName: String?
        if json["displayId"] != nil || json["milestoneId"] != nil {
            effectiveName = json["name"] as? String
        } else {
            effectiveName = json["newName"] as? String
        }
        if let name = effectiveName {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return .invalid(IntentHelpers.mapMilestoneError(.invalidName).json)
            }
            if let project = milestone.project,
               milestoneService.milestoneNameExists(trimmed, in: project, excluding: milestone.id) {
                return .invalid(IntentHelpers.mapMilestoneError(.duplicateName).json)
            }
            trimmedName = trimmed
        }

        return .valid(ValidatedUpdate(
            status: newStatus, name: trimmedName, description: json["description"] as? String
        ))
    }

    // MARK: - Apply

    // Mirrors MilestoneService.updateStatus for status side effects — keep in sync.
    @MainActor
    private static func applyUpdate(_ update: ValidatedUpdate, to milestone: Milestone) {
        if let newStatus = update.status {
            milestone.statusRawValue = newStatus.rawValue
            milestone.lastStatusChangeDate = Date.now
            milestone.completionDate = newStatus.isTerminal ? Date.now : nil
        }
        if let name = update.name {
            milestone.name = name
        }
        if let description = update.description {
            milestone.milestoneDescription = description
        }
    }

    @MainActor
    private static func buildResponse(
        _ milestone: Milestone, previousStatus: String
    ) -> String {
        var response: [String: Any] = [
            "milestoneId": milestone.id.uuidString,
            "name": milestone.name,
            "status": milestone.statusRawValue,
            "previousStatus": previousStatus,
            "projectId": milestone.project?.id.uuidString ?? "",
            "projectName": milestone.project?.name ?? ""
        ]
        if let displayId = milestone.permanentDisplayId {
            response["displayId"] = displayId
        }
        return IntentHelpers.encodeJSON(response)
    }
}
