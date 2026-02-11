# Integration Testing Guide: Shortcuts-Friendly Intents

This guide provides step-by-step instructions for manually testing the Shortcuts-Friendly Intents feature. These tests verify that all intents work correctly in the Shortcuts app and maintain backward compatibility with existing CLI integrations.

## Prerequisites

1. Build and install Transit on an iOS device or simulator:
   ```bash
   make build-ios
   ```

2. Launch Transit and create at least 2 projects with some test tasks:
   - Project 1: "Mobile App" (with 3-5 tasks in various statuses)
   - Project 2: "Backend API" (with 3-5 tasks in various statuses)

3. Ensure you have tasks with different:
   - Types: bug, feature, chore, research, documentation
   - Statuses: idea, planning, spec, inProgress, done, abandoned
   - Completion dates: some completed today, some this week, some older

## Test Suite 1: Intent Discoverability (Task 14.2)

### Test 1.1: Verify All Intents Are Discoverable

**Steps:**
1. Open the Shortcuts app
2. Create a new shortcut
3. Tap "Add Action"
4. Search for "Transit"

**Expected Results:**
- ✅ "Transit: Add Task" appears in search results
- ✅ "Transit: Find Tasks" appears in search results
- ✅ "Transit: Query Tasks" appears in search results (existing)
- ✅ "Transit: Create Task" appears in search results (existing)
- ✅ "Transit: Update Status" appears in search results (existing)

**Pass Criteria:** All 5 intents are discoverable via search

---

## Test Suite 2: Visual Task Creation Intent (Task 14.1)

### Test 2.1: Create Task with All Parameters

**Steps:**
1. Create a new shortcut
2. Add "Transit: Add Task" action
3. Fill in parameters:
   - Name: "Test Task from Shortcuts"
   - Description: "This is a test description"
   - Type: Select "Feature"
   - Project: Select "Mobile App"
4. Run the shortcut

**Expected Results:**
- ✅ Shortcut executes successfully
- ✅ Transit app opens automatically (foreground mode)
- ✅ New task appears in the "Idea" column
- ✅ Task has the correct name, description, type, and project
- ✅ Task has a display ID (T-X format)

**Pass Criteria:** Task is created with all specified parameters

### Test 2.2: Create Task with Minimal Parameters

**Steps:**
1. Create a new shortcut
2. Add "Transit: Add Task" action
3. Fill in only required parameters:
   - Name: "Minimal Task"
   - Type: Select "Bug"
   - Project: Select "Backend API"
   - Leave Description empty
4. Run the shortcut

**Expected Results:**
- ✅ Shortcut executes successfully
- ✅ Task is created without a description
- ✅ Task appears in the "Idea" column

**Pass Criteria:** Task is created with only required parameters

### Test 2.3: Project Dropdown Population

**Steps:**
1. Create a new shortcut
2. Add "Transit: Add Task" action
3. Tap on the "Project" parameter

**Expected Results:**
- ✅ Dropdown shows all existing projects
- ✅ Project names are displayed correctly
- ✅ Can select any project from the list

**Pass Criteria:** All projects are available in the dropdown

### Test 2.4: Type Dropdown Options

**Steps:**
1. Create a new shortcut
2. Add "Transit: Add Task" action
3. Tap on the "Type" parameter

**Expected Results:**
- ✅ Dropdown shows: Bug, Feature, Chore, Research, Documentation
- ✅ Display names are human-readable (capitalized)

**Pass Criteria:** All task types are available with correct display names

### Test 2.5: Error Handling - No Projects

**Steps:**
1. Delete all projects in Transit (or use a fresh install)
2. Create a shortcut with "Transit: Add Task"
3. Try to run the shortcut

**Expected Results:**
- ✅ Shortcut fails with a clear error message
- ✅ Error message says: "No projects exist. Create a project in Transit first."
- ✅ Error includes recovery suggestion

**Pass Criteria:** Clear error message when no projects exist

### Test 2.6: Error Handling - Empty Task Name

**Steps:**
1. Create a shortcut with "Transit: Add Task"
2. Leave the Name field empty
3. Run the shortcut

**Expected Results:**
- ✅ Shortcut fails with validation error
- ✅ Error indicates that name is required

**Pass Criteria:** Validation prevents empty task names

---

## Test Suite 3: Visual Task Search Intent (Task 14.1)

### Test 3.1: Find Tasks Without Filters

