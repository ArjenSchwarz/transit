import Foundation

/// Shared validator and applier for `update_task` across the MCP tool and
/// `UpdateTaskIntent`. Both surfaces parse JSON into `[String: Any]`, resolve
/// the target task, then call `validate` to produce a `ValidatedTaskUpdate`
/// and (if any changes are present) `apply` to mutate the task in memory.
/// Saving is the caller's responsibility so a single transaction covers
/// every mutation. [T-650]
@MainActor
enum TaskUpdateValidator {

    /// Walks the JSON args in a deterministic order (name → description → type
    /// → metadata → milestone) and produces a fully-validated update. Pure:
    /// never mutates `task` or the model context. Milestone resolution uses
    /// `milestoneService` for read-only lookups. The walk order is not part
    /// of the public contract (AC 5.2) — callers MUST NOT depend on which
    /// invalid field surfaces when multiple are invalid.
    static func validate(
        _ args: [String: Any],
        task: TransitTask,
        milestoneService: MilestoneService
    ) -> Result<ValidatedTaskUpdate, TaskUpdateValidationError> {
        // name
        let name: String?
        switch validateName(args) {
        case .failure(let error): return .failure(error)
        case .success(let value): name = value
        }

        // description
        let description: FieldChange<String>
        switch validateDescription(args) {
        case .failure(let error): return .failure(error)
        case .success(let value): description = value
        }

        // type
        let type: TaskType?
        switch validateType(args) {
        case .failure(let error): return .failure(error)
        case .success(let value): type = value
        }

        // metadata
        let metadata: FieldChange<[String: String]>
        switch strictStringMetadata(from: args["metadata"]) {
        case .failure(let error): return .failure(error)
        case .success(let value): metadata = value
        }

        // milestone
        let milestoneAction: MilestoneAction?
        switch validateMilestone(args, task: task, milestoneService: milestoneService) {
        case .failure(let error): return .failure(error)
        case .success(let value): milestoneAction = value
        }

        return .success(
            ValidatedTaskUpdate(
                name: name,
                description: description,
                type: type,
                metadata: metadata,
                milestoneAction: milestoneAction
            )
        )
    }

    /// Applies a validated update to the task in memory via the service layer.
    /// Calls `taskService.updateTask(..., save: false)` once with every
    /// non-milestone field and `milestoneService.setMilestone(..., save: false)`
    /// at most once. Throws service-layer errors only
    /// (`TaskService.Error` / `MilestoneService.Error`); validation errors are
    /// returned by `validate` and never thrown from `apply`. The caller is
    /// responsible for invoking `taskService.rollback()` to undo any partial
    /// in-memory mutation if a throw lands between the two service calls.
    static func apply(
        _ update: ValidatedTaskUpdate,
        to task: TransitTask,
        taskService: TaskService,
        milestoneService: MilestoneService
    ) throws {
        // Walk order: name → description → type → metadata → milestone.
        // Only call updateTask if at least one of its fields changes — otherwise
        // we'd issue a no-op service call that still adds nothing observable but
        // is wasted work.
        let (descArg, clearDesc): (String?, Bool) = switch update.description {
        case .noChange: (nil, false)
        case .set(let value): (value, false)
        case .clear: (nil, true)
        }

        let metadataArg: [String: String]? = switch update.metadata {
        case .noChange: nil
        case .set(let dict): dict
        case .clear: [:]
        }

        let hasFieldChange = update.name != nil
            || update.description.isChange
            || update.type != nil
            || update.metadata.isChange

        if hasFieldChange {
            try taskService.updateTask(
                task,
                name: update.name,
                description: descArg,
                clearDescription: clearDesc,
                type: update.type,
                metadata: metadataArg,
                save: false
            )
        }

        switch update.milestoneAction {
        case .none:
            break
        case .assign(let milestone):
            try milestoneService.setMilestone(milestone, on: task, save: false)
        case .clear:
            try milestoneService.setMilestone(nil, on: task, save: false)
        }
    }

