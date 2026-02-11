# Quick Start: Manual Testing Guide

This guide helps you quickly set up and run manual tests for the Shortcuts-Friendly Intents feature.

## Prerequisites Setup

### 1. Build and Install Transit

**For macOS:**
```bash
make build-macos
# The app will be at: Transit/build/Build/Products/Debug/Transit.app
# Open it to install
open Transit/build/Build/Products/Debug/Transit.app
```

**For iOS Simulator:**
```bash
make build-ios
# The app will be installed on the simulator automatically
```

### 2. Create Test Data in Transit

Before testing, you need some baseline data:

1. **Open Transit app**
2. **Create at least 2 projects**:
   - "Test Project Alpha"
   - "Test Project Beta"
3. **Create test tasks** with variety:
   - Different types (Bug, Feature, Chore, Research, Documentation)
   - Different statuses (Idea, Planning, In Progress, Done)
   - Different dates (completed today, this week, last week)

**Quick test data script** (if you want to automate this):
- Create 5-10 tasks across different projects
- Complete 2-3 tasks today
- Complete 2-3 tasks earlier this week
- Leave 3-4 tasks in various active statuses

### 3. Open Shortcuts App

**macOS**: Open Shortcuts from Applications or Spotlight  
**iOS**: Open Shortcuts app from home screen

## Quick Test Scenarios

### Scenario 1: Basic Task Creation (5 minutes)

1. Create new shortcut
2. Add "Transit: Add Task" action
3. Fill in:
   - Name: "Quick Test Task"
   - Type: "Feature"
   - Project: Select any project
4. Run shortcut
5. **Expected**: Transit opens, task appears in Idea column

### Scenario 2: Task Search with Filters (5 minutes)

1. Create new shortcut
2. Add "Transit: Find Tasks" action
3. Set filters:
   - Type: "Feature"
   - Status: "In Progress"
4. Add "Show Result" action
5. Run shortcut
6. **Expected**: Returns filtered tasks, app stays in background

### Scenario 3: Date Filtering (5 minutes)

1. Create new shortcut
2. Add "Transit: Find Tasks" action
3. Set "Completion Date" to "Today"
4. Add "Show Result" action
5. Run shortcut
6. **Expected**: Returns only tasks completed today

### Scenario 4: Custom Date Range (5 minutes)

1. Create new shortcut
2. Add "Transit: Find Tasks" action
3. Set "Completion Date" to "Custom Range"
4. **Verify**: Date pickers appear
5. Set date range (e.g., last 7 days)
6. Run shortcut
7. **Expected**: Returns tasks within date range

### Scenario 5: Error Handling (3 minutes)

1. Delete all projects from Transit
2. Create shortcut with "Transit: Add Task"
3. Try to run it
4. **Expected**: Error message "No projects exist. Create a project in Transit first."

### Scenario 6: Backward Compatibility (5 minutes)

1. Create new shortcut
2. Add "Transit: Query Tasks" action (existing JSON intent)
3. Use JSON input:
   ```json
   {"type": "feature"}
   ```
4. Run shortcut
5. **Expected**: Returns JSON array of feature tasks (existing behavior)

## Testing Tips

### Verifying Intent Discoverability

1. In Shortcuts, tap "Add Action"
2. Search for "Transit"
3. You should see **5 intents**:
   - Transit: Add Task (new)
   - Transit: Find Tasks (new)
   - Transit: Query Tasks (existing, enhanced)
   - Transit: Create Task (existing)
   - Transit: Update Status (existing)

### Checking TaskEntity Properties

To verify TaskEntity properties are accessible:

1. Add "Transit: Find Tasks" action
2. Add "Get Details of Tasks" action
3. Tap on "Detail" and browse available properties
4. Should see: taskId, displayId, name, status, type, projectId, projectName, lastStatusChangeDate, completionDate

### Testing Conditional Parameters

The "Custom Range" option should show/hide date pickers dynamically:

1. Add "Transit: Find Tasks"
2. Set "Completion Date" to "Today" → No date pickers
3. Change to "Custom Range" → Date pickers appear
4. Change back to "This Week" → Date pickers disappear

## Common Issues and Solutions

### Issue: Intents don't appear in Shortcuts

**Solution**: 
- Rebuild the app: `make clean && make build-macos`
- Restart Shortcuts app
- On iOS, restart the device/simulator

### Issue: "No projects exist" error

**Solution**: Open Transit and create at least one project first

### Issue: Date filters return unexpected results

**Solution**: 
- Check device timezone settings
- Verify task dates in Transit app
- Remember: "This Week" starts from the first day of the week (locale-dependent)

### Issue: App doesn't open after "Add Task"

**Solution**: This is expected behavior - "Add Task" uses `.foreground` mode and should open the app. If it doesn't, check app permissions.

### Issue: App opens after "Find Tasks"

**Solution**: This is a bug - "Find Tasks" should run in `.background` mode only. Report this issue.

## Full Testing Checklist

For comprehensive testing, see: `docs/manual-testing-checklist.md`

This includes all 50 test cases covering:
- Intent discoverability (5 tests)
- Add Task intent (7 tests)
- Find Tasks intent (14 tests)
- Query Tasks intent (7 tests)
- Backward compatibility (4 tests)
- Error handling (throughout)

## Reporting Results

After testing, update the checklist with:
- ✅ Pass / ❌ Fail for each test
- Notes on any issues found
- Screenshots of errors (if any)

Mark task 14.1 as complete in rune:
```bash
rune complete 14.1
```

## Next Steps

After completing manual testing:
- Task 14.2: Verify intent discoverability ✅ (covered in checklist)
- Task 14.3: Test error handling ✅ (covered in checklist)
- Task 14.4: Test conditional parameters ✅ (covered in checklist)
- Task 14.5: Verify TaskEntity properties ✅ (covered in checklist)

All subtasks of 14 are covered in the manual testing checklist.