**Steps:**
1. Create a new shortcut
2. Add "Transit: Find Tasks" action
3. Leave all filters empty/unselected
4. Add "Show Result" action to display the output
5. Run the shortcut

**Expected Results:**
- ✅ Shortcut executes in background (app does NOT open)
- ✅ Returns all tasks (up to 200)
- ✅ Tasks are sorted by last status change date (most recent first)
- ✅ Each task shows: name, type, status

**Pass Criteria:** All tasks are returned without filters

### Test 3.2: Filter by Project

**Steps:**
1. Create a shortcut with "Transit: Find Tasks"
2. Set Project filter to "Mobile App"
3. Add "Show Result" action
4. Run the shortcut

**Expected Results:**
- ✅ Returns only tasks from "Mobile App" project
- ✅ No tasks from other projects are included

**Pass Criteria:** Project filter works correctly

### Test 3.3: Filter by Type

**Steps:**
1. Create a shortcut with "Transit: Find Tasks"
2. Set Type filter to "Bug"
3. Add "Show Result" action
4. Run the shortcut

**Expected Results:**
- ✅ Returns only tasks with type "Bug"
- ✅ No tasks with other types are included

**Pass Criteria:** Type filter works correctly

### Test 3.4: Filter by Status

**Steps:**
1. Create a shortcut with "Transit: Find Tasks"
2. Set Status filter to "In Progress"
3. Add "Show Result" action
4. Run the shortcut

**Expected Results:**
- ✅ Returns only tasks with status "In Progress"
- ✅ No tasks with other statuses are included

**Pass Criteria:** Status filter works correctly

### Test 3.5: Filter by Completion Date - Today

**Steps:**
1. Complete at least one task today in Transit
2. Create a shortcut with "Transit: Find Tasks"
3. Set Completion Date filter to "Today"
4. Add "Show Result" action
5. Run the shortcut

**Expected Results:**
- ✅ Returns only tasks completed today
- ✅ Tasks completed on other days are excluded
- ✅ Tasks without completion dates are excluded

**Pass Criteria:** "Today" completion date filter works correctly

### Test 3.6: Filter by Completion Date - This Week

**Steps:**
1. Create a shortcut with "Transit: Find Tasks"
2. Set Completion Date filter to "This Week"
3. Add "Show Result" action
4. Run the shortcut

**Expected Results:**
- ✅ Returns tasks completed from the start of the current week to now
- ✅ Tasks completed before this week are excluded

**Pass Criteria:** "This Week" completion date filter works correctly

### Test 3.7: Filter by Completion Date - This Month

**Steps:**
1. Create a shortcut with "Transit: Find Tasks"
2. Set Completion Date filter to "This Month"
3. Add "Show Result" action
4. Run the shortcut

**Expected Results:**
- ✅ Returns tasks completed from the 1st of the current month to now
- ✅ Tasks completed in previous months are excluded

**Pass Criteria:** "This Month" completion date filter works correctly

### Test 3.8: Filter by Completion Date - Custom Range (Task 14.4)

**Steps:**
1. Create a shortcut with "Transit: Find Tasks"
2. Set Completion Date filter to "Custom Range"
3. Observe the parameter display

**Expected Results:**
- ✅ "Completed From" date picker appears
- ✅ "Completed To" date picker appears
- ✅ Both date pickers are functional

**Pass Criteria:** Conditional parameters appear for custom range

### Test 3.9: Custom Range Date Filtering

**Steps:**
1. Create a shortcut with "Transit: Find Tasks"
2. Set Completion Date filter to "Custom Range"
3. Set "Completed From" to 7 days ago
4. Set "Completed To" to today
5. Add "Show Result" action
6. Run the shortcut

**Expected Results:**
- ✅ Returns only tasks completed within the specified range
- ✅ Tasks outside the range are excluded

**Pass Criteria:** Custom date range filtering works correctly

### Test 3.10: Filter by Last Changed Date - Today

**Steps:**
1. Change the status of at least one task today
2. Create a shortcut with "Transit: Find Tasks"
3. Set Last Changed filter to "Today"
4. Add "Show Result" action
5. Run the shortcut

**Expected Results:**
- ✅ Returns only tasks with status changes today
- ✅ Tasks changed on other days are excluded

**Pass Criteria:** "Today" last changed filter works correctly

### Test 3.11: Multiple Filters Combined (AND Logic)