    /// Strict metadata coercion. `JSONSerialization` delivers JSON numbers and
    /// booleans as `NSNumber`, which would silently pass a permissive
    /// `[String: String]` cast in some paths; this helper explicitly rejects
    /// any non-string value. Co-located with the validator because its only
    /// caller is `validate` and its error type is feature-specific.
    static func strictStringMetadata(
        from value: Any?
    ) -> Result<FieldChange<[String: String]>, TaskUpdateValidationError> {
        guard let value else {
            return .success(.noChange)
        }

        // Native [String: String] from Swift callers and tests.
        if let strict = value as? [String: String] {
            return .success(strict.isEmpty ? .clear : .set(strict))
        }

        // JSONSerialization-style [String: Any]: strict-cast each value.
        if let dict = value as? [String: Any] {
            if dict.isEmpty {
                return .success(.clear)
            }
            var coerced: [String: String] = [:]
            coerced.reserveCapacity(dict.count)
            for (key, raw) in dict {
                guard let stringValue = raw as? String else {
                    return .failure(.invalidInput("metadata values must be strings"))
                }
                coerced[key] = stringValue
            }
            return .success(.set(coerced))
        }

        return .failure(.invalidInput("metadata must be an object with string values"))
    }

    // MARK: - Field Validators

    private static func validateName(
        _ args: [String: Any]
    ) -> Result<String?, TaskUpdateValidationError> {
        guard let raw = args["name"] else { return .success(nil) }
        guard let str = raw as? String else {
            return .failure(.invalidInput("name must be a string"))
        }
        let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure(.invalidInput("Task name cannot be empty"))
        }
        return .success(trimmed)
    }

    private static func validateDescription(
        _ args: [String: Any]
    ) -> Result<FieldChange<String>, TaskUpdateValidationError> {
        guard let raw = args["description"] else { return .success(.noChange) }
        guard let str = raw as? String else {
            return .failure(.invalidInput("description must be a string"))
        }
        let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
        return .success(trimmed.isEmpty ? .clear : .set(trimmed))
    }

    private static func validateType(
        _ args: [String: Any]
    ) -> Result<TaskType?, TaskUpdateValidationError> {
        guard let raw = args["type"] else { return .success(nil) }
        guard let str = raw as? String else {
            return .failure(.invalidInput("type must be a string"))
        }
        guard let type = TaskType(rawValue: str) else {
            let valid = TaskType.allCases.map(\.rawValue).joined(separator: ", ")
            return .failure(.invalidInput("Invalid type: \(str). Must be one of: \(valid)"))
        }
        return .success(type)
    }

    /// Mirrors the precedence in the existing MCP handler and
    /// `UpdateTaskIntent.applyMilestoneChange`: clearMilestone → milestoneDisplayId → milestone (name).
    /// `clearMilestone: true` is emitted as `.clear` unconditionally — even when
    /// the task is already unassigned — to preserve existing handler behavior
    /// (the save is a no-op for the milestone field but the request is still a
    /// "change" for hasChanges purposes; see Phase 3 test
    /// `clearMilestone_onAlreadyUnassigned_savesAnyway`).
    private static func validateMilestone(
        _ args: [String: Any],
        task: TransitTask,
        milestoneService: MilestoneService
    ) -> Result<MilestoneAction?, TaskUpdateValidationError> {
        // clearMilestone (boolean) takes precedence
        if args.keys.contains("clearMilestone") {
            guard let clear = IntentHelpers.parseBoolValue(args["clearMilestone"]) else {
                return .failure(.invalidInput("clearMilestone must be a boolean"))
            }
            if clear {
                return .success(.clear)
            }
            // clearMilestone: false → fall through, but only resolve other milestone
            // fields if they are present (matches existing behavior).
        }

        if args["milestoneDisplayId"] != nil {
            return resolveMilestoneByDisplayId(args, task: task, milestoneService: milestoneService)
        }

        if args["milestone"] != nil {
            return resolveMilestoneByName(args, task: task, milestoneService: milestoneService)
        }

        return .success(nil)
    }

    private static func resolveMilestoneByDisplayId(
        _ args: [String: Any],
        task: TransitTask,
        milestoneService: MilestoneService
    ) -> Result<MilestoneAction?, TaskUpdateValidationError> {
        guard let displayId = IntentHelpers.parseIntValue(args["milestoneDisplayId"]) else {
            return .failure(.invalidInput("milestoneDisplayId must be an integer"))
        }
        do {
            let milestone = try milestoneService.findByDisplayID(displayId)
            return projectMatched(milestone: milestone, task: task)
        } catch MilestoneService.Error.duplicateDisplayID {
            return .failure(.duplicateMilestoneDisplayID(
                message: "Duplicate milestone identifier detected for displayId \(displayId)"
            ))
        } catch {
            return .failure(.milestoneNotFound(
                message: "No milestone with displayId \(displayId)"
            ))
        }
    }

    private static func resolveMilestoneByName(
        _ args: [String: Any],
        task: TransitTask,
        milestoneService: MilestoneService
    ) -> Result<MilestoneAction?, TaskUpdateValidationError> {
        guard let name = args["milestone"] as? String else {
            return .failure(.invalidInput("milestone must be a string"))
        }
        guard let project = task.project else {
            return .failure(.projectRequiredForMilestone)
        }
        guard let milestone = milestoneService.findByName(name, in: project) else {
            return .failure(.milestoneNotFound(
                message: "No milestone named '\(name)' in project '\(project.name)'"
            ))
        }
        return projectMatched(milestone: milestone, task: task)
    }

    /// Validates that a resolved milestone's project matches the task's project.
    /// Throws-via-Result so the caller can surface either `.milestoneProjectMismatch`
    /// or `.projectRequiredForMilestone` depending on which precondition fails.
    private static func projectMatched(
        milestone: Milestone,
        task: TransitTask
    ) -> Result<MilestoneAction?, TaskUpdateValidationError> {
        guard let taskProject = task.project else {
            return .failure(.projectRequiredForMilestone)
        }
        guard milestone.project?.id == taskProject.id else {
            return .failure(.milestoneProjectMismatch)
        }
        return .success(.assign(milestone))
    }
}

