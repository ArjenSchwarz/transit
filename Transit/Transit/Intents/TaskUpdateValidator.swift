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
        // Stub: real implementation lands in T-650 phase 2 (task 2r6h8qm).
        _ = args
        _ = task
        _ = milestoneService
        return .failure(.invalidInput("not implemented"))
    }

    /// Applies a validated update to the task in memory via the service layer.
    /// Calls `taskService.updateTask(..., save: false)` once and
    /// `milestoneService.setMilestone(..., save: false)` at most once.
    /// Throws on service-layer failure; the caller is responsible for invoking
    /// `taskService.rollback()` to undo any partial in-memory mutation.
    static func apply(
        _ update: ValidatedTaskUpdate,
        to task: TransitTask,
        taskService: TaskService,
        milestoneService: MilestoneService
    ) throws {
        // Stub: real implementation lands in T-650 phase 2 (task 2r6h8qm).
        _ = update
        _ = task
        _ = taskService
        _ = milestoneService
        fatalError("not implemented")
    }

    /// Strict metadata coercion. `JSONSerialization` delivers JSON numbers and
    /// booleans as `NSNumber`, which would silently pass a permissive
    /// `[String: String]` cast in some paths; this helper explicitly rejects
    /// any non-string value. Co-located with the validator because its only
    /// caller is `validate` and its error type is feature-specific.
    static func strictStringMetadata(
        from value: Any?
    ) -> Result<FieldChange<[String: String]>, TaskUpdateValidationError> {
        // Stub: real implementation lands in T-650 phase 2 (task 2r6h8qm).
        _ = value
        return .failure(.invalidInput("not implemented"))
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
