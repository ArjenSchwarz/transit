---
references:
    - specs/task-priority/requirements.md
    - specs/task-priority/design.md
    - specs/task-priority/decision_log.md
---
# Task Priority (T-1463)

## Foundation

- [x] 1. Write tests for TaskPriority enum <!-- id:3dib3xi -->
  - Raw values low/medium/high; allCases ordering
  - tintColor for all three (high .red, medium .orange, low .blue)
  - glyphSymbol returns nil ONLY for medium; arrow.up.circle.fill for high, arrow.down.circle.fill for low
  - accessibilityLabel strings: 'High priority' etc.
  - Stream: 1
  - Requirements: [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [2.4](requirements.md#2.4)
  - References: specs/task-priority/design.md

- [x] 2. Implement TaskPriority enum in Models/TaskPriority.swift <!-- id:3dib3xj -->
  - String, Codable, CaseIterable; import SwiftUI for Color
  - Mirror TaskType shape
  - Blocked-by: 3dib3xi (Write tests for TaskPriority enum)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [2.4](requirements.md#2.4)
  - References: specs/task-priority/design.md

- [x] 3. Write tests for TransitTask priority accessor <!-- id:3dib3xk -->
  - Default priorityRawValue is medium
  - Empty or unrecognized raw value reads as .medium via computed accessor
  - Setter writes rawValue; init param sets priorityRawValue
  - Blocked-by: 3dib3xj (Implement TaskPriority enum in Models/TaskPriority.swift)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.3](requirements.md#1.3), [1.5](requirements.md#1.5)
  - References: specs/task-priority/design.md

- [x] 4. Add priorityRawValue stored property, priority computed accessor, and init param to TransitTask <!-- id:3dib3xl -->
  - priorityRawValue: String = medium (CloudKit-safe default, same shape as statusRawValue/typeRawValue)
  - init gains priority: TaskPriority = .medium
  - No production reads of priorityRawValue outside accessor/init/setter
  - Blocked-by: 3dib3xk (Write tests for TransitTask priority accessor)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.3](requirements.md#1.3), [1.5](requirements.md#1.5)
  - References: specs/task-priority/design.md, specs/task-priority/decision_log.md

- [x] 5. Write tests for TaskService priority create/update <!-- id:3dib3xm -->
  - createTask defaults to medium and honors explicit value
  - updateTask sets priority
  - updateTask omitting priority leaves it unchanged (Decision 8)
  - Blocked-by: 3dib3xl (Add priorityRawValue stored property, priority computed accessor, and init param to TransitTask)
  - Stream: 1
  - Requirements: [1.2](requirements.md#1.2), [5.2](requirements.md#5.2)
  - References: specs/task-priority/design.md

- [x] 6. Add priority param to TaskService createTask (both overloads) and updateTask <!-- id:3dib3xn -->
  - createTask(..., priority: TaskPriority = .medium); thread into TransitTask init
  - updateTask(..., priority: TaskPriority? = nil) -> if let priority { task.priority = priority }
  - Blocked-by: 3dib3xm (Write tests for TaskService priority create/update)
  - Stream: 1
  - Requirements: [1.2](requirements.md#1.2), [5.2](requirements.md#5.2)
  - References: specs/task-priority/design.md

## Automation

- [x] 7. Add INVALID_PRIORITY error code to IntentError enum and MCP error-code set <!-- id:3dib3xo -->
  - Parallel to INVALID_TYPE/INVALID_STATUS (Decision 9)
  - Wiring task; consumed by validator, MCP handler, and intents
  - Blocked-by: 3dib3xj (Implement TaskPriority enum in Models/TaskPriority.swift)
  - Stream: 1
  - Requirements: [5.5](requirements.md#5.5), [6.4](requirements.md#6.4)
  - References: specs/task-priority/decision_log.md

- [x] 8. Write tests for TaskUpdateValidator priority validation <!-- id:3dib3xp -->
  - Absent priority -> no change (.success(nil))
  - Invalid raw -> INVALID_PRIORITY
  - Valid -> applied (proves hasFieldChange term added so it cannot validate-but-not-apply)
  - Blocked-by: 3dib3xn (Add priority param to TaskService createTask (both overloads) and updateTask), 3dib3xo (Add INVALID_PRIORITY error code to IntentError enum and MCP error-code set)
  - Stream: 1
  - Requirements: [5.2](requirements.md#5.2), [6.2](requirements.md#6.2), [6.4](requirements.md#6.4)
  - References: specs/task-priority/design.md

- [x] 9. Implement validatePriority in TaskUpdateValidator <!-- id:3dib3xq -->
  - Mirror validateType exactly: Optional<TaskPriority>, NOT FieldChange (non-clearable)
  - Add ValidatedTaskUpdate.priority, hasChanges term, apply's hasFieldChange term (L103), pass to updateTask(priority:)
  - Covers BOTH MCP update_task and update intent
  - Blocked-by: 3dib3xp (Write tests for TaskUpdateValidator priority validation)
  - Stream: 1
  - Requirements: [5.2](requirements.md#5.2), [6.2](requirements.md#6.2), [6.4](requirements.md#6.4)
  - References: specs/task-priority/design.md, specs/task-priority/decision_log.md

- [x] 10. Write tests for MCP create_task and query_tasks priority <!-- id:3dib3xr -->
  - create with/without priority (response echoes resolved value); invalid priority -> INVALID_PRIORITY and NO task created
  - query_tasks returns priority; filters by single value and by array (multi-value)
  - Invalid query filter value rejected
  - Blocked-by: 3dib3xn (Add priority param to TaskService createTask (both overloads) and updateTask), 3dib3xo (Add INVALID_PRIORITY error code to IntentError enum and MCP error-code set)
  - Stream: 1
  - Requirements: [5.1](requirements.md#5.1), [5.3](requirements.md#5.3), [5.4](requirements.md#5.4), [5.5](requirements.md#5.5)
  - References: specs/task-priority/design.md

- [x] 11. Implement MCP priority support <!-- id:3dib3xs -->
  - MCPToolDefinitions: priority .stringEnum on create_task/update_task; priority .array on query_tasks (mirror status)
  - handleCreateTask: parse optional default medium, validate, apply; create response via taskToDict echoes priority
  - handleQueryTasks: validateEnumFilter allowArray:true; MCPQueryFilters gains priorities:[String]? + predicate comparing task.priority.rawValue (computed, NOT priorityRawValue)
  - IntentHelpers.taskToDict + taskUpdateResponseDict + milestoneToDict task sub-dict serialize task.priority.rawValue
  - Blocked-by: 3dib3xq (Implement validatePriority in TaskUpdateValidator), 3dib3xr (Write tests for MCP create_task and query_tasks priority)
  - Stream: 1
  - Requirements: [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [5.4](requirements.md#5.4), [5.5](requirements.md#5.5), [1.4](requirements.md#1.4)
  - References: specs/task-priority/design.md

- [x] 12. Write tests for JSON App Intents priority <!-- id:3dib3xt -->
  - Create: default medium / explicit / invalid -> INVALID_PRIORITY
  - Update: set and omit-unchanged; extend UpdateTaskAllFieldsParityTests for MCP/intent lockstep
  - Query: scalar single-value filter; invalid rejected
  - taskUpdateResponseDict carries priority
  - Blocked-by: 3dib3xq (Implement validatePriority in TaskUpdateValidator), 3dib3xs (Implement MCP priority support)
  - Stream: 1
  - Requirements: [6.1](requirements.md#6.1), [6.2](requirements.md#6.2), [6.3](requirements.md#6.3), [6.4](requirements.md#6.4)
  - References: specs/task-priority/design.md

- [x] 13. Implement JSON App Intents priority support <!-- id:3dib3xu -->
  - CreateTaskIntent: add to inputParameterDescription AND @Parameter literal (lockstep, T-1170); optional-with-default validation (absent->medium, invalid->INVALID_PRIORITY), pass to createTask
  - UpdateTaskIntent: document in both literals; logic via TaskUpdateValidator
  - QueryTasksIntent: scalar priority:String? on QueryFilters, validateEnumFilters clause, applyFilters compares task.priority.rawValue (computed), @Parameter docs
  - Blocked-by: 3dib3xt (Write tests for JSON App Intents priority)
  - Stream: 1
  - Requirements: [6.1](requirements.md#6.1), [6.2](requirements.md#6.2), [6.3](requirements.md#6.3), [6.4](requirements.md#6.4)
  - References: specs/task-priority/design.md, specs/task-priority/decision_log.md

## UI

- [x] 14. Write tests for dashboard priority filter predicate <!-- id:3dib3xv -->
  - DashboardLogic.buildFilteredColumns / matchesFilters: single and multi priority selection
  - Empty selection = all priorities pass
  - Intersection with project and type filters
  - Predicate uses task.priority (computed)
  - Blocked-by: 3dib3xl (Add priorityRawValue stored property, priority computed accessor, and init param to TransitTask)
  - Stream: 2
  - Requirements: [3.2](requirements.md#3.2), [3.3](requirements.md#3.3), [3.4](requirements.md#3.4)
  - References: specs/task-priority/design.md

- [x] 15. Implement PriorityFilterMenu and wire into DashboardView <!-- id:3dib3xw -->
  - New Views/Dashboard/PriorityFilterMenu.swift mirroring TypeFilterMenu; iterate ordered [high,medium,low] with Circle().fill(tintColor)+checkmark; ids dashboard.filter.priorities and filter.priority.<raw>
  - DashboardView: @State selectedPriorities; toolbar next to TypeFilterMenu; include in hasAnyFilter/hasOtherFilters; clear-all; thread into buildFilteredColumns/matchesFilters predicate
  - Ephemeral @State resets on launch
  - Blocked-by: 3dib3xv (Write tests for dashboard priority filter predicate)
  - Stream: 2
  - Requirements: [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3), [3.4](requirements.md#3.4), [3.5](requirements.md#3.5), [3.6](requirements.md#3.6), [3.7](requirements.md#3.7)
  - References: specs/task-priority/design.md

- [x] 16. Implement PriorityIndicator and add to TaskCardView <!-- id:3dib3xx -->
  - New Views/Shared/PriorityIndicator.swift: Image(systemName: glyphSymbol) for high/low, nothing for medium; .font(.caption), tintColor, accessibilityLabel, id dashboard.taskCard.priority
  - Bare symbol, NOT a TypeBadge text capsule; slot into TaskCardView badges HStack
  - Medium has no card glyph (by design; not VoiceOver-discoverable from card)
  - Blocked-by: 3dib3xl (Add priorityRawValue stored property, priority computed accessor, and init param to TransitTask)
  - Stream: 2
  - Requirements: [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [2.3](requirements.md#2.3), [2.4](requirements.md#2.4)
  - References: specs/task-priority/design.md

- [x] 17. Add priority picker to AddTaskSheet <!-- id:3dib3xy -->
  - @State selectedPriority = .medium; Picker over ordered cases on iOS and macOS mirroring the Type picker
  - Add to AddTaskFormResetLogic.Defaults; thread through TaskDraft.priority into createTask
  - Blocked-by: 3dib3xn (Add priority param to TaskService createTask (both overloads) and updateTask)
  - Stream: 2
  - Requirements: [4.1](requirements.md#4.1)
  - References: specs/task-priority/design.md

- [x] 18. Add priority picker to TaskEditView <!-- id:3dib3xz -->
  - @State selectedPriority; load = task.priority; Picker iOS+macOS; save passes priority to updateTask(save:false) before the atomic save
  - Blocked-by: 3dib3xn (Add priority param to TaskService createTask (both overloads) and updateTask)
  - Stream: 2
  - Requirements: [4.2](requirements.md#4.2), [4.3](requirements.md#4.3)
  - References: specs/task-priority/design.md

- [x] 19. Add priority row to TaskDetailView <!-- id:3dib3y0 -->
  - Priority row in both iOS (LabeledContent) and macOS (FormRow) layouts
  - Render as text for all three levels (task.priority.rawValue.capitalized), like the Status row, so medium is visible
  - Blocked-by: 3dib3xl (Add priorityRawValue stored property, priority computed accessor, and init param to TransitTask)
  - Stream: 2
  - Requirements: [4.4](requirements.md#4.4)
  - References: specs/task-priority/design.md

## Verification

- [x] 20. Write effective-priority invariant cross-surface regression test <!-- id:3dib3y1 -->
  - A task with priorityRawValue = empty string (legacy) reads/serializes as medium and is matched by a medium filter on every read surface
  - Surfaces: board matchesFilters, MCPQueryFilters.matches, MCP taskToDict serialization, intent applyFilters, intent taskUpdateResponseDict
  - This is the guard against a raw-value copy-paste breaking Req 1.4
  - Blocked-by: 3dib3xs (Implement MCP priority support), 3dib3xu (Implement JSON App Intents priority support), 3dib3xw (Implement PriorityFilterMenu and wire into DashboardView)
  - Stream: 1
  - Requirements: [1.3](requirements.md#1.3), [1.4](requirements.md#1.4)
  - References: specs/task-priority/design.md
