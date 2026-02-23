import AppIntents
import Foundation

/// Creates a new milestone via JSON input. Exposed as "Transit: Create Milestone" in Shortcuts.
/// Always creates milestones in Open status. [req 13.1]
struct CreateMilestoneIntent: AppIntent {
    nonisolated(unsafe) static var title: LocalizedStringResource = "Transit: Create Milestone"

    nonisolated(unsafe) static var description = IntentDescription(
        "Create a new milestone within a project. The milestone starts in Open status.",
        categoryName: "Milestones",
        resultValueName: "Milestone JSON"
    )

    nonisolated(unsafe) static var openAppWhenRun: Bool = true

    @Parameter(
        title: "Input JSON",
        description: """
        JSON object with milestone details. Required fields: "name" (string), plus one of "project" (name) \
        or "projectId" (UUID). Optional: "description" (string). \
        Example: {"name": "v1.0", "project": "Alpha", "description": "First release"}
        """
    )
    var input: String

    @Dependency
    private var milestoneService: MilestoneService

    @Dependency
    private var projectService: ProjectService

    @MainActor
    func perform() async throws -> some ReturnsValue<String> {
        let result = await CreateMilestoneIntent.execute(
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
    ) async -> String {
        guard let json = IntentHelpers.parseJSON(input) else {
            return IntentError.invalidInput(hint: "Expected valid JSON object").json
        }

        guard let name = json["name"] as? String, !name.isEmpty else {
            return IntentError.invalidInput(hint: "Missing required field: name").json
        }

        // Resolve project
        let projectId: UUID? = (json["projectId"] as? String).flatMap(UUID.init)
        let projectName = json["project"] as? String
        let lookupResult = projectService.findProject(id: projectId, name: projectName)

        let project: Project
        switch lookupResult {
        case .success(let found):
            project = found
        case .failure(let error):
            return IntentHelpers.mapProjectLookupError(error).json
        }

        let milestone: Milestone
        do {
            milestone = try await milestoneService.createMilestone(
                name: name,
                description: json["description"] as? String,
                project: project
            )
        } catch let error as MilestoneService.Error {
            return IntentHelpers.mapMilestoneError(error).json
        } catch {
            return IntentError.invalidInput(hint: "Milestone creation failed").json
        }

        var response: [String: Any] = [
            "milestoneId": milestone.id.uuidString,
            "name": milestone.name,
            "status": milestone.statusRawValue,
            "projectId": project.id.uuidString,
            "projectName": project.name
        ]
        if let displayId = milestone.permanentDisplayId {
            response["displayId"] = displayId
        }
        return IntentHelpers.encodeJSON(response)
    }
}
