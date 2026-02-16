# Bugfix Report: Duplicate Projects

**Date:** 2026-02-16
**Status:** Fixed
**Ticket:** T-76

## Description of the Issue

Users could create multiple projects with the same name (including case-insensitive variants like "Transit" and "transit"). This led to duplicate entries in the project list and ambiguous project lookup results when referencing projects by name via App Intents or MCP.

**Reproduction steps:**
1. Open Settings and create a project named "Transit"
2. Create another project named "Transit" (or "transit")
3. Observe two projects with the same name in the project list

**Impact:** Medium -- duplicate projects cause confusion in the UI and break name-based project lookup (returns `.ambiguous` error) in App Intents and MCP tools.

## Investigation Summary

- **Symptoms examined:** Multiple projects with identical names appearing in the settings project list
- **Code inspected:** `ProjectService.createProject()`, `ProjectEditView.save()`, `Project` model, `SettingsView`, App Intents
- **Hypotheses tested:** Checked whether `@Attribute(.unique)` could be used on the name field (not possible with CloudKit), checked all call sites for project creation

## Discovered Root Cause

`ProjectService.createProject()` did not check for existing projects with the same name before inserting a new one. Similarly, `ProjectEditView.save()` did not validate the name when renaming an existing project.

**Defect type:** Missing validation

**Why it occurred:** The `Project` model cannot use SwiftData's `@Attribute(.unique)` on the name field because CloudKit does not support unique constraints. No alternative uniqueness check was implemented at the service layer.

**Contributing factors:** CloudKit compatibility constraints prevent database-level enforcement, so uniqueness must be checked in application code.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/Services/ProjectService.swift` -- Added `ProjectMutationError` enum with `.duplicateName` case. Made `createProject()` throw on duplicate names (case-insensitive, whitespace-trimmed). Added `projectNameExists(_:excluding:)` query method for both create and rename scenarios. `createProject()` now also trims whitespace from the name before persisting.
- `Transit/Transit/Views/Settings/ProjectEditView.swift` -- Added duplicate name validation for both create and edit flows. Shows an alert when a duplicate name is detected. Added `errorMessage` state and alert binding.

**Approach rationale:** Validation at the service layer prevents duplicates regardless of the entry point (UI, intents, MCP). The `projectNameExists(_:excluding:)` method supports both creation (no exclusion) and rename (exclude the project being edited) scenarios.

**Alternatives considered:**
- `@Attribute(.unique)` on `Project.name` -- Not possible with CloudKit compatibility
- Validation only in the view layer -- Would leave the service unprotected for programmatic callers

## Regression Test

**Test file:** `Transit/TransitTests/ProjectServiceTests.swift`
**Test names:**
- `createProjectWithDuplicateNameThrows` -- exact name match
- `createProjectWithDuplicateNameCaseInsensitiveThrows` -- case variant
- `createProjectWithDuplicateNameWhitespaceVariantThrows` -- whitespace padded
- `createProjectWithDifferentNameSucceeds` -- non-conflicting name
- `projectNameExistsReturnsTrueForExactMatch`
- `projectNameExistsReturnsTrueForCaseInsensitiveMatch`
- `projectNameExistsReturnsFalseWhenNoMatch`
- `projectNameExistsExcludesSpecifiedProject` -- rename scenario
- `projectNameExistsDetectsConflictWithOtherProject`
- `createProjectTrimsWhitespaceFromName`

**What it verifies:** That `createProject()` throws `ProjectMutationError.duplicateName` when a project with the same name (case-insensitive) already exists, and that `projectNameExists()` correctly detects conflicts while allowing exclusion for the rename case.

**Run command:** `xcodebuild test -project Transit/Transit.xcodeproj -scheme Transit -destination 'platform=macOS' -only-testing:TransitTests/ProjectServiceTests`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Services/ProjectService.swift` | Added `ProjectMutationError`, duplicate check in `createProject()`, `projectNameExists()` method |
| `Transit/Transit/Views/Settings/ProjectEditView.swift` | Added duplicate name validation and error alert for both create and edit flows |
| `Transit/TransitTests/ProjectServiceTests.swift` | Added 10 regression tests, updated existing tests for throwing `createProject()` |
| `Transit/TransitTests/CommentServiceTests.swift` | Fixed pre-existing `nil` for non-optional `description` parameter |
| `Transit/Transit/Intents/AddCommentIntent.swift` | Fixed pre-existing `private` access on `@Dependency` properties (unblocks test compilation) |
| `Transit/TransitTests/AddCommentIntentTests.swift` | Added missing `import AppIntents` (unblocks test compilation) |

## Verification

**Automated:**
- [x] Regression test passes (all 20 ProjectServiceTests pass)
- [x] Both iOS and macOS build successfully
- [x] Linters pass

**Manual verification:**
- Verified that the alert message correctly displays when attempting to create a duplicate project name

## Prevention

**Recommendations to avoid similar bugs:**
- When CloudKit prevents database-level uniqueness constraints, always add service-layer validation for fields that should be unique
- Consider adding a `validate()` method pattern to service classes that can be reused across different entry points (UI, intents, MCP)

## Related

- T-76: I can see duplicate projects
