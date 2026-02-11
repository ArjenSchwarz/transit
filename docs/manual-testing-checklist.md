# Manual Testing Checklist: Shortcuts-Friendly Intents

**Task**: 14.1 - Test all three intents via Shortcuts interface  
**Date**: 2026-02-12  
**Tester**: _____________

## Prerequisites

- [ ] Transit app built and installed on test device/simulator
- [ ] At least one project exists in Transit (required for task creation)
- [ ] At least one task exists in Transit (for testing Find Tasks)
- [ ] Shortcuts app accessible on the device

## Test Environment

- **Device/Simulator**: _____________
- **OS Version**: _____________
- **Transit Build**: _____________

---

## 1. Intent Discoverability (Task 14.2)

### Test: All intents appear in Shortcuts app

- [ ] Open Shortcuts app
- [ ] Create a new shortcut
- [ ] Tap "Add Action"
- [ ] Search for "Transit"
- [ ] **Verify**: "Transit: Add Task" appears in search results
- [ ] **Verify**: "Transit: Find Tasks" appears in search results
- [ ] **Verify**: "Transit: Query Tasks" appears in search results (existing intent)
- [ ] **Verify**: "Transit: Create Task" appears in search results (existing JSON intent)
- [ ] **Verify**: "Transit: Update Status" appears in search results (existing JSON intent)

**Result**: ☐ Pass ☐ Fail  
**Notes**: _____________

---

## 2. Transit: Add Task Intent

### Test 2.1: Basic task creation with all parameters

- [ ] Add "Transit: Add Task" action to a shortcut
- [ ] **Verify**: "Name" parameter is visible (required)
- [ ] **Verify**: "Description" parameter is visible (optional)
- [ ] **Verify**: "Type" parameter shows dropdown
- [ ] **Verify**: "Project" parameter shows dropdown
- [ ] Fill in:
  - Name: "Test Task from Shortcuts"
  - Description: "This is a test description"
  - Type: Select "Feature"
  - Project: Select any existing project
- [ ] Run the shortcut
- [ ] **Verify**: Transit app opens (foreground mode)
- [ ] **Verify**: Task appears in the Idea column
- [ ] **Verify**: Task has correct name, description, type, and project
- [ ] **Verify**: Task has a display ID (T-XXX) or provisional ID

**Result**: ☐ Pass ☐ Fail  
**Notes**: _____________

### Test 2.2: Task creation without optional description

- [ ] Create shortcut with "Transit: Add Task"
- [ ] Fill in:
  - Name: "Task without description"
  - Type: "Bug"
  - Project: Select any project
  - Description: Leave empty
- [ ] Run the shortcut
- [ ] **Verify**: Task is created successfully
- [ ] **Verify**: Task has no description in Transit app

**Result**: ☐ Pass ☐ Fail  
**Notes**: _____________

### Test 2.3: Type dropdown shows all task types

- [ ] Add "Transit: Add Task" action
- [ ] Tap on "Type" parameter
- [ ] **Verify**: Dropdown shows:
  - Bug
  - Feature
  - Chore
  - Research
  - Documentation

**Result**: ☐ Pass ☐ Fail  
**Notes**: _____________

### Test 2.4: Project dropdown populates from existing projects

- [ ] Ensure multiple projects exist in Transit app
- [ ] Add "Transit: Add Task" action
- [ ] Tap on "Project" parameter
- [ ] **Verify**: Dropdown shows all existing projects
- [ ] **Verify**: Project names are displayed correctly

**Result**: ☐ Pass ☐ Fail  
**Notes**: _____________

### Test 2.5: Error when no projects exist (Task 14.3)

- [ ] Delete all projects from Transit app
- [ ] Create shortcut with "Transit: Add Task"
- [ ] Fill in required parameters
- [ ] Run the shortcut
- [ ] **Verify**: Error message appears
- [ ] **Verify**: Error says "No projects exist. Create a project in Transit first."
- [ ] **Verify**: Error includes recovery suggestion

**Result**: ☐ Pass ☐ Fail  
**Notes**: _____________

### Test 2.6: Error when name is empty (Task 14.3)

- [ ] Create shortcut with "Transit: Add Task"
- [ ] Leave "Name" parameter empty
- [ ] Fill in other parameters
- [ ] Run the shortcut
- [ ] **Verify**: Error message appears about invalid input

