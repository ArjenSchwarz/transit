import AppIntents
import Foundation

/// Deletes a milestone via JSON input. Tasks assigned to the milestone lose their
/// association but are not deleted. Exposed as "Transit: Delete Milestone" in Shortcuts. [req 13.4]
struct DeleteMilestoneIntent: AppIntent {
    nonisolated(unsafe) static var title: LocalizedStringResource = "Transit: Delete Milestone"

    nonisolated(unsafe) static var description = IntentDescription(
        "Delete a milestone. Tasks assigned to it will be unassigned but not deleted.",
        categoryName: "Milestones",
        resultValueName: "Deletion Result JSON"
    )

    nonisolated(unsafe) static var openAppWhenRun: Bool = true

    @Parameter(
        title: "Input JSON",
        description: """
        JSON object identifying the milestone. Use "displayId" (integer, e.g. 1 for M-1) \
        or "milestoneId" (UUID). Example: {"displayId": 1}
        """
    )
    var input: String

    @Dependency
    private var milestoneService: MilestoneService

    @MainActor
    func perform() async throws -> some ReturnsValue<String> {
        let result = DeleteMilestoneIntent.execute(
            input: input,
            milestoneService: milestoneService
        )
        return .result(value: result)
    }

    // MARK: - Logic (testable without @Dependency)

    @MainActor
    static func execute(
        input: String,
        milestoneService: MilestoneService
    ) -> String {
        guard let json = IntentHelpers.parseJSON(input) else {
            return IntentError.invalidInput(hint: "Expected valid JSON object").json
        }

        let milestone: Milestone
        switch resolveMilestone(from: json, milestoneService: milestoneService) {
        case .success(let found): milestone = found
        case .failure(let error): return error.json
        }

        // Capture info before deletion
        let milestoneId = milestone.id.uuidString
        let displayId = milestone.permanentDisplayId
        let name = milestone.name
        let affectedTasks = milestone.tasks?.count ?? 0

        do {
            try milestoneService.deleteMilestone(milestone)
        } catch {
            return IntentError.invalidInput(hint: "Deletion failed").json
        }

        var response: [String: Any] = [
            "deleted": true,
            "milestoneId": milestoneId,
            "name": name,
            "affectedTasks": affectedTasks
        ]
        if let displayId {
            response["displayId"] = displayId
        }
        return IntentHelpers.encodeJSON(response)
    }

    // MARK: - Identifier resolution

    /// Resolves the milestone from a `displayId` or `milestoneId` JSON field. Returns
    /// the matching `IntentError` when the identifier is missing, malformed, or unmatched.
    /// `milestoneId` is validated separately from key presence so malformed values
    /// produce a milestoneId-specific INVALID_INPUT instead of the generic missing-key
    /// fallback. [T-789]
    @MainActor
    private static func resolveMilestone(
        from json: [String: Any],
        milestoneService: MilestoneService
    ) -> Result<Milestone, IntentError> {
        if json["displayId"] != nil {
            return resolveByDisplayId(json, milestoneService: milestoneService)
        }
        if json["milestoneId"] != nil {
            return resolveByMilestoneId(json, milestoneService: milestoneService)
        }
        return .failure(.invalidInput(hint: "Provide displayId or milestoneId"))
    }

    @MainActor
    private static func resolveByDisplayId(
        _ json: [String: Any], milestoneService: MilestoneService
    ) -> Result<Milestone, IntentError> {
        guard let displayId = IntentHelpers.parseIntValue(json["displayId"]) else {
            return .failure(.invalidInput(hint: "displayId must be an integer"))
        }
        do {
            return .success(try milestoneService.findByDisplayID(displayId))
        } catch let error as MilestoneService.Error {
            return .failure(IntentHelpers.mapMilestoneError(error))
        } catch {
            return .failure(.milestoneNotFound(hint: "No milestone with displayId \(displayId)"))
        }
    }

    @MainActor
    private static func resolveByMilestoneId(
        _ json: [String: Any], milestoneService: MilestoneService
    ) -> Result<Milestone, IntentError> {
        switch IntentHelpers.validateUUIDField("milestoneId", in: json) {
        case .failure(let error):
            return .failure(error)
        case .success(nil):
            // Unreachable: caller gates on key presence.
            return .failure(.invalidInput(hint: "milestoneId must be a valid UUID"))
        case .success(let uuid?):
            do {
                return .success(try milestoneService.findByID(uuid))
            } catch {
                return .failure(.milestoneNotFound(hint: "No milestone with ID \(uuid.uuidString)"))
            }
        }
    }
}
