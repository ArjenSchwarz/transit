# Manual Testing Guide: Shortcuts-Friendly Intents

This guide provides step-by-step instructions for manually testing the three new/enhanced intents through the Shortcuts app on iOS/iPadOS/macOS.

## Prerequisites

1. Build and install Transit app on your test device
2. Create at least 2 projects in Transit (e.g., "Work", "Personal")
3. Create a few test tasks with different statuses and types
4. Open the Shortcuts app

## Test Suite

### 14.1: Test All Three Intents via Shortcuts Interface

#### Test 14.1.1: AddTaskIntent (Transit: Add Task)

**Setup:**
1. Open Shortcuts app
2. Create a new shortcut
3. Add action: Search for "Transit" or "Add Task"
4. Select "Transit: Add Task" action

**Test Cases:**

**TC1: Basic task creation with all parameters**
- Fill in:
  - Name: "Test Task from Shortcuts"
  - Description: "This is a test description"
  - Type: Select "Feature"
  - Project: Select one of your projects
- Run the shortcut
- Expected: 
  - App opens to the kanban board
  - New task appears in the Idea column
  - Task has the correct name, description, type, and project
  - Result shows taskId, displayId (e.g., "T-42"), status, projectId, projectName

**TC2: Minimal task creation (name and project only)**
- Fill in:
  - Name: "Minimal Task"
  - Project: Select a project
  - Leave description empty
  - Leave type as default
- Run the shortcut
- Expected:
  - Task created successfully
  - Description is empty
  - Type defaults to "Feature"

**TC3: Error handling - empty name**
- Fill in:
  - Name: "" (empty)
  - Project: Select a project
- Run the shortcut
- Expected:
  - Error message displayed
  - No task created

**TC4: Error handling - no projects exist**
- Delete all projects from Transit
- Try to run the shortcut
- Expected:
  - Error message: "NO_PROJECTS: No projects available. Please create a project first."
  - Shortcut fails gracefully

---

#### Test 14.1.2: FindTasksIntent (Transit: Find Tasks)

**Setup:**
1. Ensure you have tasks with various statuses, types, and projects
2. Create a new shortcut
3. Add action: "Transit: Find Tasks"

**Test Cases:**

**TC1: Find all tasks (no filters)**
- Leave all filters empty/default
- Run the shortcut
- Expected:
  - Returns array of TaskEntity objects
  - Maximum 200 tasks
  - Sorted by lastStatusChangeDate (most recent first)
  - App does NOT open

**TC2: Filter by project**
- Select a specific project
- Run the shortcut
- Expected:
  - Only tasks from that project returned
  - Other filters not applied

**TC3: Filter by status**
- Select status: "In Progress"
- Run the shortcut
- Expected:
  - Only tasks with "In Progress" status returned

**TC4: Filter by type**
- Select type: "Bug"
- Run the shortcut
- Expected:
  - Only tasks with type "Bug" returned

**TC5: Combine multiple filters**
- Select project: "Work"
- Select status: "Done"
- Select type: "Feature"
- Run the shortcut
- Expected:
  - Only tasks matching ALL criteria returned (AND logic)

**TC6: Date filter - relative range (today)**
- Set "Completion Date" to "today"
- Run the shortcut
- Expected:
  - Only tasks completed today returned
  - No additional date parameters shown

**TC7: Date filter - relative range (this-week)**
- Set "Last Status Change Date" to "this-week"
- Run the shortcut
- Expected:
  - Only tasks with status changes this week returned

**TC8: Date filter - relative range (this-month)**
- Set "Completion Date" to "this-month"
- Run the shortcut
- Expected:
  - Only tasks completed this month returned

**TC9: Empty results**
- Set filters that match no tasks (e.g., project "Work" + status "Abandoned" + type "Bug")
- Run the shortcut
- Expected:
  - Returns empty array
  - No error thrown
  - App does NOT open

---

#### Test 14.1.3: QueryTasksIntent (Enhanced with Date Filtering)

**Setup:**
1. Create a new shortcut
2. Add action: "Transit: Query Tasks"