**Result**: ☐ Pass ☐ Fail  
**Notes**: _____________

### Test 2.7: Return value structure (Task 14.5)

- [ ] Create shortcut with "Transit: Add Task"
- [ ] Add "Show Result" action after the intent
- [ ] Run the shortcut
- [ ] **Verify**: Result shows TaskCreationResult with:
  - taskId (UUID)
  - displayId (integer or null)
  - status (should be "idea")
  - projectId (UUID)
  - projectName (string)

**Result**: ☐ Pass ☐ Fail  
**Notes**: _____________

---

## 3. Transit: Find Tasks Intent

### Test 3.1: Find tasks without any filters

- [ ] Create shortcut with "Transit: Find Tasks"
- [ ] Leave all filter parameters empty/unselected
- [ ] Add "Show Result" action
- [ ] Run the shortcut
- [ ] **Verify**: Shortcut runs in background (app does NOT open)
- [ ] **Verify**: Returns array of TaskEntity objects
- [ ] **Verify**: Results are sorted by lastStatusChangeDate (most recent first)
- [ ] **Verify**: Maximum 200 tasks returned

**Result**: ☐ Pass ☐ Fail  
**Notes**: _____________

### Test 3.2: Filter by task type

- [ ] Create tasks of different types in Transit
- [ ] Create shortcut with "Transit: Find Tasks"
- [ ] Set "Type" filter to "Bug"
- [ ] Run the shortcut
- [ ] **Verify**: Only tasks with type "Bug" are returned
- [ ] **Verify**: Other task types are excluded

**Result**: ☐ Pass ☐ Fail  
**Notes**: _____________

### Test 3.3: Filter by project

- [ ] Create tasks in different projects
- [ ] Create shortcut with "Transit: Find Tasks"
- [ ] Set "Project" filter to a specific project
- [ ] Run the shortcut
- [ ] **Verify**: Only tasks from selected project are returned

**Result**: ☐ Pass ☐ Fail  
**Notes**: _____________

### Test 3.4: Filter by status

- [ ] Create tasks with different statuses in Transit
- [ ] Create shortcut with "Transit: Find Tasks"
- [ ] Set "Status" filter to "In Progress"
- [ ] Run the shortcut
- [ ] **Verify**: Only tasks with "In Progress" status are returned

**Result**: ☐ Pass ☐ Fail  
**Notes**: _____________

### Test 3.5: Completion date filter - "Today" (Task 14.4)

- [ ] Complete a task today in Transit
- [ ] Create shortcut with "Transit: Find Tasks"
- [ ] Set "Completion Date" filter to "Today"
- [ ] Run the shortcut
- [ ] **Verify**: Only tasks completed today are returned
- [ ] **Verify**: Tasks completed yesterday are excluded

**Result**: ☐ Pass ☐ Fail  
**Notes**: _____________

### Test 3.6: Completion date filter - "This Week"

- [ ] Complete tasks at different times (this week, last week)
- [ ] Create shortcut with "Transit: Find Tasks"
- [ ] Set "Completion Date" filter to "This Week"
- [ ] Run the shortcut
- [ ] **Verify**: Only tasks completed this week are returned

**Result**: ☐ Pass ☐ Fail  
**Notes**: _____________

### Test 3.7: Completion date filter - "This Month"

- [ ] Complete tasks at different times (this month, last month)
- [ ] Create shortcut with "Transit: Find Tasks"
- [ ] Set "Completion Date" filter to "This Month"
- [ ] Run the shortcut
- [ ] **Verify**: Only tasks completed this month are returned

**Result**: ☐ Pass ☐ Fail  
**Notes**: _____________

### Test 3.8: Completion date filter - "Custom Range" (Task 14.4)

- [ ] Create shortcut with "Transit: Find Tasks"
- [ ] Set "Completion Date" filter to "Custom Range"
- [ ] **Verify**: "Completed From" date picker appears
- [ ] **Verify**: "Completed To" date picker appears
- [ ] Set date range (e.g., 2026-02-01 to 2026-02-10)
- [ ] Run the shortcut
- [ ] **Verify**: Only tasks completed within the date range are returned

**Result**: ☐ Pass ☐ Fail  
**Notes**: _____________

### Test 3.9: Last Changed filter - "Today"

- [ ] Change status of a task today
- [ ] Create shortcut with "Transit: Find Tasks"
- [ ] Set "Last Changed" filter to "Today"
- [ ] Run the shortcut
- [ ] **Verify**: Only tasks with status changed today are returned