**Steps:**
1. Create a shortcut with "Transit: Find Tasks"
2. Set multiple filters:
   - Project: "Mobile App"
   - Type: "Feature"
   - Status: "In Progress"
3. Add "Show Result" action
4. Run the shortcut

**Expected Results:**
- ✅ Returns only tasks matching ALL filters
- ✅ Tasks matching only some filters are excluded

**Pass Criteria:** Multiple filters use AND logic correctly

### Test 3.12: Empty Results Handling

**Steps:**
1. Create a shortcut with "Transit: Find Tasks"
2. Set filters that match no tasks (e.g., Status: "Abandoned" if you have none)
3. Add "Show Result" action
4. Run the shortcut

**Expected Results:**
- ✅ Shortcut succeeds (does NOT throw an error)
- ✅ Returns an empty array
- ✅ "Show Result" displays an empty list

**Pass Criteria:** Empty results return empty array, not error

### Test 3.13: TaskEntity Properties Accessibility (Task 14.5)

**Steps:**
1. Create a shortcut with "Transit: Find Tasks"
2. Add "Get Details of Shortcuts Input" action after Find Tasks
3. Observe available properties in the dropdown

**Expected Results:**
- ✅ Can access: Name
- ✅ Can access: Status
- ✅ Can access: Type
- ✅ Can access: Project Name
- ✅ Can access: Display ID
- ✅ Can access: Last Status Change Date
- ✅ Can access: Completion Date

**Pass Criteria:** All TaskEntity properties are accessible in Shortcuts

### Test 3.14: Result Limit (200 Tasks)

**Steps:**
1. If you have >200 tasks, create a shortcut with "Transit: Find Tasks"
2. Leave all filters empty
3. Add "Count" action to count results
4. Add "Show Result" action
5. Run the shortcut

**Expected Results:**
- ✅ Returns maximum of 200 tasks
- ✅ Results are the 200 most recently changed tasks

**Pass Criteria:** Results are limited to 200 tasks

---

## Test Suite 4: Enhanced Query Intent (Task 14.1)

### Test 4.1: Query Without Date Filters (Backward Compatibility - Task 15.1)

**Steps:**
1. Create a shortcut with "Transit: Query Tasks" (JSON-based intent)
2. Set Input parameter to:
   ```json
   {
     "status": "inProgress"
   }
   ```
3. Add "Show Result" action
4. Run the shortcut

**Expected Results:**
- ✅ Returns JSON string with tasks
- ✅ Only tasks with status "inProgress" are included
- ✅ No errors occur

**Pass Criteria:** Existing queries work without date filters

### Test 4.2: Query with Completion Date - Today

**Steps:**
1. Create a shortcut with "Transit: Query Tasks"
2. Set Input parameter to:
   ```json
   {
     "completionDate": {
       "relative": "today"
     }
   }
   ```
3. Add "Show Result" action
4. Run the shortcut

**Expected Results:**
- ✅ Returns JSON with tasks completed today
- ✅ Tasks completed on other days are excluded

**Pass Criteria:** Relative "today" filter works in JSON intent

### Test 4.3: Query with Completion Date - This Week

**Steps:**
1. Create a shortcut with "Transit: Query Tasks"
2. Set Input parameter to:
   ```json
   {
     "completionDate": {
       "relative": "this-week"
     }
   }
   ```
3. Add "Show Result" action
4. Run the shortcut

**Expected Results:**
- ✅ Returns JSON with tasks completed this week
- ✅ Tasks completed before this week are excluded

**Pass Criteria:** Relative "this-week" filter works in JSON intent

### Test 4.4: Query with Completion Date - This Month

**Steps:**
1. Create a shortcut with "Transit: Query Tasks"
2. Set Input parameter to:
   ```json
   {
     "completionDate": {
       "relative": "this-month"
     }
   }
   ```
3. Add "Show Result" action
4. Run the shortcut

**Expected Results:**
- ✅ Returns JSON with tasks completed this month
- ✅ Tasks completed in previous months are excluded

**Pass Criteria:** Relative "this-month" filter works in JSON intent

### Test 4.5: Query with Absolute Date Range

**Steps:**
1. Create a shortcut with "Transit: Query Tasks"
2. Set Input parameter to:
   ```json
   {
     "completionDate": {
       "from": "2026-02-01",
       "to": "2026-02-11"
     }
   }
   ```
3. Add "Show Result" action
4. Run the shortcut

