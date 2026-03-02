# Bugfix Report: Empty Project Names

**Date:** 2026-03-03
**Status:** Fixed

## Description of the Issue

`ProjectService.createProject` trims the name but never rejects an empty result. This allows programmatic callers (App Intents, future MCP) to create projects with blank names. Additionally, trimming used `.whitespaces` instead of `.whitespacesAndNewlines`, so newline characters in names were preserved.

**Reproduction steps:**
1. Call `ProjectService.createProject(name: "", ...)` or `name: "   "`
2. No error is thrown
3. A project with an empty or whitespace-only name is created

**Impact:** Data integrity -- blank project names are invalid and could cause display issues in the kanban board and confusing behaviour in project lookups.

## Investigation Summary

- **Symptoms examined:** `createProject` trimmed whitespace but had no guard against the empty result
- **Code inspected:** `ProjectService.swift`, `ProjectEditView.swift`, `TaskService.swift`, `MilestoneService.swift`, `MCPToolHandler.swift`, `IntentHelpers.swift`
- **Hypotheses tested:** Checked whether the UI or MCP layers had their own validation -- the UI's `canSave` property prevents empty names from the form, but the service layer was unguarded

## Discovered Root Cause

Missing input validation in `ProjectService.createProject`. The duplicate-name check passes for empty names (no existing project has an empty name), and the method proceeds to insert a project with a blank name.

**Defect type:** Missing validation

**Why it occurred:** The original implementation added duplicate-name prevention but did not consider the empty-name edge case. `TaskService` and `MilestoneService` both have `invalidName` guards, but `ProjectService` was not updated to follow the same pattern.

**Contributing factors:** Trimming used `.whitespaces` instead of `.whitespacesAndNewlines`, which was inconsistent with the other services and could allow newline-only names to pass even if an emptiness check had been added.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/Services/ProjectService.swift` - Added `invalidName` case to `ProjectMutationError`, changed trimming from `.whitespaces` to `.whitespacesAndNewlines`, added guard rejecting empty trimmed names in `createProject`, aligned `findProject` and `projectNameExists` trimming to `.whitespacesAndNewlines`
- `Transit/Transit/Views/Settings/ProjectEditView.swift` - Updated `canSave` and `save()` to use `.whitespacesAndNewlines`, split `catch is ProjectMutationError` into separate catches for `invalidName` and `duplicateName` with distinct error messages

**Approach rationale:** Follows the established pattern from `TaskService` and `MilestoneService` which both guard against empty names with `.whitespacesAndNewlines` trimming.

**Alternatives considered:**
- Silently returning without creating a project -- Rejected because throwing an error gives callers actionable feedback
- Adding validation only at the UI layer -- Rejected because programmatic callers (intents, MCP) would bypass it

## Regression Test

**Test file:** `Transit/TransitTests/ProjectServiceTests.swift`
**Test names:** `createProjectWithEmptyNameThrowsInvalidName`, `createProjectWithWhitespaceOnlyNameThrowsInvalidName`, `createProjectWithNewlinesOnlyNameThrowsInvalidName`, `createProjectTrimsWhitespaceAndNewlinesFromName`

**What it verifies:** Empty string, whitespace-only, and newline/tab-only names all throw `ProjectMutationError.invalidName`. Names with newlines surrounding valid content are trimmed correctly.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Services/ProjectService.swift` | Added `invalidName` error case, empty-name guard, `.whitespacesAndNewlines` trimming |
| `Transit/Transit/Views/Settings/ProjectEditView.swift` | Consistent trimming, separate error messages for `invalidName` vs `duplicateName` |
| `Transit/TransitTests/ProjectServiceTests.swift` | Four regression tests for empty/whitespace/newline name rejection and trimming |

## Verification

**Automated:**
- [x] Regression test written
- [ ] Full test suite passes (xcodebuild plugin issue prevents local test run -- CI will verify)
- [x] Linters/validators pass

**Manual verification:**
- Code review confirms the fix follows the same pattern used by `TaskService` and `MilestoneService`

## Prevention

**Recommendations to avoid similar bugs:**
- When adding CRUD operations to a service, include input validation for required string fields (empty check after trimming)
- Use `.whitespacesAndNewlines` consistently for all name trimming across services

## Related

- T-330: Prevent empty project names in ProjectService.createProject
