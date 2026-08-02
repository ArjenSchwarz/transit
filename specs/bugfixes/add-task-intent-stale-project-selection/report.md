# Bugfix Report: AddTaskIntent Stale Project Selection

**Date:** 2026-08-02
**Status:** In Progress

## Description of the Issue

`AddTaskIntent` checks whether any projects exist before resolving the selected `ProjectEntity`. When a Shortcut retains a project entity whose project was deleted, and that project was the last project in Transit, the intent throws `VisualIntentError.noProjects` instead of the more useful `VisualIntentError.projectNotFound`.

**Reproduction steps:**
1. Create one project and select it in an Add Task Shortcut.
2. Delete that project so the database contains no projects.
3. Run the Shortcut with its saved project selection.
4. Observe that the intent reports `NO_PROJECTS` instead of `PROJECT_NOT_FOUND`.

**Impact:** A stale Shortcut receives incorrect recovery guidance. It tells the user to create a project rather than explaining that the selected project was deleted and needs to be replaced. No task should be created in this failure path.

## Investigation Summary

The selected entity, intent execution path, project resolver, callers, requirements, and existing tests were inspected line by line.

- **Symptoms examined:** stale selection with another project present, stale selection after deleting the last project, and an empty database with no usable selection.
- **Code inspected:** `AddTaskIntent.execute`, `ProjectEntity`, `ProjectEntityQuery`, `ProjectService.findProject`, all `AddTaskIntent.execute` callers, and `AddTaskIntentTests`.
- **Hypotheses tested:** the failure is not in task creation or entity serialization; the early project-count guard prevents the selected entity from reaching `ProjectService.findProject`.

### Systematic inspection findings

1. **Control-flow defect:** `AddTaskIntent.execute` calls `hasAnyProjects()` before resolving `project.projectId`.
2. **Boundary-condition defect:** the early guard collapses two distinct states when the project count is zero: no project was selected versus a selected project was deleted.
3. **Error-classification defect:** the stale entity cannot receive `projectNotFound`, even though `ProjectService.findProject` would correctly report that the UUID is absent.
4. **Mutation safety:** task creation occurs after project resolution, so the failure path currently creates no task; the regression test now asserts this explicitly.

## Discovered Root Cause

The no-project check has higher precedence than selected-entity resolution. Because the check observes only current database contents, it reports `noProjects` before the intent can determine whether the caller supplied a stale selection.

**Defect type:** Control-flow logic error and boundary-condition misclassification.

**Why it occurred:** The original implementation treated a required project parameter and an empty database as mutually exclusive, but did not account for persisted Shortcut parameters surviving deletion of their referenced project.

**Contributing factors:** `ProjectEntity` values are snapshots used by Shortcuts, while `ProjectService` resolves against current SwiftData state. A saved entity can therefore outlive its model record.

## Resolution for the Issue

<!-- Filled after the fix is implemented. -->

## Regression Test

**Test file:** `Transit/Transit/TransitTests/AddTaskIntentTests.swift`
**Test name:** `executeThrowsProjectNotFoundForStaleProjectSelection`

**What it verifies:** A stale selected entity throws the exact `.projectNotFound("Selected project no longer exists.")` case after the selected project was the only project and was deleted, and no task is created.

**Run command:** `make test-quick`

**Red checkpoint:** The tightened test failed before implementation because the actual error was `.noProjects`.

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/TransitTests/AddTaskIntentTests.swift` | Tightened stale-selection assertion and no-task assertion |
| `specs/bugfixes/add-task-intent-stale-project-selection/report.md` | Investigation report |

## Verification

**Automated:**
- [ ] Regression test passes
- [ ] Full test suite passes
- [ ] Linters/validators pass

**Manual verification:**
- Not yet performed.

## Prevention

- Resolve an explicitly supplied entity before classifying an empty current database.
- Keep separate regression coverage for a stale selected entity and true no-selection/empty-database behavior.
- Assert exact typed error cases and absence of mutations in intent failure tests.

## Related

- Transit T-1814
- `specs/shortcuts-friendly-intents/requirements.md` requirement 7.8
