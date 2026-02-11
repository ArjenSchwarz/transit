# Manual Testing: Task 14 - End-to-End Intent Testing

## Overview

Task 14 requires **manual testing** of the Shortcuts-friendly intents through the actual Shortcuts app on iOS/iPadOS/macOS. This cannot be fully automated as it requires human interaction with the Shortcuts UI.

## What Has Been Prepared

1. **Manual Testing Guide** (`manual-testing-guide.md`)
   - Comprehensive test cases for all three intents
   - Step-by-step instructions for each test scenario
   - Expected results and error cases
   - Troubleshooting tips

2. **Test Results Tracking** (`manual-testing-results.md`)
   - Checklist of all test cases
   - Space to record results, notes, and issues
   - Pre-testing verification status
   - Sign-off section

3. **App Build**
   - App builds successfully for macOS
   - All 5 intents are registered in TransitShortcuts
   - Ready to run and test

## How to Perform Manual Testing

### Step 1: Build and Run the App

```bash
# For macOS testing
make build-macos
open ~/Library/Developer/Xcode/DerivedData/Transit-*/Build/Products/Debug/Transit.app

# For iOS Simulator testing
make build-ios
# Then run from Xcode or use xcrun simctl
```

### Step 2: Set Up Test Data

1. Launch Transit app
2. Create 2-3 projects:
   - "Work"
   - "Personal"
   - "Side Project" (optional)
3. Create 5-10 test tasks with variety:
   - Different statuses (Idea, Planning, Spec, In Progress, Done, Abandoned)
   - Different types (Feature, Bug, Chore, Spike)
   - Assigned to different projects
   - Some with completion dates (mark a few as Done)

### Step 3: Open Shortcuts App

- **macOS:** Open Shortcuts.app from Applications
- **iOS:** Open Shortcuts app on device or simulator

### Step 4: Execute Test Cases

Follow the test cases in `manual-testing-guide.md` in order:

1. **14.1:** Test all three intents via Shortcuts interface
   - 14.1.1: AddTaskIntent (Transit: Add Task)
   - 14.1.2: FindTasksIntent (Transit: Find Tasks)
   - 14.1.3: QueryTasksIntent (Enhanced with date filtering)

2. **14.2:** Verify intent discoverability in Shortcuts app

3. **14.3:** Test error handling for all error cases

4. **14.4:** Test conditional parameter display (custom-range dates)

5. **14.5:** Verify TaskEntity properties are accessible in Shortcuts

### Step 5: Record Results

As you complete each test case, update `manual-testing-results.md`:
- Change status from ⏳ PENDING to ✅ PASS or ❌ FAIL
- Add notes about any observations or issues
- Record any bugs or unexpected behavior in the "Issues Found" section

### Step 6: Complete the Task

Once all test cases pass:

```bash
# Mark task 14 as complete
rune complete 14

# Commit the testing documentation
git add specs/shortcuts-friendly-intents/manual-testing-*.md
git commit -m "Complete task 14: End-to-end intent testing

- Created comprehensive manual testing guide
- Documented all test cases for AddTaskIntent, FindTasksIntent, QueryTasksIntent
- Verified intent discoverability, error handling, conditional parameters
- All manual tests passed (see manual-testing-results.md)"
```

## Important Notes

### Unit Test Failures

⚠️ There are currently some unit test failures. These are noted in `manual-testing-results.md`. Task 14 focuses on manual Shortcuts UI testing, so these failures don't block this task, but they should be investigated separately.

### What This Task Tests

Task 14 specifically tests:
- ✅ User-facing Shortcuts UI experience
- ✅ Intent discoverability and descriptions
- ✅ Parameter display and conditional parameters
- ✅ Error messages shown to users
- ✅ TaskEntity property accessibility in Shortcuts
- ✅ App opening behavior (foreground vs background)

Task 14 does NOT test:
- ❌ Unit-level logic (covered by unit tests)
- ❌ Integration with services (covered by integration tests)
- ❌ Code-level error handling (covered by unit tests)

### Backward Compatibility

Task 15 will specifically test backward compatibility. Task 14 includes some backward compatibility test cases (14.1.3-TC1), but the comprehensive backward compatibility verification is a separate task.

## Questions or Issues?

If you encounter any issues during manual testing:

1. Check the "Troubleshooting" section in `manual-testing-guide.md`
2. Record the issue in `manual-testing-results.md`
3. If it's a bug, it may need to be fixed before completing task 14
4. If it's a test environment issue, document it and continue with other tests

## Completion Criteria

Task 14 is complete when:

- [ ] All test cases in sections 14.1-14.5 have been executed
- [ ] Results are recorded in `manual-testing-results.md`
- [ ] All critical and major issues are resolved
- [ ] Minor issues are documented for future consideration
- [ ] Testing documentation is committed to the repository

---

**Current Status:** ⏳ IN PROGRESS - Awaiting manual testing execution

**Next Steps:** Execute manual test cases following `manual-testing-guide.md`
