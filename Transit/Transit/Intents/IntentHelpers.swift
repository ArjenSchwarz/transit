import Foundation

// swiftlint:disable type_body_length
/// Shared utilities for App Intent JSON parsing and response encoding.
/// Nonisolated because these are pure functions that only use Foundation types.
nonisolated enum IntentHelpers {

    /// Extracts an integer from a value that may be `Int`, `Double`, or `NSNumber`.
    /// JSONSerialization and MCP argument passing may deliver JSON integers as `Double`.
    /// Returns `nil` for non-numeric or non-integral values (e.g. 42.5).
    static func parseIntValue(_ value: Any?) -> Int? {
        guard let value else { return nil }
        if let intVal = value as? Int { return intVal }
        if let doubleVal = value as? Double { return Int(exactly: doubleVal) }
        return nil
    }

    /// Parses a JSON string into a dictionary. Returns nil for malformed input.
    static func parseJSON(_ input: String) -> [String: Any]? {
        guard let data = input.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }

    /// Extracts string metadata entries from a JSON object value.
    /// Non-string values are ignored because task metadata is stored as `[String: String]`.
    static func stringMetadata(from value: Any?) -> [String: String]? {
        // Fast path for native callers/tests that already provide the expected metadata type.
        if let metadata = value as? [String: String], !metadata.isEmpty {
            return metadata
        }
        guard let dict = value as? [String: Any], !dict.isEmpty else {
            return nil
        }
        let metadata = dict.reduce(into: [String: String]()) { result, pair in
            guard let stringValue = pair.value as? String else { return }
            result[pair.key] = stringValue
        }
        return metadata.isEmpty ? nil : metadata
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

    enum EncodingError: Swift.Error { case utf8 }

    /// Encodes an `Encodable` value as a UTF-8 JSON string. Used by both the MCP
    /// dispatch handler and the maintenance Intents so they share a byte-equal
    /// encoding for the same input.
    static func encodeAsJSONString(_ value: some Encodable) throws -> String {
        let data = try JSONEncoder().encode(value)
        guard let text = String(data: data, encoding: .utf8) else {
            throw EncodingError.utf8
        }
        return text
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
        case .duplicateDisplayID:
            .internalError(hint: "A duplicate milestone identifier was detected")
        case .projectRequired:
            .invalidInput(hint: "Task must belong to a project before assigning a milestone")
        case .projectMismatch:
            .milestoneProjectMismatch(hint: "Milestone and task must belong to the same project")
        }
    }

    /// Resolves a task from JSON containing displayId or taskId, mapping errors to `IntentError`.
    @MainActor
    static func resolveTask(
        from json: [String: Any],
        taskService: TaskService
    ) -> Result<TransitTask, IntentError> {
        do {
            return .success(try taskService.resolveTask(from: json))
        } catch {
            return .failure(.taskNotFound(
                hint: "Provide either displayId (integer) or taskId (UUID)"
            ))
        }
    }

    /// Validates that a JSON field, if present, is a valid UUID string. Returns the parsed UUID,
    /// nil when absent, or `.failure` when present but malformed. [T-753]
    static func validateUUIDField(
        _ key: String, in json: [String: Any]
    ) -> Result<UUID?, IntentError> {
        guard let value = json[key] else { return .success(nil) }
        guard let str = value as? String, let uuid = UUID(uuidString: str) else {
            return .failure(.invalidInput(hint: "\(key) must be a valid UUID"))
        }
        return .success(uuid)
    }

    /// Resolves a milestone from JSON containing displayId or milestoneId.
    @MainActor
    static func resolveMilestone(
        from json: [String: Any],
        milestoneService: MilestoneService,
        projectService: ProjectService
    ) -> Result<Milestone, IntentError> {
        if json["displayId"] != nil {
            return resolveMilestoneByDisplayId(json, milestoneService: milestoneService)
        } else if json["milestoneId"] != nil {
            return resolveMilestoneById(json, milestoneService: milestoneService)
        } else if let name = json["name"] as? String {
            return resolveMilestoneByName(
                name, json: json,
                milestoneService: milestoneService, projectService: projectService
            )
        }
        return .failure(.invalidInput(hint: "Provide displayId, milestoneId, or name with project"))
    }

    /// Resolves a milestone by its integer display ID.
    @MainActor
    private static func resolveMilestoneByDisplayId(
        _ json: [String: Any], milestoneService: MilestoneService
    ) -> Result<Milestone, IntentError> {
        guard let displayId = parseIntValue(json["displayId"]) else {
            return .failure(.invalidInput(hint: "displayId must be an integer"))
        }
        do {
            return .success(try milestoneService.findByDisplayID(displayId))
        } catch MilestoneService.Error.duplicateDisplayID {
            return .failure(.internalError(hint: "Duplicate milestone identifier for displayId \(displayId)"))
        } catch {
            return .failure(.milestoneNotFound(hint: "No milestone with displayId \(displayId)"))
        }
    }

    /// Resolves a milestone by its UUID identifier. Rejects non-UUID values with INVALID_INPUT. [T-753]
    @MainActor
    private static func resolveMilestoneById(
        _ json: [String: Any], milestoneService: MilestoneService
    ) -> Result<Milestone, IntentError> {
        switch validateUUIDField("milestoneId", in: json) {
        case .failure(let error): return .failure(error)
        case .success(nil): // unreachable: caller gates on key presence
            return .failure(.invalidInput(hint: "milestoneId must be a valid UUID"))
        case .success(let uuid?):
            do {
                return .success(try milestoneService.findByID(uuid))
            } catch {
                let idStr = json["milestoneId"] as? String ?? "unknown"
                return .failure(.milestoneNotFound(hint: "No milestone with ID \(idStr)"))
            }
        }
    }

    /// Resolves a milestone by name within a project. Rejects non-UUID projectId values. [T-753]
    @MainActor
    private static func resolveMilestoneByName(
        _ name: String,
        json: [String: Any],
        milestoneService: MilestoneService,
        projectService: ProjectService
    ) -> Result<Milestone, IntentError> {
        switch validateUUIDField("projectId", in: json) {
        case .failure(let error): return .failure(error)
        case .success(let projectId):
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
    }

    /// Converts a TransitTask to a JSON-compatible dictionary.
    /// When `detailed` is true, includes `description` and `metadata` fields.
    @MainActor
    static func taskToDict(
        _ task: TransitTask, formatter: ISO8601DateFormatter, detailed: Bool = false
    ) -> [String: Any] {
        var dict: [String: Any] = [
            "taskId": task.id.uuidString,
            "name": task.name,
            "status": task.statusRawValue,
            "type": task.typeRawValue,
            "lastStatusChangeDate": formatter.string(from: task.lastStatusChangeDate)
        ]
        if let displayId = task.permanentDisplayId {
            dict["displayId"] = displayId
        }
        if let projectId = task.project?.id.uuidString {
            dict["projectId"] = projectId
        }
        if let projectName = task.project?.name {
            dict["projectName"] = projectName
        }
        if let completionDate = task.completionDate {
            dict["completionDate"] = formatter.string(from: completionDate)
        }
        if let milestone = task.milestone {
            dict["milestone"] = milestoneInfoDict(milestone)
        }
        if detailed {
            dict["description"] = task.taskDescription as Any
            if !task.metadata.isEmpty {
                dict["metadata"] = task.metadata
            }
        }
        return dict
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
        if json["milestoneDisplayId"] != nil, parseIntValue(json["milestoneDisplayId"]) == nil {
            return IntentError.invalidInput(hint: "milestoneDisplayId must be an integer").json
        }
        if let milestoneDisplayId = parseIntValue(json["milestoneDisplayId"]) {
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
// swiftlint:enable type_body_length
