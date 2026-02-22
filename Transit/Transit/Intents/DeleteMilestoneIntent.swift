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

        // Resolve milestone
        let milestone: Milestone
        if let displayIdValue = json["displayId"] {
            let displayId: Int
            if let intVal = displayIdValue as? Int {
                displayId = intVal
            } else if let doubleVal = displayIdValue as? Double {
                displayId = Int(doubleVal)
            } else {
                return IntentError.invalidInput(hint: "displayId must be an integer").json
            }
            do {
                milestone = try milestoneService.findByDisplayID(displayId)
            } catch {
                return IntentError.milestoneNotFound(hint: "No milestone with displayId \(displayId)").json
            }
        } else if let idString = json["milestoneId"] as? String, let uuid = UUID(uuidString: idString) {
            do {
                milestone = try milestoneService.findByID(uuid)
            } catch {
                return IntentError.milestoneNotFound(hint: "No milestone with ID \(idString)").json
            }
        } else {
            return IntentError.invalidInput(hint: "Provide displayId or milestoneId").json
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
}