// MARK: - Value Types

/// A pure data carrier for a fully-validated update. Field representation
/// makes invalid states unrepresentable:
/// - Non-clearable fields (`name`, `type`) use `Optional<T>` — `nil` = no change.
/// - Clearable fields (`description`, `metadata`) use `FieldChange<T>` to
///   distinguish "set" from "clear" cleanly.
/// - Milestone uses its own enum because "assign" carries a `Milestone`
///   instance that resolution has already located.
struct ValidatedTaskUpdate {
    let name: String?
    let description: FieldChange<String>
    let type: TaskType?
    let metadata: FieldChange<[String: String]>
    let milestoneAction: MilestoneAction?

    var hasChanges: Bool {
        name != nil
            || description.isChange
            || type != nil
            || metadata.isChange
            || milestoneAction != nil
    }
}

/// Represents a single field's update intent. `noChange` means the field was
/// omitted from the request; `set(T)` carries a validated value; `clear`
/// signals an explicit clear (e.g. `description: ""` or `metadata: {}`).
enum FieldChange<T> {
    case noChange
    case set(T)
    case clear

    var isChange: Bool {
        if case .noChange = self { false } else { true }
    }
}

/// Milestone update intent. `assign(Milestone)` carries the already-resolved
/// milestone so `apply` does not need to re-look it up.
///
/// `clear` is emitted unconditionally whenever `clearMilestone: true` is in the
/// request args, even when the task already has no milestone assigned. This
/// preserves the existing MCP handler's behavior (the save is a no-op for the
/// milestone field but still counts as a "change" for `hasChanges` purposes).
enum MilestoneAction {
    case assign(Milestone)
    case clear
}

// MARK: - Errors

/// Structured validation/resolution errors emitted by `TaskUpdateValidator`.
/// Each surface (MCP / App Intent) renders these into its own error envelope
/// via `mcpMessage` or `intentError`. Error-message text is allowed to differ
/// across surfaces (AC 5.2 carve-out).
enum TaskUpdateValidationError: Error {
    case invalidInput(String)
    case milestoneNotFound(message: String)
    case duplicateMilestoneDisplayID(message: String)
    case milestoneProjectMismatch
    case projectRequiredForMilestone

    /// Message string used by the MCP surface's `errorResult(...)`. Mirrors
    /// the literals previously hard-coded in `MCPToolHandler.handleUpdateTask`
    /// for milestone errors so existing tests and callers see no change.
    var mcpMessage: String {
        switch self {
        case .invalidInput(let message),
             .milestoneNotFound(let message),
             .duplicateMilestoneDisplayID(let message):
            return message
        case .milestoneProjectMismatch:
            return "Milestone and task must belong to the same project"
        case .projectRequiredForMilestone:
            return "Task must belong to a project before assigning a milestone"
        }
    }

    /// Projection to `IntentError` for the App Intent surface. Mirrors the
    /// mapping previously in `UpdateTaskIntent.applyMilestoneChange` and
    /// `IntentHelpers.mapMilestoneError`.
    var intentError: IntentError {
        switch self {
        case .invalidInput(let hint):
            return .invalidInput(hint: hint)
        case .milestoneNotFound(let message):
            return .milestoneNotFound(hint: message)
        case .duplicateMilestoneDisplayID(let message):
            return .internalError(hint: message)
        case .milestoneProjectMismatch:
            return .milestoneProjectMismatch(
                hint: "Milestone and task must belong to the same project"
            )
        case .projectRequiredForMilestone:
            return .invalidInput(
                hint: "Task must belong to a project before assigning a milestone"
            )
        }
    }
}
