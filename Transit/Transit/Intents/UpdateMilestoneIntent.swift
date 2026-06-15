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
        "description" (new description; pass "" or whitespace-only to clear), \
        "status" (open | done | abandoned). \
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
        let description: FieldChange<String>
        var hasChanges: Bool { status != nil || name != nil || description.isChange }
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
        // Validate status. When the key is present it MUST be a string — a non-string value
        // (e.g. integer, boolean, null) would otherwise be silently dropped by `as? String`,
        // letting other update fields apply with the malformed status quietly ignored [T-830].
        var newStatus: MilestoneStatus?
        if json["status"] != nil {
            guard let statusString = json["status"] as? String else {
                return .invalid(IntentError.invalidStatus(hint: "status must be a string").json)
            }
            guard let parsed = MilestoneStatus(rawValue: statusString) else {
                return .invalid(IntentError.invalidStatus(hint: "Unknown status: \(statusString)").json)
            }
            newStatus = parsed
        }

        // Validate name. Only use "name" as a rename when identified by displayId or
        // milestoneId; otherwise the rename field is "newName". When the relevant key is
        // present it MUST be a string — a non-string value (integer, boolean, null,
        // array) would otherwise be silently dropped by `as? String`, letting other
        // update fields apply with the malformed rename quietly ignored [T-1230].
        var trimmedName: String?
        let renameKey = (json["displayId"] != nil || json["milestoneId"] != nil) ? "name" : "newName"
        if let rawName = json[renameKey] {
            guard let name = rawName as? String else {
                return .invalid(IntentError.invalidInput(hint: "\(renameKey) must be a string").json)
            }
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

        // Validate description. Same reasoning as name: a present-but-non-string
        // value must be rejected rather than silently dropped [T-1230]. An empty
        // or whitespace-only string is an explicit clear signal that sets the
        // description back to nil, mirroring update_task's clear semantics [T-1555].
        let newDescription: FieldChange<String>
        if let rawDescription = json["description"] {
            guard let descriptionString = rawDescription as? String else {
                return .invalid(IntentError.invalidInput(hint: "description must be a string").json)
            }
            let trimmed = descriptionString.trimmingCharacters(in: .whitespacesAndNewlines)
            newDescription = trimmed.isEmpty ? .clear : .set(trimmed)
        } else {
            newDescription = .noChange
        }

        return .valid(ValidatedUpdate(
            status: newStatus, name: trimmedName, description: newDescription
        ))
    }

    // MARK: - Apply

    // Mirrors MilestoneService.updateStatus for status side effects — keep in sync.
    @MainActor
    private static func applyUpdate(_ update: ValidatedUpdate, to milestone: Milestone) {
        // T-923: Skip timestamp writes when the requested status matches the
        // current status so same-status retries don't rewrite completion dates.
        if let newStatus = update.status, milestone.statusRawValue != newStatus.rawValue {
            milestone.statusRawValue = newStatus.rawValue
            milestone.lastStatusChangeDate = Date.now
            milestone.completionDate = newStatus.isTerminal ? Date.now : nil
        }
        if let name = update.name {
            milestone.name = name
        }
        switch update.description {
        case .noChange:
            break
        case .set(let value):
            milestone.milestoneDescription = value
        case .clear:
            milestone.milestoneDescription = nil
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
        // Emit description only when set, matching the MCP `milestoneToDict`
        // serializer: a cleared (nil) description is omitted entirely so callers
        // can distinguish "no description" from an empty string [T-1555].
        if let description = milestone.milestoneDescription {
            response["description"] = description
        }
        return IntentHelpers.encodeJSON(response)
    }
}