**Test Cases:**

**TC1: Query without date filters (backward compatibility)**
- Use existing JSON format without date filters:
```json
{
  "projectName": "Work",
  "status": "in-progress"
}
```
- Run the shortcut
- Expected:
  - Returns JSON string with matching tasks
  - Behaves exactly as before enhancement

**TC2: Query with completion date filter (relative)**
- Use JSON format:
```json
{
  "status": "done",
  "completionDate": {
    "range": "today"
  }
}
```
- Run the shortcut
- Expected:
  - Returns tasks completed today
  - JSON output format unchanged

**TC3: Query with custom date range (absolute)**
- Use JSON format:
```json
{
  "lastStatusChangeDate": {
    "range": "custom-range",
    "from": "2026-02-01T00:00:00Z",
    "to": "2026-02-12T23:59:59Z"
  }
}
```
- Run the shortcut
- Expected:
  - Returns tasks with status changes in specified range
  - Inclusive boundaries (includes both from and to dates)

**TC4: Invalid date format**
- Use JSON format:
```json
{
  "completionDate": {
    "range": "custom-range",
    "from": "invalid-date"
  }
}
```
- Run the shortcut
- Expected:
  - Returns error JSON with code "INVALID_DATE"

---

### 14.2: Verify Intent Discoverability in Shortcuts App

**Test Cases:**

**TC1: Search for Transit intents**
- Open Shortcuts app
- Create new shortcut
- Search for "Transit"
- Expected:
  - All 5 intents appear:
    - Transit: Create Task (JSON-based)
    - Transit: Add Task (Visual)
    - Transit: Update Status (JSON-based)
    - Transit: Query Tasks (JSON-based, enhanced)
    - Transit: Find Tasks (Visual)

**TC2: Verify intent titles and descriptions**
- For each intent, check:
  - Title is clear and descriptive
  - Icon is appropriate
  - Description explains what the intent does
- Expected:
  - AddTaskIntent: "Add a new task to Transit with visual parameter selection"
  - FindTasksIntent: "Search for tasks in Transit using filters"
  - QueryTasksIntent: Description mentions date filtering capability

**TC3: Verify intent appears in Siri suggestions**
- Use Transit app for a while
- Check Siri suggestions
- Expected:
  - Transit intents may appear in suggestions (not guaranteed, depends on usage)

---

### 14.3: Test Error Handling for All Error Cases

#### AddTaskIntent Error Cases

**TC1: NO_PROJECTS error**
- Delete all projects
- Try to create task
- Expected: Error message with code "NO_PROJECTS"

**TC2: INVALID_INPUT error (empty name)**
- Provide empty task name
- Expected: Error message with code "INVALID_INPUT"

**TC3: TASK_CREATION_FAILED error**
- This is harder to trigger manually
- Could be simulated by filling device storage
- Expected: Error message with code "TASK_CREATION_FAILED"

#### FindTasksIntent Error Cases

**TC1: INVALID_DATE error**
- Use custom-range with invalid date format
- Expected: Error message with code "INVALID_DATE"

**TC2: PROJECT_NOT_FOUND error**
- This shouldn't happen in normal use (dropdown prevents it)
- Could be tested via direct API call if needed

#### QueryTasksIntent Error Cases

**TC1: INVALID_INPUT error (malformed JSON)**
- Provide invalid JSON string
- Expected: Error JSON response with code "INVALID_INPUT"

**TC2: PROJECT_NOT_FOUND error**
- Provide non-existent project name
- Expected: Error JSON response with code "PROJECT_NOT_FOUND"

**TC3: AMBIGUOUS_PROJECT error**
- Create two projects with similar names (if case-insensitive matching allows)
- Query with ambiguous name
- Expected: Error JSON response with code "AMBIGUOUS_PROJECT"

---

### 14.4: Test Conditional Parameter Display (Custom-Range Dates)

**Test Cases:**