**Expected Results:**
- ✅ Returns JSON with tasks completed between Feb 1-11, 2026
- ✅ Tasks outside this range are excluded
- ✅ Dates are interpreted in local timezone

**Pass Criteria:** Absolute date range filtering works correctly

### Test 4.6: Query with Only "From" Date

**Steps:**
1. Create a shortcut with "Transit: Query Tasks"
2. Set Input parameter to:
   ```json
   {
     "completionDate": {
       "from": "2026-02-01"
     }
   }
   ```
3. Add "Show Result" action
4. Run the shortcut

**Expected Results:**
- ✅ Returns tasks completed on or after Feb 1, 2026
- ✅ Tasks before this date are excluded

**Pass Criteria:** "From" date filter works without "to" date

### Test 4.7: Query with Only "To" Date

**Steps:**
1. Create a shortcut with "Transit: Query Tasks"
2. Set Input parameter to:
   ```json
   {
     "completionDate": {
       "to": "2026-02-11"
     }
   }
   ```
3. Add "Show Result" action
4. Run the shortcut

**Expected Results:**
- ✅ Returns tasks completed on or before Feb 11, 2026
- ✅ Tasks after this date are excluded

**Pass Criteria:** "To" date filter works without "from" date

### Test 4.8: Query with Last Status Change Date Filter

**Steps:**
1. Create a shortcut with "Transit: Query Tasks"
2. Set Input parameter to:
   ```json
   {
     "lastStatusChangeDate": {
       "relative": "today"
     }
   }
   ```
3. Add "Show Result" action
4. Run the shortcut

**Expected Results:**
- ✅ Returns tasks with status changes today
- ✅ Tasks changed on other days are excluded

**Pass Criteria:** Last status change date filter works correctly

### Test 4.9: Query with Both Date Filters

**Steps:**
1. Create a shortcut with "Transit: Query Tasks"
2. Set Input parameter to:
   ```json
   {
     "completionDate": {
       "relative": "this-week"
     },
     "lastStatusChangeDate": {
       "relative": "today"
     }
   }
   ```
3. Add "Show Result" action
4. Run the shortcut

**Expected Results:**
- ✅ Returns tasks matching BOTH filters
- ✅ Tasks must be completed this week AND changed today

**Pass Criteria:** Both date filters can be applied together

### Test 4.10: Query with Combined Status and Date Filters

**Steps:**
1. Create a shortcut with "Transit: Query Tasks"
2. Set Input parameter to:
   ```json
   {
     "status": "done",
     "completionDate": {
       "relative": "this-week"
     }
   }
   ```
3. Add "Show Result" action
4. Run the shortcut

**Expected Results:**
- ✅ Returns only "done" tasks completed this week
- ✅ All filters are applied with AND logic

**Pass Criteria:** Status and date filters work together

---

## Test Suite 5: Error Handling (Task 14.3)

### Test 5.1: Visual Intent - No Projects Error

**Covered in Test 2.5**

### Test 5.2: Visual Intent - Invalid Input

**Steps:**
1. Create a shortcut with "Transit: Add Task"
2. Use a variable or text field that could be empty
3. Run with empty name

**Expected Results:**
- ✅ Error message indicates invalid input
- ✅ Error includes recovery suggestion

**Pass Criteria:** Invalid input errors are clear and actionable

### Test 5.3: JSON Intent - Invalid Date Format

**Steps:**
1. Create a shortcut with "Transit: Query Tasks"
2. Set Input parameter to:
   ```json
   {
     "completionDate": {
       "from": "invalid-date"
     }
   }
   ```
3. Add "Show Result" action
4. Run the shortcut

**Expected Results:**
- ✅ Invalid date is ignored (filter not applied)
- ✅ Query returns results as if no date filter was specified
- ✅ No error is thrown

**Pass Criteria:** Invalid dates are gracefully ignored

### Test 5.4: JSON Intent - Empty Date Filter Object

**Steps:**
1. Create a shortcut with "Transit: Query Tasks"
2. Set Input parameter to:
   ```json
   {
     "completionDate": {}
   }
   ```
3. Add "Show Result" action
4. Run the shortcut

**Expected Results:**
- ✅ Empty filter object is ignored
- ✅ Query returns results as if no date filter was specified

**Pass Criteria:** Empty filter objects are ignored

---

## Test Suite 6: Backward Compatibility (Task 15)

### Test 6.1: Existing CreateTaskIntent (Task 15.2)

