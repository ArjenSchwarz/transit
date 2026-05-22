---
references:
    - specs/update-task-all-fields/requirements.md
    - specs/update-task-all-fields/design.md
    - specs/update-task-all-fields/decision_log.md
---
# Tasks: Extend update_task to Support All Task Fields (T-650)

## Foundation

- [x] 1. Add rollback() method to TaskService <!-- id:2r6h8qp -->
  - Single public method `func rollback() { modelContext.safeRollback() }` so handlers can revert in-memory mutations when apply() throws mid-way. Wiring-only task; no test required (the underlying safeRollback already has service-layer tests).
  - Requirements: [5.2](requirements.md#5.2), [5.3](requirements.md#5.3)
  - References: Transit/Transit/Services/TaskService.swift, Transit/Transit/Extensions/ModelContext+SafeRollback.swift

- [x] 2. Create TaskUpdateValidator.swift with value types and function stubs <!-- id:2r6h8qk -->
  - New file: Transit/Transit/Intents/TaskUpdateValidator.swift
  - Declare value types: FieldChange<T> (case noChange/set(T)/clear with isChange computed property), MilestoneAction (case assign(Milestone)/clear), ValidatedTaskUpdate struct (name: String?, description: FieldChange<String>, type: TaskType?, metadata: FieldChange<[String:String]>, milestoneAction: MilestoneAction?, hasChanges: Bool), TaskUpdateValidationError enum with cases .invalidInput(String), .milestoneNotFound(message:), .duplicateMilestoneDisplayID(message:), .milestoneProjectMismatch, .projectRequiredForMilestone
  - Add computed properties mcpMessage: String and intentError: IntentError on TaskUpdateValidationError (duplicateMilestoneDisplayID maps to .internalError, milestoneProjectMismatch to .milestoneProjectMismatch, etc.)
  - Stub function signatures only (return fatalError or .failure(.invalidInput("not implemented"))) for validate, apply, strictStringMetadata so test files can import the symbols
  - Types-only / wiring task per design — exempt from TDD pairing rule
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.3](requirements.md#1.3), [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [2.3](requirements.md#2.3), [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3), [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [4.3](requirements.md#4.3), [4.4](requirements.md#4.4), [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [7.1](requirements.md#7.1), [7.2](requirements.md#7.2), [8.1](requirements.md#8.1)
  - References: specs/update-task-all-fields/design.md

## Shared validator and applier

- [x] 3. Write tests for TaskUpdateValidator (validate, apply, strictStringMetadata) <!-- id:2r6h8ql -->
  - New test file: Transit/TransitTests/TaskUpdateValidatorTests.swift (Swift Testing, @MainActor @Suite(.serialized))
  - validate: cover all field combinations — name (trim/empty/non-string), description (trim+set/empty-clears/whitespace-clears/non-string), type (valid lowercase/invalid/non-string), metadata (replace/{}/non-object/non-string values via NSNumber from JSONSerialization)
  - validate: milestone path delegates to existing patterns (milestone displayId/name/clearMilestone) and surfaces .milestoneNotFound, .duplicateMilestoneDisplayID, .milestoneProjectMismatch correctly
  - validate: returns Result with hasChanges flag — identifier-only args produce hasChanges == false even with unknown fields present
  - strictStringMetadata: explicitly test that JSONSerialization-decoded numbers (NSNumber) fail the cast and return .failure(.invalidInput("metadata values must be strings"))
  - apply: covers .set/.clear/.noChange translation for description and metadata, MilestoneAction.assign/.clear, atomicity (mutations applied in-memory, no save() called by apply itself)
  - apply: throws if milestoneService.setMilestone throws — test caller can call taskService.rollback() to undo
  - Blocked-by: 2r6h8qk (Create TaskUpdateValidator.swift with value types and function stubs)
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.3](requirements.md#1.3), [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [2.3](requirements.md#2.3), [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3), [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [4.3](requirements.md#4.3), [4.4](requirements.md#4.4), [5.1](requirements.md#5.1), [7.1](requirements.md#7.1), [7.2](requirements.md#7.2)
  - References: specs/update-task-all-fields/design.md, Transit/TransitTests/MCPTestHelpers.swift

- [x] 4. Implement TaskUpdateValidator.validate, apply, and strictStringMetadata <!-- id:2r6h8qm -->
  - Walk fields in order: name → description → type → metadata → milestone (deterministic order, not part of public contract per AC 5.2)
  - validate is pure: never mutates the task; milestone resolution uses milestoneService read-only lookups
  - apply translates FieldChange<String> for description into TaskService.updateTask (description: String?, clearDescription: Bool) parameter pair; for metadata translates FieldChange<[String:String]> into the service metadata: parameter (.clear becomes [:], .set(d) becomes d, .noChange omits)
  - Both service calls use save: false; apply throws (does not catch) so caller handles rollback
  - Make all tests from task 3 pass
  - Blocked-by: 2r6h8ql (Write tests for TaskUpdateValidator (validate, apply, strictStringMetadata))
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.3](requirements.md#1.3), [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [2.3](requirements.md#2.3), [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3), [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [4.3](requirements.md#4.3), [4.4](requirements.md#4.4), [5.1](requirements.md#5.1), [7.1](requirements.md#7.1), [7.2](requirements.md#7.2)
  - References: Transit/Transit/Intents/TaskUpdateValidator.swift, Transit/Transit/Services/TaskService.swift

## Response builder

- [x] 5. Write tests for IntentHelpers.taskUpdateResponseDict <!-- id:2r6h8qn -->
  - Append to or create a new test in Transit/TransitTests for the helper
  - Verify always-present keys: taskId, name, type, status
  - Verify present-when-non-nil: displayId, projectId, projectName, description, milestone
  - Verify present-when-non-empty: metadata
  - Verify a cleared description (taskDescription == nil) and empty metadata are OMITTED — not present as "", null, or {}
  - Verify excluded keys: comments, creationDate, lastStatusChangeDate, completionDate
  - Requirements: [9.1](requirements.md#9.1)
  - References: specs/update-task-all-fields/design.md, Transit/Transit/Intents/IntentHelpers.swift

- [x] 6. Implement IntentHelpers.taskUpdateResponseDict <!-- id:2r6h8qo -->
  - Add `@MainActor static func taskUpdateResponseDict(_ task: TransitTask) -> [String: Any]`
  - Build the dict per AC 9.1 — omit nil description (do NOT use `task.taskDescription as Any`), omit empty metadata
  - Use existing milestoneInfoDict for milestone summary
  - Make tests from task 5 pass
  - Blocked-by: 2r6h8qn (Write tests for IntentHelpers.taskUpdateResponseDict)
  - Requirements: [9.1](requirements.md#9.1)
  - References: Transit/Transit/Intents/IntentHelpers.swift

## MCP surface

- [x] 7. Extend MCPUpdateTaskTests.swift with new field-update tests <!-- id:2r6h8qq -->
  - Add tests per design matrix: updateName_setsTrimmedName, updateName_rejectsEmptyAndWhitespace, updateName_rejectsNonString, updateDescription_setsTrimmed, updateDescription_emptyAndWhitespaceClears, updateDescription_rejectsNonString, updateType_setsValidType, updateType_rejectsInvalidValue, updateType_rejectsNonString, updateMetadata_replacesEntireDict, updateMetadata_emptyDictClears, updateMetadata_rejectsNonObject, updateMetadata_rejectsNonStringValues
  - Omission preservation: omittingNamePreservesIt, omittingDescriptionPreservesIt, omittingTypePreservesIt, omittingMetadataPreservesIt
  - Atomicity: updateMultipleFields_allAppliedAtomically, updateMixed_invalidFieldRollsBackAll, applyThrows_taskUntouched
  - No-op + unknown fields: identifierOnly_doesNotSave_returnsCurrent, metadataEmpty_isMutation_triggersSave, unknownFieldsIgnored_doNotBlockNoOp
  - Milestone parity: updateMilestoneAndName_singleSave, clearMilestone_onAlreadyUnassigned_savesAnyway (documents redundant-save behavior)
  - Response shape: responseOmitsClearedDescriptionAndMetadata, responseExcludesCommentsAndDateFields
  - Schema test (AC 8.2): toolsListIncludesNewUpdateTaskFields — assert presence of name/description/type/metadata in MCPToolDefinitions.updateTask.inputSchema AND that description's prose contains 'clear' and metadata's prose contains 'clear' or '{}' (exact-substring match)
  - Existing milestone tests (setMilestoneByDisplayId, clearMilestone, etc.) MUST continue to pass — do not delete or modify them
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.3](requirements.md#1.3), [1.4](requirements.md#1.4), [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [2.3](requirements.md#2.3), [2.4](requirements.md#2.4), [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3), [3.4](requirements.md#3.4), [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [4.3](requirements.md#4.3), [4.4](requirements.md#4.4), [4.5](requirements.md#4.5), [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [6.1](requirements.md#6.1), [6.2](requirements.md#6.2), [6.3](requirements.md#6.3), [7.1](requirements.md#7.1), [7.2](requirements.md#7.2), [8.2](requirements.md#8.2), [9.1](requirements.md#9.1)
  - References: Transit/TransitTests/MCPUpdateTaskTests.swift, specs/update-task-all-fields/design.md

- [x] 8. Rewrite MCPToolHandler.handleUpdateTask and extend MCPToolDefinitions.updateTask schema <!-- id:2r6h8qr -->
  - Rewrite handleUpdateTask (currently at line 787) following design's code sketch — preserve identifier-resolution preamble (T-634/T-808), then call TaskUpdateValidator.validate, handle no-op echo, two-stage do/catch (apply with explicit taskService.rollback(), then save with implicit safeRollback)
  - Use IntentHelpers.taskUpdateResponseDict for the response
  - Extend MCPToolDefinitions.updateTask.inputSchema with name/description/type/metadata properties — prose for description must contain 'clear' (e.g., 'Pass "" or whitespace-only to clear.'), prose for metadata must contain 'clear' (e.g., 'Pass {} to clear all. Values must be strings.')
  - Update updateTaskDescription (the tool top-level description string) to mention all supported fields
  - Make all tests from task 7 pass
  - Blocked-by: 2r6h8qp (Add rollback() method to TaskService), 2r6h8qm (Implement TaskUpdateValidator.validate, apply, and strictStringMetadata), 2r6h8qo (Implement IntentHelpers.taskUpdateResponseDict), 2r6h8qq (Extend MCPUpdateTaskTests.swift with new field-update tests)
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.3](requirements.md#1.3), [1.4](requirements.md#1.4), [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [2.3](requirements.md#2.3), [2.4](requirements.md#2.4), [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3), [3.4](requirements.md#3.4), [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [4.3](requirements.md#4.3), [4.4](requirements.md#4.4), [4.5](requirements.md#4.5), [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [6.1](requirements.md#6.1), [6.2](requirements.md#6.2), [6.3](requirements.md#6.3), [7.1](requirements.md#7.1), [7.2](requirements.md#7.2), [8.2](requirements.md#8.2), [9.1](requirements.md#9.1)
  - References: Transit/Transit/MCP/MCPToolHandler.swift, Transit/Transit/MCP/MCPToolDefinitions.swift, specs/update-task-all-fields/design.md

## App Intent surface

- [x] 9. Extend UpdateTaskIntentTests.swift with parallel field-update tests <!-- id:2r6h8qs -->
  - Parallel coverage to task 7 — call UpdateTaskIntent.execute directly, parse the returned JSON string
  - Test that UpdateTaskIntent.Input parameter description contains 'clear' wording for description and metadata (AC 8.2 parity)
  - Existing milestone tests in this file MUST continue to pass — do not delete or modify them
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.3](requirements.md#1.3), [1.4](requirements.md#1.4), [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [2.3](requirements.md#2.3), [2.4](requirements.md#2.4), [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3), [3.4](requirements.md#3.4), [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [4.3](requirements.md#4.3), [4.4](requirements.md#4.4), [4.5](requirements.md#4.5), [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [6.1](requirements.md#6.1), [6.2](requirements.md#6.2), [6.3](requirements.md#6.3), [7.1](requirements.md#7.1), [7.2](requirements.md#7.2), [8.1](requirements.md#8.1), [8.2](requirements.md#8.2), [9.1](requirements.md#9.1)
  - References: Transit/TransitTests/UpdateTaskIntentTests.swift, specs/update-task-all-fields/design.md

- [x] 10. Rewrite UpdateTaskIntent.execute, delete buildResponse and applyMilestoneChange, extend Input parameter description <!-- id:2r6h8qt -->
  - Rewrite execute() to mirror the MCP handler: parse JSON, resolve task, validate, no-op echo, apply with explicit rollback on throw, save (TaskService.save wraps rollback), encode response via IntentHelpers.taskUpdateResponseDict
  - Map TaskUpdateValidationError to its intentError projection then to .json
  - Map apply/save failures to IntentError.internalError(hint:), not raw error interpolation
  - DELETE: private static func applyMilestoneChange (line 77) and private static func buildResponse (line 103) — they are subsumed by the validator/applier and taskUpdateResponseDict
  - Update the Input @Parameter description to list every supported field including name, description (with empty-string-clears note), type, metadata (with {} clears note)
  - Make all tests from task 9 pass
  - Blocked-by: 2r6h8qp (Add rollback() method to TaskService), 2r6h8qm (Implement TaskUpdateValidator.validate, apply, and strictStringMetadata), 2r6h8qo (Implement IntentHelpers.taskUpdateResponseDict), 2r6h8qs (Extend UpdateTaskIntentTests.swift with parallel field-update tests)
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.3](requirements.md#1.3), [1.4](requirements.md#1.4), [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [2.3](requirements.md#2.3), [2.4](requirements.md#2.4), [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3), [3.4](requirements.md#3.4), [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [4.3](requirements.md#4.3), [4.4](requirements.md#4.4), [4.5](requirements.md#4.5), [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [6.1](requirements.md#6.1), [6.2](requirements.md#6.2), [6.3](requirements.md#6.3), [7.1](requirements.md#7.1), [7.2](requirements.md#7.2), [8.1](requirements.md#8.1), [8.2](requirements.md#8.2), [9.1](requirements.md#9.1)
  - References: Transit/Transit/Intents/UpdateTaskIntent.swift

## Cross-surface parity

- [ ] 11. Write UpdateTaskAllFieldsParityTests.swift <!-- id:2r6h8qu -->
  - New file: Transit/TransitTests/UpdateTaskAllFieldsParityTests.swift
  - For a fixed set of valid update args (covering each new field individually and a combined multi-field case), call BOTH the MCP handler and UpdateTaskIntent.execute, parse the JSON responses, assert dict equality on the full key set
  - Success cases only — error message divergence is allowed per AC 5.2
  - Verifies AC 8.1 contract holds in practice; if it fails, fix whichever surface diverges
  - Blocked-by: 2r6h8qr (Rewrite MCPToolHandler.handleUpdateTask and extend MCPToolDefinitions.updateTask schema), 2r6h8qt (Rewrite UpdateTaskIntent.execute, delete buildResponse and applyMilestoneChange, extend Input parameter description)
  - Requirements: [8.1](requirements.md#8.1)
  - References: Transit/TransitTests/MCPUpdateTaskTests.swift, Transit/TransitTests/UpdateTaskIntentTests.swift

## Documentation

- [ ] 12. Update docs/agent-notes/mcp-server.md for extended update_task <!-- id:2r6h8qv -->
  - Update the Tools Exposed table entry for update_task to reflect that it now supports name/description/type/metadata in addition to milestone fields
  - Optionally add a one-line gotcha about the empty-string-clears semantic
  - Blocked-by: 2r6h8qr (Rewrite MCPToolHandler.handleUpdateTask and extend MCPToolDefinitions.updateTask schema), 2r6h8qt (Rewrite UpdateTaskIntent.execute, delete buildResponse and applyMilestoneChange, extend Input parameter description)
  - Requirements: [8.1](requirements.md#8.1), [8.2](requirements.md#8.2)
  - References: docs/agent-notes/mcp-server.md