**TC1: FindTasksIntent - Completion Date custom-range**
- Open FindTasksIntent in Shortcuts
- Set "Completion Date" to "none"
- Expected: No additional date parameters shown
- Change to "today"
- Expected: No additional date parameters shown
- Change to "this-week"
- Expected: No additional date parameters shown
- Change to "custom-range"
- Expected: Two new parameters appear:
  - "Completion Date From"
  - "Completion Date To"

**TC2: FindTasksIntent - Last Status Change Date custom-range**
- Set "Last Status Change Date" to "custom-range"
- Expected: Two new parameters appear:
  - "Last Status Change Date From"
  - "Last Status Change Date To"

**TC3: Both date filters with custom-range**
- Set both "Completion Date" and "Last Status Change Date" to "custom-range"
- Expected: Four date parameters appear total:
  - Completion Date From
  - Completion Date To
  - Last Status Change Date From
  - Last Status Change Date To

**TC4: Parameter summary updates**
- As you change filters, verify the parameter summary at the top updates correctly
- Expected: Summary shows selected filters in readable format

---

### 14.5: Verify TaskEntity Properties Are Accessible in Shortcuts

**Test Cases:**

**TC1: Access TaskEntity properties in Shortcuts**
- Create a shortcut with FindTasksIntent
- Add a "Get Details of Shortcuts Input" action after FindTasksIntent
- Run the shortcut
- Expected: Can access these properties:
  - id (UUID)
  - displayId (String, e.g., "T-42")
  - name (String)
  - description (String, optional)
  - status (String)
  - type (String)
  - projectId (UUID)
  - projectName (String)
  - completionDate (Date, optional)
  - lastStatusChangeDate (Date)

**TC2: Use TaskEntity in conditional logic**
- Create a shortcut that:
  1. Finds tasks with status "Done"
  2. Filters results where completionDate is today
  3. Shows notification with count
- Expected: Shortcut can access and use TaskEntity properties in logic

**TC3: Display TaskEntity in notification**
- Create a shortcut that:
  1. Finds a specific task
  2. Shows notification with task details
- Expected: displayRepresentation shows correctly:
  - Title: "[displayId] name"
  - Subtitle: "projectName"

**TC4: Pass TaskEntity to other actions**
- Create a shortcut that:
  1. Finds tasks
  2. Creates a list from task names
  3. Shows in Quick Look
- Expected: Can extract and use properties from TaskEntity array

---

## Test Results Template

For each test case, record:

```
Test ID: [e.g., 14.1.1-TC1]
Date: [YYYY-MM-DD]
Tester: [Name]
Device: [iOS/iPadOS/macOS version]
Result: [PASS/FAIL]
Notes: [Any observations, issues, or unexpected behavior]
```

## Known Limitations

1. **Display ID allocation offline**: When offline, tasks may get provisional IDs (e.g., "T-PROV-1") that are replaced when connectivity is restored
2. **200-task limit**: FindTasksIntent returns maximum 200 tasks to prevent performance issues
3. **CloudKit sync delay**: Changes may take a few seconds to sync across devices
4. **Date timezone**: All date comparisons use device's local timezone via `Calendar.current`

## Troubleshooting

**Issue: Intents don't appear in Shortcuts app**
- Solution: Rebuild app, ensure it's installed, restart Shortcuts app

**Issue: "No projects available" error**
- Solution: Create at least one project in Transit first

**Issue: Date filters not working as expected**
- Solution: Check device timezone, verify date format is ISO 8601

**Issue: App doesn't open after AddTaskIntent**
- Solution: Check intent's `openAppWhenRun` property is true

**Issue: FindTasksIntent opens app**
- Solution: Verify intent's `openAppWhenRun` property is false

---

## Completion Criteria

Task 14 is complete when:

- [ ] All test cases in 14.1 pass
- [ ] All intents are discoverable in Shortcuts app (14.2)
- [ ] All error cases are handled correctly (14.3)
- [ ] Conditional parameters display correctly (14.4)
- [ ] TaskEntity properties are accessible (14.5)
- [ ] No crashes or unexpected behavior
- [ ] All error messages are clear and actionable
