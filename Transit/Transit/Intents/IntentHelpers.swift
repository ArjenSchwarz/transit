import Foundation

/// Shared utilities for App Intent JSON parsing and response encoding.
/// Nonisolated because these are pure functions that only use Foundation types.
nonisolated enum IntentHelpers {

    /// Parses a JSON string into a dictionary. Returns nil for malformed input.
    static func parseJSON(_ input: String) -> [String: Any]? {
        guard let data = input.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }

    /// Encodes a dictionary as a JSON string. Returns an error JSON on failure.
    static func encodeJSON(_ dict: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let string = String(data: data, encoding: .utf8) else {
            return IntentError.invalidInput(hint: "Failed to encode response").json
        }
        return string
    }

    /// Encodes an array of dictionaries as a JSON string.
    static func encodeJSONArray(_ array: [[String: Any]]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: array),
              let string = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return string
    }

    /// Translates ProjectLookupError to IntentError.
    static func mapProjectLookupError(_ error: ProjectLookupError) -> IntentError {
        switch error {
        case .notFound(let hint):
            .projectNotFound(hint: hint)
        case .ambiguous(let hint):
            .ambiguousProject(hint: hint)
        case .noIdentifier:
            .invalidInput(hint: "Either projectId or project name is required")
        }
    }

    /// Translates MilestoneService.Error to IntentError.
    static func mapMilestoneError(_ error: MilestoneService.Error) -> IntentError {
        switch error {
        case .invalidName:
            .invalidInput(hint: "Milestone name cannot be empty")
        case .milestoneNotFound:
            .milestoneNotFound(hint: "No matching milestone found")
        case .duplicateName:
            .duplicateMilestoneName(hint: "A milestone with this name already exists in the project")
        case .projectRequired:
            .invalidInput(hint: "Task must belong to a project before assigning a milestone")
        case .projectMismatch:
            .milestoneProjectMismatch(hint: "Milestone and task must belong to the same project")
        }
    }

    /// Resolves a task from JSON containing displayId or taskId.
    @MainActor
    static func resolveTask(
        from json: [String: Any],
        taskService: TaskService
    ) -> Result<TransitTask, IntentError> {
        if let displayId = json["displayId"] as? Int {
            do {
                return .success(try taskService.findByDisplayID(displayId))
            } catch {
                return .failure(.taskNotFound(hint: "No task with displayId \(displayId)"))
            }
        } else if let idString = json["taskId"] as? String, let uuid = UUID(uuidString: idString) {
            do {
                return .success(try taskService.findByID(uuid))
            } catch {
                return .failure(.taskNotFound(hint: "No task with taskId \(idString)"))
            }
        }
        return .failure(.invalidInput(hint: "Provide either displayId (integer) or taskId (UUID)"))
    }

    /// Resolves a milestone from JSON containing displayId or milestoneId.
    @MainActor
    static func resolveMilestone(
        from json: [String: Any],
        milestoneService: MilestoneService,
        projectService: ProjectService
    ) -> Result<Milestone, IntentError> {
        if let displayIdValue = json["displayId"] {
            guard let displayId = displayIdValue as? Int ?? (displayIdValue as? Double).map(Int.init) else {
                return .failure(.invalidInput(hint: "displayId must be an integer"))
            }
            do {
                return .success(try milestoneService.findByDisplayID(displayId))
            } catch {
                return .failure(.milestoneNotFound(hint: "No milestone with displayId \(displayId)"))
            }
        } else if let idString = json["milestoneId"] as? String, let uuid = UUID(uuidString: idString) {
            do {
                return .success(try milestoneService.findByID(uuid))
            } catch {
                return .failure(.milestoneNotFound(hint: "No milestone with ID \(idString)"))
            }
        } else if let name = json["name"] as? String {
            let projectId: UUID? = (json["projectId"] as? String).flatMap(UUID.init)
            let projectName = json["project"] as? String
            let lookupResult = projectService.findProject(id: projectId, name: projectName)
            guard case .success(let project) = lookupResult else {
                if case .failure(let error) = lookupResult {
                    return .failure(mapProjectLookupError(error))
                }
                return .failure(.invalidInput(hint: "Project required for name-based lookup"))
            }
            guard let found = milestoneService.findByName(name, in: project) else {
                return .failure(.milestoneNotFound(
                    hint: "No milestone named '\(name)' in project '\(project.name)'"
                ))
            }
            return .success(found)
        }
        return .failure(.invalidInput(hint: "Provide displayId, milestoneId, or name with project"))
    }

    /// Builds a milestone info dictionary for inclusion in task responses.
    @MainActor
    static func milestoneInfoDict(_ milestone: Milestone) -> [String: Any] {
        var info: [String: Any] = [
            "milestoneId": milestone.id.uuidString,
            "name": milestone.name
        ]
        if let displayId = milestone.permanentDisplayId {
            info["displayId"] = displayId
        }
        return info
    }

    /// Assigns a milestone to a task from JSON, returning an error string on failure.
    @MainActor
    static func assignMilestone(
        from json: [String: Any],
        to task: TransitTask,
        milestoneService: MilestoneService
    ) -> String? {
        if let milestoneDisplayId = json["milestoneDisplayId"] as? Int {
            do {
                let milestone = try milestoneService.findByDisplayID(milestoneDisplayId)
                try milestoneService.setMilestone(milestone, on: task)
            } catch let error as MilestoneService.Error {
                return mapMilestoneError(error).json
            } catch {
                return IntentError.milestoneNotFound(
                    hint: "No milestone with displayId \(milestoneDisplayId)"
                ).json
            }
        } else if let milestoneName = json["milestone"] as? String {
            guard let project = task.project else {
                return IntentError.invalidInput(
                    hint: "Task must belong to a project before assigning a milestone"
                ).json
            }
            guard let milestone = milestoneService.findByName(milestoneName, in: project) else {
                return IntentError.milestoneNotFound(
                    hint: "No milestone named '\(milestoneName)' in project '\(project.name)'"
                ).json
            }
            do {
                try milestoneService.setMilestone(milestone, on: task)
            } catch let error as MilestoneService.Error {
                return mapMilestoneError(error).json
            } catch {
                return IntentError.invalidInput(hint: "Failed to assign milestone").json
            }
        }
        return nil
    }
}
