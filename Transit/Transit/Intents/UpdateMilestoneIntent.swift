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

        if let error = applyStatusChange(json, milestone: milestone, milestoneService: milestoneService) {
            return error
        }

        if let error = applyFieldUpdates(
            json, milestone: milestone, milestoneService: milestoneService
        ) {
            return error
        }

        return buildResponse(milestone, previousStatus: previousStatus)
    }

    // MARK: - Private Helpers

    @MainActor
    private static func applyStatusChange(
        _ json: [String: Any],
        milestone: Milestone,
        milestoneService: MilestoneService
    ) -> String? {
        guard let statusString = json["status"] as? String else { return nil }
        guard let newStatus = MilestoneStatus(rawValue: statusString) else {
            return IntentError.invalidStatus(hint: "Unknown status: \(statusString)").json
        }
        do {
            try milestoneService.updateStatus(milestone, to: newStatus)
        } catch {
            return IntentError.invalidInput(hint: "Status update failed").json
        }
        return nil
    }

    @MainActor
    private static func applyFieldUpdates(
        _ json: [String: Any],
        milestone: Milestone,
        milestoneService: MilestoneService
    ) -> String? {
        // Only use "name" as a rename when identified by displayId or milestoneId
        let effectiveName: String?
        if json["displayId"] != nil || json["milestoneId"] != nil {
            effectiveName = json["name"] as? String
        } else {
            effectiveName = json["newName"] as? String
        }
        let newDescription = json["description"] as? String

        guard effectiveName != nil || newDescription != nil else { return nil }

        do {
            try milestoneService.updateMilestone(
                milestone, name: effectiveName, description: newDescription
            )
        } catch let error as MilestoneService.Error {
            return IntentHelpers.mapMilestoneError(error).json
        } catch {
            return IntentError.invalidInput(hint: "Update failed").json
        }
        return nil
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
