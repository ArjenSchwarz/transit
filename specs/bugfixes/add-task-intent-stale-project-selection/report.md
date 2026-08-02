# Bugfix Report: AddTaskIntent Stale Project Selection

**Date:** 2026-08-02
**Status:** Fixed

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

**Changes made:**
- `Transit/Transit/Intents/Visual/AddTaskIntent.swift` — Keeps the visual intent's project parameter required at the App Intents boundary, while the testable execution path represents an absent selection explicitly. A nil selection throws `.noProjects` only when the database is empty and otherwise throws `.invalidInput`; a supplied entity is resolved through `ProjectService.findProject` before task creation. A stale entity therefore throws `.projectNotFound` even when the current project store is empty.
- `Transit/TransitTests/AddTaskIntentTests.swift` — Tightened stale-selection coverage to assert the exact associated enum value and verify that no task is persisted when the stale project was the only project or when another project remains. Updated the empty-database/no-selection test to assert exact `.noProjects` and verify that no task is persisted, and covered missing selection with existing projects as invalid input.
- `CHANGELOG.md` — Added the T-1814 fix to the Unreleased Fixed section.

**Approach rationale:** The App Intents parameter remains required, preserving the Shortcuts UI contract. The testable execution seam uses nil to represent an absent input: it reports `.noProjects` only when the store is empty and `.invalidInput` when projects exist. Resolving a supplied entity first preserves the identity of a stale Shortcut selection independently of how many projects remain. The existing task creation boundary remains after validation and resolution, so all failure cases are mutation-free.

**Alternatives considered:**
- Keep the early `hasAnyProjects()` guard and inspect the count after failure — rejected because an empty store cannot distinguish a deleted selected project from no selection.
- Infer selection state from `ProjectEntity.id`, `projectId`, or `name` — rejected because those are serialized entity fields and should not carry control-flow meaning beyond the selected entity's UUID.
- Add deletion tombstones to `ProjectService` — rejected because deletion can happen through sync or another context, and it would add state solely to compensate for an ambiguous API.

## Regression Test

**Test file:** `Transit/Transit/TransitTests/AddTaskIntentTests.swift`
**Test names:** `executeThrowsProjectNotFoundForStaleProjectSelection`, `executeThrowsProjectNotFoundForStaleProjectSelectionWhenAnotherProjectRemains`, `executeThrowsNoProjectsWhenDatabaseIsEmpty`, and `executeThrowsInvalidInputForMissingProjectWhenProjectsExist`

**What they verify:** A stale selected entity throws the exact `.projectNotFound("Selected project no longer exists.")` case both after the selected project was the only project and after another project remains, an absent selection in an empty store throws exact `.noProjects`, and an absent selection with existing projects throws exact `.invalidInput("Project is required.")`. Each failure path verifies that no task is created.

**Run command:** `make test-quick`

**Red checkpoint:** The tightened test failed before implementation because the actual error was `.noProjects`.

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Intents/Visual/AddTaskIntent.swift` | Distinguish nil selection from stale selected entity before creating a task |
| `Transit/TransitTests/AddTaskIntentTests.swift` | Exact error and no-mutation regressions for stale and empty selection cases |
| `CHANGELOG.md` | Unreleased T-1814 fix entry |
| `specs/bugfixes/add-task-intent-stale-project-selection/report.md` | Investigation, resolution, and verification record |

## Verification

**Automated:**
- [x] Regression tests pass — `executeThrowsProjectNotFoundForStaleProjectSelection` and `executeThrowsProjectNotFoundForStaleProjectSelectionWhenAnotherProjectRemains` assert the exact `.projectNotFound` value for stale selections with zero and remaining projects, `executeThrowsNoProjectsWhenDatabaseIsEmpty` asserts exact `.noProjects`, and `executeThrowsInvalidInputForMissingProjectWhenProjectsExist` asserts exact `.invalidInput`; all four verify no task creation.
- [x] Full macOS unit test suite passes — `make test-quick` result: 1,651 passed, 0 failed.
- [~] Full iOS test suite executed — 1,184 passed, 3 failed; the failures are the documented pre-existing iOS 26.5 UI baseline (`TransitUITests.testClearAll`, `TransitUITests.testEditViewPreservesTaskMilestone`, and `DataMaintenanceUITests.testDataMaintenanceGoldenPath`) and do not touch AddTaskIntent.
- [~] UI tests executed — 18 passed, 3 failed; the same documented baseline failures occurred, with no AddTaskIntent UI regression.
- [x] Linters/validators pass — `make lint` reports 0 violations and all ownership guard checks pass.
- [x] Builds pass for iOS and macOS — `make build` reports both Build Succeeded.

**Manual verification:**
- Not performed; automated tests cover both error classifications and mutation safety.

## Prevention

- Resolve an explicitly supplied entity before classifying an empty current database.
- Keep separate regression coverage for a stale selected entity and true no-selection/empty-database behavior.
- Assert exact typed error cases and absence of mutations in intent failure tests.

## Related

- Transit T-1814
- `specs/shortcuts-friendly-intents/requirements.md` requirement 7.8