**Steps:**
1. Create a shortcut with "Transit: Create Task" (JSON-based)
2. Set Input parameter to:
   ```json
   {
     "name": "Legacy Task",
     "description": "Created via legacy intent",
     "type": "feature",
     "projectName": "Mobile App"
   }
   ```
3. Add "Show Result" action
4. Run the shortcut

**Expected Results:**
- ✅ Task is created successfully
- ✅ Returns JSON with task details
- ✅ JSON format matches existing format (no breaking changes)

**Pass Criteria:** Existing CreateTaskIntent works unchanged

### Test 6.2: Existing UpdateStatusIntent (Task 15.3)

**Steps:**
1. Note the display ID of an existing task (e.g., T-5)
2. Create a shortcut with "Transit: Update Status"
3. Set Input parameter to:
   ```json
   {
     "displayId": 5,
     "status": "inProgress"
   }
   ```
3. Add "Show Result" action
4. Run the shortcut

**Expected Results:**
- ✅ Task status is updated successfully
- ✅ Returns JSON with updated task details
- ✅ JSON format matches existing format

**Pass Criteria:** Existing UpdateStatusIntent works unchanged

### Test 6.3: Intent Names Unchanged (Task 15.4)

**Steps:**
1. Open Shortcuts app
2. Search for "Transit"
3. Verify intent names

**Expected Results:**
- ✅ "Transit: Query Tasks" (not renamed)
- ✅ "Transit: Create Task" (not renamed)
- ✅ "Transit: Update Status" (not renamed)
- ✅ "Transit: Add Task" (new)
- ✅ "Transit: Find Tasks" (new)

**Pass Criteria:** All existing intent names are unchanged

### Test 6.4: JSON Input/Output Formats (Task 15.5)

**Steps:**
1. Run tests 6.1, 6.2, and 4.1
2. Examine the JSON output format

**Expected Results:**
- ✅ QueryTasksIntent returns array of task objects with same structure
- ✅ CreateTaskIntent returns task object with same structure
- ✅ UpdateStatusIntent returns task object with same structure
- ✅ Error format remains: `{"error": "CODE", "message": "..."}`

**Pass Criteria:** All JSON formats are unchanged

---

## Test Completion Checklist

### Task 14.1: Test all three intents via Shortcuts interface
- [ ] AddTaskIntent (Tests 2.1-2.6)
- [ ] FindTasksIntent (Tests 3.1-3.14)
- [ ] Enhanced QueryTasksIntent (Tests 4.1-4.10)

### Task 14.2: Verify intent discoverability
- [ ] All 5 intents discoverable (Test 1.1)

### Task 14.3: Test error handling
- [ ] Visual intent errors (Tests 5.1-5.2)
- [ ] JSON intent error handling (Tests 5.3-5.4)

### Task 14.4: Test conditional parameter display
- [ ] Custom range date pickers appear (Test 3.8)

### Task 14.5: Verify TaskEntity properties accessible
- [ ] All properties accessible in Shortcuts (Test 3.13)

### Task 15.1: Test existing QueryTasksIntent
- [ ] Works without date filters (Test 4.1)

### Task 15.2: Test existing CreateTaskIntent
- [ ] Works with current JSON format (Test 6.1)

### Task 15.3: Test existing UpdateStatusIntent
- [ ] Works unchanged (Test 6.2)

### Task 15.4: Verify intent names unchanged
- [ ] All names verified (Test 6.3)

### Task 15.5: Verify JSON formats unchanged
- [ ] All formats verified (Test 6.4)

---

## Notes

- **Test Environment**: These tests should be performed on a physical iOS device or simulator running iOS 26+
- **Test Data**: Ensure you have sufficient test data (projects and tasks) before starting
- **Test Order**: Tests can be performed in any order, but creating test data first is recommended
- **Failures**: Document any failures with screenshots and error messages
- **Performance**: Note any performance issues, especially with the 200-task limit test

## Reporting Results

After completing all tests, update the task status in the task list:

```bash
rune update 14.1 --status completed
rune update 14.2 --status completed
rune update 14.3 --status completed
rune update 14.4 --status completed
rune update 14.5 --status completed
rune update 15.1 --status completed
rune update 15.2 --status completed
rune update 15.3 --status completed
rune update 15.4 --status completed
rune update 15.5 --status completed
```

Document any issues found in the decision log or create bug reports as needed.
