# Backward Compatibility Verification Guide

## Overview

Task 15 verifies that all existing JSON-based intents continue to work unchanged after adding the new Shortcuts-friendly visual intents. This ensures CLI automation users don't need to rewrite their scripts.

## Requirements

From `requirements.md` section 6:

- **6.1:** QueryTasksIntent remains available with JSON interface
- **6.2:** CreateTaskIntent remains available with JSON interface
- **6.3:** UpdateStatusIntent remains available unchanged
- **6.4:** Intent names remain unchanged
- **6.5:** All existing JSON input formats continue to be accepted
- **6.6:** All existing JSON output formats remain unchanged
- **6.7:** Date filtering doesn't break existing queries
- **6.8:** No deprecation or removal of existing functionality

---

## Automated Tests

### Unit Tests for Backward Compatibility

The following unit tests verify backward compatibility:

#### QueryTasksIntent Tests

Located in: `Transit/TransitTests/QueryTasksIntentTests.swift`

**Test: `existingQueriesWithoutDateFiltersStillWork`**
- Verifies queries without date filters work as before
- Input: `{"status":"idea"}`
- Expected: Returns all tasks with "idea" status

**Test: `emptyDateFilterObjectIsIgnored`**
- Verifies empty date filter objects don't break queries
- Input: `{"completionDate":{}}`
- Expected: Returns all tasks (filter ignored)

**Test: `invalidDateFormatIsIgnored`**
- Verifies invalid date formats don't break queries
- Input: `{"completionDate":{"from":"invalid-date"}}`
- Expected: Returns all tasks (invalid date ignored)

#### CreateTaskIntent Tests

Located in: `Transit/TransitTests/CreateTaskIntentTests.swift`

**Test: `createsTaskWithValidInput`**
- Verifies basic task creation still works
- Input: `{"name":"Test Task","projectName":"Work"}`
- Expected: Task created successfully

**Test: `returnsErrorForMissingName`**
- Verifies error handling unchanged
- Input: `{"projectName":"Work"}`
- Expected: Returns error JSON with code "INVALID_INPUT"

**Test: `returnsErrorForNonExistentProject`**
- Verifies project validation unchanged
- Input: `{"name":"Task","projectName":"NonExistent"}`
- Expected: Returns error JSON with code "PROJECT_NOT_FOUND"

#### UpdateStatusIntent Tests

Located in: `Transit/TransitTests/UpdateStatusIntentTests.swift`

**Test: `updatesTaskStatusSuccessfully`**
- Verifies status updates still work
- Input: `{"taskId":"<uuid>","status":"in-progress"}`
- Expected: Task status updated, returns success JSON

**Test: `returnsErrorForInvalidTaskId`**
- Verifies error handling unchanged
- Input: `{"taskId":"invalid-uuid","status":"done"}`
- Expected: Returns error JSON with code "TASK_NOT_FOUND"

### Running Automated Tests

```bash
# Run all unit tests
make test-quick

# Run specific test suite
xcodebuild test -project Transit/Transit.xcodeproj -scheme Transit \
  -destination 'platform=macOS' \
  -only-testing:TransitTests/QueryTasksIntentTests

# Run specific test
xcodebuild test -project Transit/Transit.xcodeproj -scheme Transit \
  -destination 'platform=macOS' \
  -only-testing:TransitTests/QueryTasksIntentTests/existingQueriesWithoutDateFiltersStillWork
```

---

## Manual Verification

### 15.1: Test Existing QueryTasksIntent Without Date Filters

**Purpose:** Verify QueryTasksIntent works exactly as before when date filters are not used.

**Test Cases:**

**TC1: Basic query by status**
```json
Input: {"status": "in-progress"}
Expected: Returns JSON array of tasks with "in-progress" status
Format: [{"id":"...","displayId":"T-1","name":"...","status":"in-progress",...}]
```

**TC2: Query by project name**
```json
Input: {"projectName": "Work"}
Expected: Returns JSON array of tasks in "Work" project
```

**TC3: Query by type**
```json
Input: {"type": "bug"}
Expected: Returns JSON array of tasks with type "bug"
```

**TC4: Combined filters (no dates)**
```json
Input: {"projectName": "Work", "status": "done", "type": "feature"}
Expected: Returns JSON array of tasks matching all criteria
```

**TC5: Empty query**
```json
Input: {}
Expected: Returns JSON array of all tasks
```

**TC6: Invalid project name**
```json
Input: {"projectName": "NonExistent"}
Expected: Returns error JSON: {"error":"PROJECT_NOT_FOUND","message":"..."}
```

---

### 15.2: Test Existing CreateTaskIntent With Current JSON Format