**Result**: ☐ Pass ☐ Fail  
**Notes**: _____________

### Test 3.10: Last Changed filter - "Custom Range" (Task 14.4)

- [ ] Create shortcut with "Transit: Find Tasks"
- [ ] Set "Last Changed" filter to "Custom Range"
- [ ] **Verify**: "Changed From" date picker appears
- [ ] **Verify**: "Changed To" date picker appears
- [ ] Set date range
- [ ] Run the shortcut
- [ ] **Verify**: Only tasks with status changed within the date range are returned

**Result**: ☐ Pass ☐ Fail  
**Notes**: _____________

### Test 3.11: Multiple filters combined (AND logic)

- [ ] Create shortcut with "Transit: Find Tasks"
- [ ] Set multiple filters:
  - Type: "Feature"
  - Status: "In Progress"
  - Last Changed: "This Week"
- [ ] Run the shortcut
- [ ] **Verify**: Only tasks matching ALL filters are returned
- [ ] **Verify**: Tasks matching only some filters are excluded

**Result**: ☐ Pass ☐ Fail  
**Notes**: _____________

### Test 3.12: Empty results (no error)

- [ ] Create shortcut with "Transit: Find Tasks"
- [ ] Set filters that match no tasks (e.g., impossible combination)
- [ ] Run the shortcut
- [ ] **Verify**: Returns empty array (not an error)
- [ ] **Verify**: Shortcut completes successfully

**Result**: ☐ Pass ☐ Fail  
**Notes**: _____________

### Test 3.13: TaskEntity properties accessible (Task 14.5)

- [ ] Create shortcut with "Transit: Find Tasks"
- [ ] Add "Get Details of Tasks" action after the intent
- [ ] **Verify**: Can access properties:
  - taskId
  - displayId
  - name
  - status
  - type
  - projectId
  - projectName
  - lastStatusChangeDate
  - completionDate
- [ ] Add "Show Result" to display a specific property
- [ ] Run the shortcut
- [ ] **Verify**: Property values are correct

**Result**: ☐ Pass ☐ Fail  
**Notes**: _____________

### Test 3.14: Conditional parameter display (Task 14.4)

- [ ] Create shortcut with "Transit: Find Tasks"
- [ ] **Initial state**: Verify date pickers are NOT visible
- [ ] Set "Completion Date" to "Custom Range"
- [ ] **Verify**: "Completed From" and "Completed To" date pickers appear
- [ ] Set "Completion Date" back to "Today"
- [ ] **Verify**: Date pickers disappear
- [ ] Set "Last Changed" to "Custom Range"
- [ ] **Verify**: "Changed From" and "Changed To" date pickers appear
- [ ] Set both filters to "Custom Range"
- [ ] **Verify**: All 4 date pickers are visible simultaneously

**Result**: ☐ Pass ☐ Fail  
**Notes**: _____________

---

## 4. Transit: Query Tasks Intent (Enhanced with Date Filtering)

### Test 4.1: Backward compatibility - query without date filters (Task 15.1)

- [ ] Create shortcut with "Transit: Query Tasks"
- [ ] Use existing JSON format without date filters:
  ```json
  {
    "type": "feature",
    "status": "in-progress"
  }
  ```
- [ ] Run the shortcut
- [ ] **Verify**: Returns JSON array of tasks
- [ ] **Verify**: Existing behavior unchanged

**Result**: ☐ Pass ☐ Fail  
**Notes**: _____________

### Test 4.2: Date filter - completionDate with relative range

- [ ] Create shortcut with "Transit: Query Tasks"
- [ ] Use JSON input:
  ```json
  {
    "completionDate": {
      "relative": "today"
    }
  }
  ```
- [ ] Run the shortcut
- [ ] **Verify**: Returns only tasks completed today
- [ ] Test with "this-week" and "this-month"

**Result**: ☐ Pass ☐ Fail  
**Notes**: _____________

### Test 4.3: Date filter - completionDate with absolute range

- [ ] Create shortcut with "Transit: Query Tasks"
- [ ] Use JSON input:
  ```json
  {
    "completionDate": {
      "from": "2026-02-01",
      "to": "2026-02-10"
    }
  }
  ```
- [ ] Run the shortcut
- [ ] **Verify**: Returns only tasks completed within the date range

