---
references:
    - specs/shortcuts-friendly-intents/requirements.md
    - specs/shortcuts-friendly-intents/design.md
    - specs/shortcuts-friendly-intents/decision_log.md
---
# Implementation Tasks: Shortcuts-Friendly Intents

## Foundation: Shared Infrastructure

- [x] 1. Implement TaskStatus AppEnum conformance <!-- id:2ds0b3t -->
  - Stream: 1
  - Requirements: [5.6](requirements.md#5.6), [5.7](requirements.md#5.7), [5.10](requirements.md#5.10)
  - [x] 1.1. Write unit tests for TaskStatus AppEnum <!-- id:2ds0b40 -->
    - Stream: 1
  - [x] 1.2. Implement AppEnum protocol conformance with display names <!-- id:2ds0b41 -->
    - Stream: 1
  - [x] 1.3. Mark static properties as nonisolated to avoid MainActor conflicts <!-- id:2ds0b42 -->
    - Stream: 1

- [x] 2. Implement TaskType AppEnum conformance <!-- id:2ds0b3u -->
  - Stream: 1
  - Requirements: [5.8](requirements.md#5.8), [5.9](requirements.md#5.9), [5.10](requirements.md#5.10)
  - [x] 2.1. Write unit tests for TaskType AppEnum <!-- id:2ds0b43 -->
    - Stream: 1
  - [x] 2.2. Implement AppEnum protocol conformance with display names <!-- id:2ds0b44 -->
    - Stream: 1
  - [x] 2.3. Mark static properties as nonisolated to avoid MainActor conflicts <!-- id:2ds0b45 -->
    - Stream: 1

- [x] 3. Implement VisualIntentError enum <!-- id:2ds0b3v -->
  - Stream: 1
  - Requirements: [7.2](requirements.md#7.2), [7.3](requirements.md#7.3), [7.4](requirements.md#7.4), [7.5](requirements.md#7.5), [7.6](requirements.md#7.6), [7.7](requirements.md#7.7), [7.8](requirements.md#7.8), [7.9](requirements.md#7.9)
  - [x] 3.1. Write unit tests for VisualIntentError <!-- id:2ds0b46 -->
    - Stream: 1
  - [x] 3.2. Implement LocalizedError conformance with error codes <!-- id:2ds0b47 -->
    - Stream: 1
  - [x] 3.3. Add all error cases: noProjects, invalidInput, invalidDate, projectNotFound, taskNotFound, taskCreationFailed <!-- id:2ds0b48 -->
    - Stream: 1

- [x] 4. Implement ProjectEntity and ProjectEntityQuery <!-- id:2ds0b3w -->
  - Stream: 1
  - Requirements: [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [5.4](requirements.md#5.4), [5.5](requirements.md#5.5)
  - [x] 4.1. Write unit tests for ProjectEntity <!-- id:2ds0b49 -->
    - Stream: 1
  - [x] 4.2. Implement ProjectEntity with id and name properties <!-- id:2ds0b4a -->
    - Stream: 1
  - [x] 4.3. Implement ProjectEntityQuery to fetch projects from ModelContext <!-- id:2ds0b4b -->
    - Stream: 1
  - [x] 4.4. Handle empty project list gracefully <!-- id:2ds0b4c -->
    - Stream: 1

- [x] 5. Implement TaskEntity struct <!-- id:2ds0b3x -->
  - Stream: 1
  - Requirements: [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [4.3](requirements.md#4.3), [4.4](requirements.md#4.4), [4.7](requirements.md#4.7), [4.9](requirements.md#4.9)
  - [x] 5.1. Write unit tests for TaskEntity <!-- id:2ds0b4d -->
    - Stream: 1
  - [x] 5.2. Implement AppEntity conformance with id and displayRepresentation <!-- id:2ds0b4e -->
    - Stream: 1
  - [x] 5.3. Add all required properties from requirement 3.9 <!-- id:2ds0b4f -->
    - Stream: 1
  - [x] 5.4. Implement static from() factory method with error handling <!-- id:2ds0b4g -->
    - Stream: 1

- [x] 6. Implement TaskEntityQuery <!-- id:2ds0b3y -->
  - Stream: 1
  - Requirements: [4.5](requirements.md#4.5), [4.6](requirements.md#4.6)
  - [x] 6.1. Write unit tests for TaskEntityQuery <!-- id:2ds0b4h -->
    - Stream: 1
  - [x] 6.2. Implement EntityQuery conformance with UUID resolution <!-- id:2ds0b4i -->
    - Stream: 1
  - [x] 6.3. Use fetch-then-filter pattern for CloudKit sync resilience <!-- id:2ds0b4j -->
    - Stream: 1
  - [x] 6.4. Use compactMap for batch contexts to handle sync issues gracefully <!-- id:2ds0b4k -->
    - Stream: 1

- [x] 7. Implement DateFilterHelpers utility <!-- id:2ds0b3z -->
  - Stream: 1
  - Requirements: [8.1](requirements.md#8.1), [8.2](requirements.md#8.2), [8.3](requirements.md#8.3), [8.4](requirements.md#8.4), [8.5](requirements.md#8.5), [8.6](requirements.md#8.6), [8.7](requirements.md#8.7), [8.8](requirements.md#8.8)
  - [x] 7.1. Write unit tests for DateFilterHelpers covering all scenarios <!-- id:2ds0b4l -->
    - Stream: 1
  - [x] 7.2. Implement relative date range calculation (today, this-week, this-month) <!-- id:2ds0b4m -->
    - Stream: 1
  - [x] 7.3. Implement absolute date range parsing from ISO 8601 strings <!-- id:2ds0b4n -->
    - Stream: 1
  - [x] 7.4. Use Calendar.current for all date calculations <!-- id:2ds0b4o -->
    - Stream: 1
  - [x] 7.5. Implement inclusive boundary date comparisons <!-- id:2ds0b4p -->
    - Stream: 1
  - [x] 7.6. Handle nil date values by excluding from filtered results <!-- id:2ds0b4q -->
    - Stream: 1

## Enhanced Query Intent

- [x] 8. Enhance QueryTasksIntent with date filtering <!-- id:2ds0b4r -->
  - Blocked-by: 2ds0b3z (Implement DateFilterHelpers utility)
  - Stream: 2
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.3](requirements.md#1.3), [1.4](requirements.md#1.4), [1.5](requirements.md#1.5), [1.6](requirements.md#1.6), [1.7](requirements.md#1.7), [1.8](requirements.md#1.8), [1.9](requirements.md#1.9), [1.10](requirements.md#1.10), [1.11](requirements.md#1.11), [1.12](requirements.md#1.12)
  - [x] 8.1. Write unit tests for date filtering in QueryTasksIntent <!-- id:2ds0b4s -->
    - Stream: 2
  - [x] 8.2. Add DateRangeFilter codable type with from/to properties <!-- id:2ds0b4t -->
    - Stream: 2
  - [x] 8.3. Add optional completionDate and lastStatusChangeDate filter parameters <!-- id:2ds0b4u -->
    - Stream: 2
  - [x] 8.4. Update JSON schema to support relative and absolute date ranges <!-- id:2ds0b4v -->
    - Stream: 2
  - [x] 8.5. Implement filter logic using DateFilterHelpers <!-- id:2ds0b4w -->
    - Stream: 2
  - [x] 8.6. Update parameter description with date filter examples <!-- id:2ds0b4x -->
    - Stream: 2
  - [x] 8.7. Test backward compatibility with existing queries <!-- id:2ds0b4y -->
    - Stream: 2

## Visual Task Creation Intent

- [x] 9. Implement TaskCreationResult struct <!-- id:2ds0b4z -->
  - Blocked-by: 2ds0b3t (Implement TaskStatus AppEnum conformance), 2ds0b3u (Implement TaskType AppEnum conformance), 2ds0b3v (Implement VisualIntentError enum)
  - Stream: 3
  - Requirements: [2.10](requirements.md#2.10), [4.8](requirements.md#4.8), [4.9](requirements.md#4.9)
  - [x] 9.1. Write unit tests for TaskCreationResult <!-- id:2ds0b50 -->
    - Stream: 3
  - [x] 9.2. Implement struct with taskId, displayId, status, projectId, projectName <!-- id:2ds0b51 -->
    - Stream: 3
  - [x] 9.3. Use standard Swift types for Shortcuts serialization <!-- id:2ds0b52 -->
    - Stream: 3

- [x] 10. Implement AddTaskIntent (Transit: Add Task) <!-- id:2ds0b53 -->
  - Blocked-by: 2ds0b3w (Implement ProjectEntity and ProjectEntityQuery), 2ds0b3x (Implement TaskEntity struct), 2ds0b4z (Implement TaskCreationResult struct)
  - Stream: 3
  - Requirements: [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [2.3](requirements.md#2.3), [2.4](requirements.md#2.4), [2.5](requirements.md#2.5), [2.6](requirements.md#2.6), [2.7](requirements.md#2.7), [2.8](requirements.md#2.8), [2.11](requirements.md#2.11), [2.12](requirements.md#2.12), [2.13](requirements.md#2.13)
  - [x] 10.1. Write unit tests for AddTaskIntent <!-- id:2ds0b54 -->
    - Stream: 3
  - [x] 10.2. Add intent title and IntentDescription <!-- id:2ds0b55 -->
    - Stream: 3
  - [x] 10.3. Implement required name parameter (text field) <!-- id:2ds0b56 -->
    - Stream: 3
  - [x] 10.4. Implement optional description parameter (text field) <!-- id:2ds0b57 -->
    - Stream: 3
  - [x] 10.5. Implement task type dropdown using TaskType AppEnum <!-- id:2ds0b58 -->
    - Stream: 3
  - [x] 10.6. Implement project dropdown using ProjectEntity <!-- id:2ds0b59 -->
    - Stream: 3
  - [x] 10.7. Throw NO_PROJECTS error when no projects exist <!-- id:2ds0b5a -->
    - Stream: 3
  - [x] 10.8. Create tasks with initial status idea <!-- id:2ds0b5b -->
    - Stream: 3
  - [x] 10.9. Validate non-empty task name <!-- id:2ds0b5c -->
    - Stream: 3
  - [x] 10.10. Integrate with TaskService for task creation <!-- id:2ds0b5d -->
    - Stream: 3
  - [x] 10.11. Return TaskCreationResult with all required fields <!-- id:2ds0b5e -->
    - Stream: 3
  - [x] 10.12. Declare supportedModes including .foreground <!-- id:2ds0b5f -->
    - Stream: 3

- [x] 11. Write integration tests for AddTaskIntent <!-- id:2ds0b5g -->
  - Blocked-by: 2ds0b53 (Implement AddTaskIntent (Transit: Add Task))
  - Stream: 3

## Visual Task Search Intent

- [x] 12. Implement FindTasksIntent (Transit: Find Tasks) <!-- id:2ds0b5h -->
  - Blocked-by: 2ds0b3x (Implement TaskEntity struct), 2ds0b3y (Implement TaskEntityQuery), 2ds0b3z (Implement DateFilterHelpers utility), 2ds0b4r (Enhance QueryTasksIntent with date filtering)
  - Stream: 4
  - Requirements: [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3), [3.4](requirements.md#3.4), [3.5](requirements.md#3.5), [3.6](requirements.md#3.6), [3.7](requirements.md#3.7), [3.8](requirements.md#3.8), [3.9](requirements.md#3.9), [3.10](requirements.md#3.10), [3.11](requirements.md#3.11), [3.12](requirements.md#3.12), [3.13](requirements.md#3.13), [3.14](requirements.md#3.14), [3.15](requirements.md#3.15), [3.16](requirements.md#3.16)
  - [x] 12.1. Write unit tests for FindTasksIntent <!-- id:2ds0b5i -->
    - Stream: 4
  - [ ] 12.2. Add intent title and IntentDescription <!-- id:2ds0b5j -->
    - Stream: 4
  - [ ] 12.3. Implement optional task type filter dropdown <!-- id:2ds0b5k -->
    - Stream: 4
  - [ ] 12.4. Implement optional project filter dropdown <!-- id:2ds0b5l -->
    - Stream: 4
  - [ ] 12.5. Implement optional task status filter dropdown <!-- id:2ds0b5m -->
    - Stream: 4
  - [ ] 12.6. Implement completion date filter with relative options <!-- id:2ds0b5n -->
    - Stream: 4
  - [ ] 12.7. Implement last status change date filter with relative options <!-- id:2ds0b5o -->
    - Stream: 4
  - [ ] 12.8. Implement ParameterSummary with nested When clauses for custom-range <!-- id:2ds0b5p -->
    - Stream: 4
  - [ ] 12.9. Add conditional from/to date parameters for custom ranges <!-- id:2ds0b5q -->
    - Stream: 4
  - [ ] 12.10. Return [TaskEntity] array using TaskEntityQuery <!-- id:2ds0b5r -->
    - Stream: 4
  - [ ] 12.11. Apply all filters using AND logic <!-- id:2ds0b5s -->
    - Stream: 4
  - [ ] 12.12. Limit results to 200 tasks maximum <!-- id:2ds0b5t -->
    - Stream: 4
  - [ ] 12.13. Sort results by lastStatusChangeDate descending <!-- id:2ds0b5u -->
    - Stream: 4
  - [ ] 12.14. Return empty array when no matches (no error) <!-- id:2ds0b5v -->
    - Stream: 4
  - [ ] 12.15. Declare supportedModes as .background only <!-- id:2ds0b5w -->
    - Stream: 4
  - [ ] 12.16. Integrate with ModelContext for task queries <!-- id:2ds0b5x -->
    - Stream: 4

- [ ] 13. Write integration tests for FindTasksIntent <!-- id:2ds0b5y -->
  - Blocked-by: 2ds0b5h (Implement FindTasksIntent (Transit: Find Tasks))
  - Stream: 4

## Integration and Verification

- [ ] 14. End-to-end intent testing <!-- id:2ds0b5z -->
  - Blocked-by: 2ds0b4r (Enhance QueryTasksIntent with date filtering), 2ds0b53 (Implement AddTaskIntent (Transit: Add Task)), 2ds0b5h (Implement FindTasksIntent (Transit: Find Tasks))
  - Stream: 5
  - [ ] 14.1. Test all three intents via Shortcuts interface <!-- id:2ds0b60 -->
    - Stream: 5
  - [ ] 14.2. Verify intent discoverability in Shortcuts app <!-- id:2ds0b61 -->
    - Stream: 5
  - [ ] 14.3. Test error handling for all error cases <!-- id:2ds0b62 -->
    - Stream: 5
  - [ ] 14.4. Test conditional parameter display (custom-range dates) <!-- id:2ds0b63 -->
    - Stream: 5
  - [ ] 14.5. Verify TaskEntity properties are accessible in Shortcuts <!-- id:2ds0b64 -->
    - Stream: 5

- [ ] 15. Backward compatibility verification <!-- id:2ds0b65 -->
  - Blocked-by: 2ds0b4r (Enhance QueryTasksIntent with date filtering)
  - Stream: 5
  - Requirements: [6.1](requirements.md#6.1), [6.2](requirements.md#6.2), [6.3](requirements.md#6.3), [6.4](requirements.md#6.4), [6.5](requirements.md#6.5), [6.6](requirements.md#6.6), [6.7](requirements.md#6.7), [6.8](requirements.md#6.8)
  - [ ] 15.1. Test existing QueryTasksIntent without date filters <!-- id:2ds0b66 -->
    - Stream: 5
  - [ ] 15.2. Test existing CreateTaskIntent with current JSON format <!-- id:2ds0b67 -->
    - Stream: 5
  - [ ] 15.3. Test existing UpdateStatusIntent unchanged <!-- id:2ds0b68 -->
    - Stream: 5
  - [ ] 15.4. Verify all existing intent names remain unchanged <!-- id:2ds0b69 -->
    - Stream: 5
  - [ ] 15.5. Verify JSON input/output formats unchanged for existing intents <!-- id:2ds0b6a -->
    - Stream: 5
