# Design: Extend update_task to Support All Task Fields (T-650)

## Overview

Extend the MCP `update_task` tool and `UpdateTaskIntent` to update `name`, `description`, `type`, and `metadata` in addition to the existing milestone fields. Both surfaces share a single validator and applier so that validation rules and applied changes are guaranteed identical. The service layer already supports every field via `TaskService.updateTask`; this work is entirely in the handler/intent and the tool schema.

## Architecture

### Call flow (both surfaces)

```
   ┌── MCP handleUpdateTask ──┐         ┌── UpdateTaskIntent.execute ──┐
   │ parse JSON args           │         │ parse JSON input              │
   │ resolve task              │         │ resolve task                  │
   └──────────┬────────────────┘         └──────────────┬────────────────┘
              │                                         │
              ▼                                         ▼
   ┌─────────────────────────────────────────────────────────────────┐
   │ TaskUpdateValidator.validate(args, task, milestoneService)      │
   │  → Result<ValidatedTaskUpdate, TaskUpdateValidationError>       │
   │  ── walks: name → description → type → metadata → milestone     │
   │  ── purely functional; no model mutations                       │
   └──────────────────────────┬──────────────────────────────────────┘
                              │
              ┌───────────────┴──────────────┐
              │                              │
        update.hasChanges == false?   update.hasChanges == true?
              │                              │
              ▼                              ▼
        skip save                  TaskUpdateValidator.apply(update,
        return current task echo   task, taskService, milestoneService)
                                            │
                                            ▼
                                   try taskService.save()
                                   (which already wraps safeRollback)
                                            │
                                            ▼
                              IntentHelpers.taskUpdateResponseDict(task)
                              → JSON
```

Each surface maps `TaskUpdateValidationError` to its own error envelope:
- MCP: `errorResult(error.mcpMessage)` → `MCPToolResult(isError: true, ...)`
- App Intent: `error.intentError.json` → IntentError-encoded string

### Module placement

A new file `Transit/Transit/Intents/TaskUpdateValidator.swift` holds the shared validator, applier, value types, error enum, **and** the strict metadata helper. Co-locating `strictStringMetadata` with the validator avoids creating a dependency edge from generic `IntentHelpers.swift` to the feature-specific `TaskUpdateValidationError` enum — the helper has exactly one caller.