**Purpose:** Verify CreateTaskIntent works exactly as before.

**Test Cases:**

**TC1: Create task with all fields**
```json
Input: {
  "name": "Test Task",
  "description": "Test description",
  "type": "feature",
  "projectName": "Work"
}
Expected: Returns success JSON with taskId, displayId, status, etc.
```

**TC2: Create task with minimal fields**
```json
Input: {
  "name": "Minimal Task",
  "projectName": "Work"
}
Expected: Task created with default type "feature", empty description
```

**TC3: Error - missing name**
```json
Input: {"projectName": "Work"}
Expected: Returns error JSON: {"error":"INVALID_INPUT","message":"..."}
```

**TC4: Error - missing project**
```json
Input: {"name": "Task"}
Expected: Returns error JSON: {"error":"INVALID_INPUT","message":"..."}
```

**TC5: Error - non-existent project**
```json
Input: {"name": "Task", "projectName": "NonExistent"}
Expected: Returns error JSON: {"error":"PROJECT_NOT_FOUND","message":"..."}
```

**TC6: Error - invalid type**
```json
Input: {"name": "Task", "projectName": "Work", "type": "invalid"}
Expected: Returns error JSON: {"error":"INVALID_INPUT","message":"..."}
```

---

### 15.3: Test Existing UpdateStatusIntent Unchanged

**Purpose:** Verify UpdateStatusIntent works exactly as before.

**Test Cases:**

**TC1: Update status successfully**
```json
Input: {"taskId": "<valid-uuid>", "status": "in-progress"}
Expected: Returns success JSON with updated task details
```

**TC2: Update to done status**
```json
Input: {"taskId": "<valid-uuid>", "status": "done"}
Expected: Task marked as done, completionDate set
```

**TC3: Update to abandoned status**
```json
Input: {"taskId": "<valid-uuid>", "status": "abandoned"}
Expected: Task marked as abandoned, completionDate set
```

**TC4: Error - invalid task ID**
```json
Input: {"taskId": "invalid-uuid", "status": "done"}
Expected: Returns error JSON: {"error":"TASK_NOT_FOUND","message":"..."}
```

**TC5: Error - invalid status**
```json
Input: {"taskId": "<valid-uuid>", "status": "invalid-status"}
Expected: Returns error JSON: {"error":"INVALID_STATUS","message":"..."}
```

**TC6: Error - missing task ID**
```json
Input: {"status": "done"}
Expected: Returns error JSON: {"error":"INVALID_INPUT","message":"..."}
```

---

### 15.4: Verify All Existing Intent Names Remain Unchanged

**Purpose:** Ensure intent names haven't changed, which would break existing shortcuts.

**Test Cases:**

**TC1: Verify intent names in Shortcuts app**
- Open Shortcuts app
- Search for "Transit"
- Expected intent names:
  - ✅ "Transit: Query Tasks" (QueryTasksIntent)
  - ✅ "Transit: Create Task" (CreateTaskIntent)
  - ✅ "Transit: Update Status" (UpdateStatusIntent)
  - ✅ "Transit: Add Task" (AddTaskIntent - new)
  - ✅ "Transit: Find Tasks" (FindTasksIntent - new)

**TC2: Verify intent names in code**
- Check `TransitShortcuts.swift`
- Verify shortTitle values match expected names

**TC3: Verify intent names in App Intents metadata**
- Build app
- Check extracted metadata
- Verify intent identifiers unchanged

---

### 15.5: Verify JSON Input/Output Formats Unchanged for Existing Intents

**Purpose:** Ensure JSON schemas haven't changed, which would break CLI integrations.

**Test Cases:**

**TC1: QueryTasksIntent input format**
- Verify accepts all previous input fields:
  - `projectName` (string, optional)
  - `status` (string, optional)
  - `type` (string, optional)
- Verify new fields are optional:
  - `completionDate` (object, optional)
  - `lastStatusChangeDate` (object, optional)

**TC2: QueryTasksIntent output format**
- Verify output structure unchanged:
  ```json
  [
    {
      "id": "uuid",
      "displayId": "T-1",
      "name": "Task name",
      "description": "...",
      "status": "in-progress",
      "type": "feature",
      "projectId": "uuid",
      "projectName": "Work",
      "completionDate": "2026-02-12T00:00:00Z" or null,
      "lastStatusChangeDate": "2026-02-12T00:00:00Z"
    }
  ]
  ```

**TC3: CreateTaskIntent input format**
- Verify accepts all previous input fields:
  - `name` (string, required)
  - `description` (string, optional)
  - `type` (string, optional)
  - `projectName` (string, required)