**Result**: ☐ Pass ☐ Fail  
**Notes**: _____________

### Test 4.4: Date filter - lastStatusChangeDate

- [ ] Create shortcut with "Transit: Query Tasks"
- [ ] Use JSON input:
  ```json
  {
    "lastStatusChangeDate": {
      "relative": "this-week"
    }
  }
  ```
- [ ] Run the shortcut
- [ ] **Verify**: Returns only tasks with status changed this week

**Result**: ☐ Pass ☐ Fail  
**Notes**: _____________

### Test 4.5: Date filter - only "from" date

- [ ] Create shortcut with "Transit: Query Tasks"
- [ ] Use JSON input:
  ```json
  {
    "completionDate": {
      "from": "2026-02-01"
    }
  }
  ```
- [ ] Run the shortcut
- [ ] **Verify**: Returns tasks completed on or after 2026-02-01

**Result**: ☐ Pass ☐ Fail  
**Notes**: _____________

### Test 4.6: Date filter - only "to" date

- [ ] Create shortcut with "Transit: Query Tasks"
- [ ] Use JSON input:
  ```json
  {
    "completionDate": {
      "to": "2026-02-10"
    }
  }
  ```
- [ ] Run the shortcut
- [ ] **Verify**: Returns tasks completed on or before 2026-02-10

**Result**: ☐ Pass ☐ Fail  
**Notes**: _____________

### Test 4.7: Error handling - invalid date format (Task 14.3)

- [ ] Create shortcut with "Transit: Query Tasks"
- [ ] Use JSON input with invalid date:
  ```json
  {
    "completionDate": {
      "from": "invalid-date"
    }
  }
  ```
- [ ] Run the shortcut
- [ ] **Verify**: Returns error JSON with code "INVALID_DATE"

**Result**: ☐ Pass ☐ Fail  
**Notes**: _____________

---

## 5. Backward Compatibility Tests (Task 15)

### Test 5.1: Transit: Create Task (existing JSON intent) (Task 15.2)

- [ ] Create shortcut with "Transit: Create Task"
- [ ] Use existing JSON format:
  ```json
  {
    "name": "Test task from JSON intent",
    "type": "feature",
    "projectName": "Test Project"
  }
  ```
- [ ] Run the shortcut
- [ ] **Verify**: Task is created successfully
- [ ] **Verify**: JSON response format unchanged

**Result**: ☐ Pass ☐ Fail  
**Notes**: _____________

### Test 5.2: Transit: Update Status (existing intent) (Task 15.3)

- [ ] Create a task in Transit
- [ ] Create shortcut with "Transit: Update Status"
- [ ] Use existing JSON format:
  ```json
  {
    "taskId": "<uuid>",
    "status": "in-progress"
  }
  ```
- [ ] Run the shortcut
- [ ] **Verify**: Task status is updated
- [ ] **Verify**: JSON response format unchanged

**Result**: ☐ Pass ☐ Fail  
**Notes**: _____________

### Test 5.3: Intent names unchanged (Task 15.4)

- [ ] Open Shortcuts app
- [ ] Search for "Transit"
- [ ] **Verify**: Intent names are exactly:
  - "Transit: Add Task" (new)
  - "Transit: Find Tasks" (new)
  - "Transit: Query Tasks" (existing)
  - "Transit: Create Task" (existing)
  - "Transit: Update Status" (existing)

**Result**: ☐ Pass ☐ Fail  
**Notes**: _____________

### Test 5.4: JSON formats unchanged (Task 15.5)

- [ ] Test all existing JSON intents with previous JSON formats
- [ ] **Verify**: All input formats still accepted
- [ ] **Verify**: All output formats unchanged
- [ ] **Verify**: No breaking changes to JSON structure

**Result**: ☐ Pass ☐ Fail  
**Notes**: _____________

---

## Summary

**Total Tests**: 50  
**Passed**: _____  
**Failed**: _____  
**Blocked**: _____  

### Critical Issues Found

_List any critical issues that block release:_

1. _____________
2. _____________

### Non-Critical Issues Found

_List any minor issues or improvements:_

1. _____________
2. _____________

### Overall Assessment

☐ All tests passed - Ready for release  
☐ Minor issues found - Can proceed with release  
☐ Critical issues found - Requires fixes before release

### Sign-off

**Tester**: _____________  
**Date**: _____________  
**Signature**: _____________