`IntentHelpers.swift` gains one small addition:
- `taskUpdateResponseDict(_:) -> [String: Any]` — builds the AC 9.1 response shape (no `comments`, no date fields, omits cleared fields). This is the *only* response builder used by `update_task` post-T-650; `UpdateTaskIntent.buildResponse` (Transit/Transit/Intents/UpdateTaskIntent.swift:103) is deleted as part of this change. Cannot reuse `taskToDict(detailed: true)` because it emits `description` as `task.taskDescription as Any` which encodes `nil` as `NSNull` (violates [9.1](#9.1)) and it also emits `lastStatusChangeDate`/`completionDate`.

### Integration points

| Site | Change |
|---|---|
| `MCPToolHandler.handleUpdateTask` (Transit/Transit/MCP/MCPToolHandler.swift:787) | Replace milestone-only logic with: validate → apply → save → response |
| `UpdateTaskIntent.execute` (Transit/Transit/Intents/UpdateTaskIntent.swift:50) | Same shape; surface-specific error translation |
| `UpdateTaskIntent.buildResponse` / `applyMilestoneChange` (Transit/Transit/Intents/UpdateTaskIntent.swift:77,103) | **Delete.** Replaced by `IntentHelpers.taskUpdateResponseDict` and the shared validator/applier. |
| `MCPToolDefinitions.updateTask` (Transit/Transit/MCP/MCPToolDefinitions.swift:231) | Add `name`, `description`, `type`, `metadata` to schema; update `updateTaskDescription` |
| `UpdateTaskIntent.Input` parameter description | Document new fields incl. empty-string-clears semantic |
| `TaskService` (Transit/Transit/Services/TaskService.swift) | Add `func rollback() { modelContext.safeRollback() }` for handler-level rollback when `apply()` throws (apply-failure rollback gap, see Error Handling section) |

The existing milestone path (`clearMilestone`, `milestone`, `milestoneDisplayId`) is preserved by folding it into `TaskUpdateValidator` rather than running it before/after; this is what makes [5.1](#5.1)/[7.2](#7.2) atomic.

## Components and Interfaces

### TaskUpdateValidator (new file)

```swift
// Transit/Transit/Intents/TaskUpdateValidator.swift

@MainActor
enum TaskUpdateValidator {
    static func validate(
        _ args: [String: Any],
        task: TransitTask,
        milestoneService: MilestoneService
    ) -> Result<ValidatedTaskUpdate, TaskUpdateValidationError>

    static func apply(
        _ update: ValidatedTaskUpdate,
        to task: TransitTask,
        taskService: TaskService,
        milestoneService: MilestoneService
    ) throws

    // Strict metadata coercion. Sole caller is `validate`; co-located to avoid
    // dropping a feature-specific error type into IntentHelpers.
    static func strictStringMetadata(
        from value: Any?
    ) -> Result<FieldChange<[String: String]>, TaskUpdateValidationError>
}

/// A pure data carrier for a fully-validated update. Field representation
/// makes invalid states unrepresentable:
/// - Non-clearable fields (`name`, `type`) use `Optional<T>` — nil = no change.
/// - Clearable fields (`description`, `metadata`) use `FieldChange<T>` to
///   distinguish "set" from "clear" cleanly.
/// - Milestone uses its own enum because "assign" carries a `Milestone`
///   instance that resolution has already located.
struct ValidatedTaskUpdate {
    let name: String?                       // trimmed, non-empty; nil = no change
    let description: FieldChange<String>    // .set(trimmed-non-empty), .clear, or .noChange
    let type: TaskType?                     // nil = no change
    let metadata: FieldChange<[String: String]>  // .set(non-empty), .clear (was {}), or .noChange
    let milestoneAction: MilestoneAction?   // nil = no change

    var hasChanges: Bool {
        name != nil || description.isChange || type != nil
            || metadata.isChange || milestoneAction != nil
    }
}

enum FieldChange<T> {
    case noChange
    case set(T)
    case clear

    var isChange: Bool { if case .noChange = self { false } else { true } }
}

enum MilestoneAction {
    case assign(Milestone)
    case clear
}

enum TaskUpdateValidationError {
    case invalidInput(String)              // type/value validation: "name must be a string", "Invalid type: x. ..."
    case milestoneNotFound(message: String)
    case duplicateMilestoneDisplayID(message: String)  // mirrors existing MilestoneService.Error.duplicateDisplayID handling
    case milestoneProjectMismatch
    case projectRequiredForMilestone

    var mcpMessage: String { /* extract a single string for errorResult */ }
    var intentError: IntentError {
        switch self {
        case .invalidInput(let hint): .invalidInput(hint: hint)
        case .milestoneNotFound(let m): .milestoneNotFound(hint: m)
        case .duplicateMilestoneDisplayID(let m): .internalError(hint: m)
        case .milestoneProjectMismatch: .milestoneProjectMismatch(hint: "Milestone and task must belong to the same project")
        case .projectRequiredForMilestone: .invalidInput(hint: "Task must belong to a project before assigning a milestone")
        }
    }
}
```

The `FieldChange<T>` enum makes `description` and `metadata` self-describing — the applier pattern-matches on the case rather than juggling an optional + boolean flag. Translation to `TaskService.updateTask`'s `(description: String?, clearDescription: Bool)` parameter pair happens inside `apply`:

```swift
// apply translates FieldChange to service parameters
let (descArg, clearDesc): (String?, Bool) = switch update.description {
case .noChange: (nil, false)
case .set(let s): (s, false)
case .clear:     (nil, true)
}
```

**Behavioral contract for `validate`:**
- Pure: never mutates `task` or any model.
- Stops at the first failure encountered while walking fields in this order: `name`, `description`, `type`, `metadata`, milestone fields. The order is deterministic in the implementation, but not part of the public contract per [5.2](#5.2) — tests for "any one of multiple invalid fields produces an error" SHALL NOT depend on which one surfaces.
- Milestone resolution requires the milestone service to call `findByDisplayID` / `findByName`, which read the model context. Reads are allowed; writes are not. Atomicity between read and the subsequent `apply` is provided by `@MainActor` isolation — no other actor can mutate the context between the validator returning and the applier running.

**Behavioral contract for `apply`:**
- Calls `taskService.updateTask(task, ..., save: false)` once with all non-milestone fields if any are present.
- Calls `milestoneService.setMilestone(_, on:, save: false)` once if milestone changed. Note: `clearMilestone: true` against an already-unassigned task counts as a "change" for the purposes of `hasChanges` and will trigger a (no-op) save. This matches the existing pre-T-650 behavior and is left as-is — the redundant save is harmless and the alternative (per-field equality checks) is more code with no observable benefit.
- Performs no `save()`; that is the caller's responsibility so a single transaction covers every mutation ([5.1](#5.1)).

### Strict metadata helper (co-located in TaskUpdateValidator.swift)

`TaskUpdateValidator.strictStringMetadata(from:) -> Result<FieldChange<[String: String]>, TaskUpdateValidationError>`

Behavioral contract:
- `value == nil` → `.success(.noChange)` (field omitted)
- `value` is `[String: String]` empty, or `[String: Any]` empty → `.success(.clear)` (caller passed `{}`)
- `value` is `[String: String]` non-empty → `.success(.set(value))`
- `value` is `[String: Any]` with all-string values → `.success(.set(coerced))`. "String values" means Swift `String`; JSON numbers and booleans deserialised by `JSONSerialization` as `NSNumber` fail the `as? String` cast and are rejected by the next rule.
- `value` is `[String: Any]` with any non-string entry → `.failure(.invalidInput("metadata values must be strings"))`
- `value` is any other JSON type → `.failure(.invalidInput("metadata must be an object with string values"))`

### Response builder (IntentHelpers extension)

```swift
extension IntentHelpers {
    @MainActor
    static func taskUpdateResponseDict(_ task: TransitTask) -> [String: Any]
}
```

Returns the AC 9.1 shape exactly:
- Always present: `taskId`, `name`, `type`, `status`
- Present when non-nil: `displayId`, `projectId`, `projectName`
- Present when non-nil **and non-empty**: `description`
- Present when non-empty: `metadata`
- Present when assigned: `milestone` (via existing `milestoneInfoDict`)
- Never present: `comments`, `creationDate`, `lastStatusChangeDate`, `completionDate`

The output is purely a function of the task's current model state, not of which fields the request touched ([9.1](#9.1)).

### MCPToolHandler.handleUpdateTask (rewritten)

```swift
private func handleUpdateTask(_ args: [String: Any]) -> MCPToolResult {
    // Identifier resolution (preserve existing T-634 / T-808 behavior)
    if args["displayId"] != nil, IntentHelpers.parseIntValue(args["displayId"]) == nil {
        return errorResult("displayId must be an integer")
    }
    let task: TransitTask
    do { task = try taskService.resolveTask(from: args) }
    catch TaskService.Error.invalidIdentifier(let field) {
        return errorResult(IntentHelpers.invalidIdentifierHint(for: field))
    } catch {
        return errorResult("Provide either displayId (integer) or taskId (UUID string)")
    }

    // Validate
    let update: ValidatedTaskUpdate
    switch TaskUpdateValidator.validate(args, task: task, milestoneService: milestoneService) {
    case .success(let v): update = v
    case .failure(let e): return errorResult(e.mcpMessage)
    }

    // No-op echo
    guard update.hasChanges else {
        return textResult(IntentHelpers.encodeJSON(IntentHelpers.taskUpdateResponseDict(task)))
    }

    // Apply + save. Two distinct catch paths to satisfy AC 5.2 (apply mid-throw
    // must roll back partial mutations) and AC 5.3 (save failure path).
    do {
        try TaskUpdateValidator.apply(update, to: task, taskService: taskService, milestoneService: milestoneService)
    } catch {
        taskService.rollback()  // undo any partial in-memory mutations from updateTask before setMilestone threw
        return errorResult("Update failed: \(error)")
    }
    do {
        try taskService.save()  // wraps safeRollback internally on save failure
    } catch {
        return errorResult("Update failed: \(error)")
    }

    return textResult(IntentHelpers.encodeJSON(IntentHelpers.taskUpdateResponseDict(task)))
}
```

### UpdateTaskIntent.execute (rewritten)

Mirror structure; differs only in:
- Returns a JSON string directly (not `MCPToolResult`).
- Maps `TaskUpdateValidationError → IntentError → .json` instead of `errorResult(...)`.
- Save and apply failures map to `IntentError.internalError(hint:)` so the App Intent JSON envelope carries the correct error code (matches `IntentError`'s existing INTERNAL_ERROR mapping, not raw error interpolation).
- Existing helpers (`IntentHelpers.parseJSON`, `IntentHelpers.resolveTask`) handle parse/resolve.

### MCPToolDefinitions.updateTask (extended schema)

```swift
static let updateTask = MCPToolDefinition(
    name: "update_task",
    description: "Update a task's mutable fields (name, description, type, metadata, milestone) "
              + "in a single atomic call. Identify task by displayId or taskId.",
    inputSchema: .object(properties: [
        "displayId": .integer("Task display ID (e.g. 42 for T-42)"),
        "taskId": .string("Task UUID"),
        "name": .string("New task name (trimmed; must be non-empty after trim)"),
        "description": .string("New description. Pass \"\" or whitespace-only to clear."),
        "type": .string("New type. Exact lowercase: bug, feature, chore, research, documentation."),
        "metadata": .object("Replaces entire metadata dictionary. Pass {} to clear all. Values must be strings."),
        "milestone": .string("Milestone name (within task's project). Use clearMilestone to unassign."),
        "milestoneDisplayId": .integer("Milestone display ID (takes precedence over name)"),
        "clearMilestone": .boolean("Set true to remove milestone assignment")
    ], required: [])
)
```

The prose for `description` and `metadata` carries the discoverability requirement from [8.2](#8.2).

## Data Models

None. No SwiftData schema changes. `ValidatedTaskUpdate`, `MilestoneAction`, and `TaskUpdateValidationError` are transient value types in the validator file.

## Error Handling

| Failure source | MCP surface | App Intent surface |
|---|---|---|
| Identifier missing/invalid (existing) | `errorResult("Provide either displayId ...")` or field-specific hint | `IntentError.invalidInput(...)` |
| Non-string `name`/`description`/`type` | `errorResult("name must be a string")` etc. | `IntentError.invalidInput(hint:)` |
| Empty-after-trim `name` | `errorResult("Task name cannot be empty")` | `IntentError.invalidInput(hint:)` |
| Invalid `type` enum value | `errorResult("Invalid type: x. Must be one of: ...")` | same hint, wrapped in `INVALID_INPUT` |
| Non-object `metadata` | `errorResult("metadata must be an object with string values")` | same hint, INVALID_INPUT |
| Non-string `metadata` value | `errorResult("metadata values must be strings")` | same hint, INVALID_INPUT |
| Milestone not found | `errorResult("No milestone with displayId N")` | `IntentError.milestoneNotFound(hint:)` |
| Milestone duplicate displayID | `errorResult("Duplicate milestone identifier detected for displayId N")` | `IntentError.internalError(hint:)` (mirrors existing `assignMilestone` behavior) |
| Milestone/project mismatch | `errorResult("Milestone and task must belong to the same project")` | `IntentError.milestoneProjectMismatch(hint:)` |
| Apply mid-throw | `errorResult("Update failed: ...")` + explicit `taskService.rollback()` | `IntentError.internalError(hint:)` + explicit `taskService.rollback()` |
| Save failure | `errorResult("Update failed: ...")` (rollback inside `taskService.save()`) | `IntentError.internalError(hint:)` |

Error-message text is allowed to differ across surfaces ([5.2](#5.2) carve-out); the validator emits a structured error, each surface chooses how to render it.

## Testing Strategy

### Unit tests

Two test files extended; both use Swift Testing + `MCPTestHelpers` / direct `UpdateTaskIntent.execute` calls with in-memory `TestModelContainer`.

**Coverage matrix per AC** (added test names suggested in parentheses):

| AC | MCP test | Intent test |
|---|---|---|
| [1.1](#1.1) name set | `updateName_setsTrimmedName` | parallel |
| [1.2](#1.2) name empty/whitespace rejected | `updateName_rejectsEmptyAndWhitespace` | parallel |
| [1.3](#1.3) name non-string rejected | `updateName_rejectsNonString` | parallel |
| [1.4](#1.4) name omission preserves | `omittingNamePreservesIt` (combined with other omission ACs below) | parallel |
| [2.1](#2.1) description set + trim | `updateDescription_setsTrimmed` | parallel |
| [2.2](#2.2) description empty / whitespace clears | `updateDescription_emptyAndWhitespaceClears` | parallel |
| [2.3](#2.3) description non-string rejected | `updateDescription_rejectsNonString` | parallel |
| [2.4](#2.4) description omission preserves | `omittingDescriptionPreservesIt` | parallel |
| [3.4](#3.4) type omission preserves | `omittingTypePreservesIt` | parallel |
| [4.5](#4.5) metadata omission preserves | `omittingMetadataPreservesIt` | parallel |
| [3.1](#3.1) type set | `updateType_setsValidType` | parallel |
| [3.2](#3.2) invalid type rejected | `updateType_rejectsInvalidValue` | parallel |
| [3.3](#3.3) type non-string rejected | `updateType_rejectsNonString` | parallel |
| [4.1](#4.1) metadata replace | `updateMetadata_replacesEntireDict` | parallel |
| [4.2](#4.2) metadata `{}` clears | `updateMetadata_emptyDictClears` | parallel |
| [4.3](#4.3) metadata non-object rejected | `updateMetadata_rejectsNonObject` | parallel |
| [4.4](#4.4) metadata non-string value rejected | `updateMetadata_rejectsNonStringValues` | parallel |
| [5.1](#5.1) atomic multi-field update | `updateMultipleFields_allAppliedAtomically` | parallel |
| [5.2](#5.2) validation failure leaves all fields unchanged | `updateMixed_invalidFieldRollsBackAll` | parallel |
| [5.3](#5.3) save failure path | **No handler-level test.** `TaskService` is `final` with no protocol seam; introducing one is out of scope for T-650 (would affect every handler). The catch branch is one line. AC 5.3 coverage is provided by the existing `TaskService.save()` service-layer test that asserts `safeRollback()` runs on failure. This carve-out is documented in the test file. |
| [5.2](#5.2) apply-throw rollback | `applyThrows_taskUntouched` — stubs `milestoneService.setMilestone` to throw after `taskService.updateTask` mutates, asserts task fields are reverted. Achievable via `MilestoneService` test seam if available; otherwise covered by inspection of the handler's catch block plus the existing `setMilestone` error-path service tests. |
| [6.1](#6.1)/[6.2](#6.2) no-op echo | `identifierOnly_doesNotSave_returnsCurrent` + `metadataEmpty_isMutation_triggersSave` | parallel |
| [6.3](#6.3) unknown fields ignored | `unknownFieldsIgnored_doNotBlockNoOp` | parallel |
| [7.1](#7.1) milestone backward compat | existing milestone tests must continue to pass unchanged | parallel |
| [7.2](#7.2) milestone + field atomic | `updateMilestoneAndName_singleSave` | parallel |
| [7.x](#7.1) `clearMilestone` on already-unassigned task | `clearMilestone_onAlreadyUnassigned_savesAnyway` — documents the redundant-save behavior so a future refactor doesn't silently optimise it away | parallel |
| [8.2](#8.2) tool schema includes new fields and clearing prose | `toolsListIncludesNewUpdateTaskFields` — asserts each of `name`/`description`/`type`/`metadata` is present and that `description`'s prose contains the substring `"clear"` and `metadata`'s prose contains `"clear"`/`"{}"` (exact-substring match, not just non-empty) | parallel test reads `UpdateTaskIntent.$input.description` substring on the same wording |
| [9.1](#9.1) response shape: cleared fields omitted | `responseOmitsClearedDescriptionAndMetadata` + `responseExcludesCommentsAndDateFields` | parallel |

### Cross-surface parity test

One additional test asserts that for the same valid `args` (success case only), MCP and Intent return JSON with equivalent data payloads — parses both, asserts dict equality on the full key set. This enforces [8.1](#8.1) at the contract level without requiring byte-equal serialisation. Error-response parity is explicitly NOT asserted; per [5.2](#5.2) the two surfaces may surface different error messages for the same invalid input. Covering both in one test would mask omission-rule divergence that this contract test exists to catch.

### Property-based testing

Not applicable. The contract has no algebraic invariants worth generating inputs against — every behavior is a small set of input shape × field combinations, and example-based coverage is exhaustive.

### Schema test

Assert that `MCPToolDefinitions.updateTask.inputSchema` lists all new properties (`name`, `description`, `type`, `metadata`) with non-empty `description` strings ([8.2](#8.2)).