**TC4: CreateTaskIntent output format**
- Verify output structure unchanged:
  ```json
  {
    "taskId": "uuid",
    "displayId": "T-1",
    "status": "idea",
    "projectId": "uuid",
    "projectName": "Work"
  }
  ```

**TC5: UpdateStatusIntent input format**
- Verify accepts all previous input fields:
  - `taskId` (string, required)
  - `status` (string, required)

**TC6: UpdateStatusIntent output format**
- Verify output structure unchanged:
  ```json
  {
    "taskId": "uuid",
    "displayId": "T-1",
    "status": "in-progress",
    "previousStatus": "idea",
    "lastStatusChangeDate": "2026-02-12T00:00:00Z"
  }
  ```

**TC7: Error response format**
- Verify error JSON structure unchanged:
  ```json
  {
    "error": "ERROR_CODE",
    "message": "Human-readable error message"
  }
  ```

---

## CLI Testing Script

For comprehensive CLI testing, use this script:

```bash
#!/bin/bash
# backward-compatibility-test.sh

# Prerequisites:
# 1. Transit app is running
# 2. At least one project exists (e.g., "Work")
# 3. At least one task exists

echo "=== Backward Compatibility Tests ==="

# Test 1: QueryTasksIntent without date filters
echo "Test 1: Query tasks by status"
shortcuts run "Transit: Query Tasks" <<< '{"status":"idea"}'

# Test 2: CreateTaskIntent
echo "Test 2: Create task"
shortcuts run "Transit: Create Task" <<< '{"name":"BC Test Task","projectName":"Work"}'

# Test 3: UpdateStatusIntent
echo "Test 3: Update task status"
# Note: Replace <task-id> with actual task UUID
shortcuts run "Transit: Update Status" <<< '{"taskId":"<task-id>","status":"in-progress"}'

# Test 4: Query with invalid project (error case)
echo "Test 4: Query with invalid project"
shortcuts run "Transit: Query Tasks" <<< '{"projectName":"NonExistent"}'

# Test 5: Create task with missing name (error case)
echo "Test 5: Create task with missing name"
shortcuts run "Transit: Create Task" <<< '{"projectName":"Work"}'

echo "=== Tests Complete ==="
```

---

## Verification Checklist

### Automated Tests
- [ ] All QueryTasksIntent backward compatibility tests pass
- [ ] All CreateTaskIntent tests pass
- [ ] All UpdateStatusIntent tests pass
- [ ] No test regressions introduced

### Manual Verification
- [ ] 15.1: QueryTasksIntent without date filters works
- [ ] 15.2: CreateTaskIntent with current JSON format works
- [ ] 15.3: UpdateStatusIntent unchanged
- [ ] 15.4: All existing intent names remain unchanged
- [ ] 15.5: JSON input/output formats unchanged

### Code Review
- [ ] No breaking changes to existing intent interfaces
- [ ] New parameters are optional
- [ ] Error handling unchanged for existing intents
- [ ] Intent names unchanged in TransitShortcuts.swift

---

## Known Issues

### Unit Test Failures

⚠️ Currently, some unit tests are failing. These need to be investigated:
- QueryTasksIntent date filtering tests
- FindTasksIntent sorting tests
- AddTaskIntent error handling tests

These failures may indicate issues that need to be fixed before declaring backward compatibility verified.

---

## Completion Criteria

Task 15 is complete when:

- [ ] All automated backward compatibility tests pass
- [ ] All manual verification test cases pass
- [ ] No breaking changes detected
- [ ] Existing CLI integrations work unchanged
- [ ] Documentation updated with verification results

---

## Testing Notes

### How to Test via Shortcuts CLI

On macOS, you can test intents via the `shortcuts` command:

```bash
# List all shortcuts
shortcuts list

# Run a shortcut with input
shortcuts run "Transit: Query Tasks" <<< '{"status":"idea"}'

# Or use echo
echo '{"status":"idea"}' | shortcuts run "Transit: Query Tasks"
```

### How to Test via Shortcuts App

1. Create a new shortcut
2. Add the intent action
3. Set the input parameter to the JSON string
4. Run the shortcut
5. Verify the output

### Debugging Tips

- Use `Console.app` to view app logs
- Check for error messages in Shortcuts app
- Verify JSON parsing with `jq` command:
  ```bash
  echo '{"status":"idea"}' | jq .
  ```

---

## References

- Requirements: `specs/shortcuts-friendly-intents/requirements.md` section 6
- Design: `specs/shortcuts-friendly-intents/design.md`
- Unit Tests: `Transit/TransitTests/*IntentTests.swift`
