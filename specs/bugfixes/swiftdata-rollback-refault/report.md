# Bugfix Report: SwiftData Rollback Re-fault

**Date:** 2025-07-14
**Status:** Fixed
**Ticket:** T-452

## Description of the Issue

After `ModelContext.rollback()`, `@Model` object properties retained their mutated in-memory values even though the persistent store was reverted. This affected all 13 production `rollback()` call sites across services, views, and the MCP handler.

**Reproduction steps:**
1. Mutate properties on a SwiftData `@Model` object (e.g., change task name, status)
2. Call `modelContext.save()` which fails
3. Call `modelContext.rollback()` in the error handler
4. Observe that in-memory properties still reflect the mutated values

**Impact:** High — users saw stale/mutated values in the UI after failed saves, making it appear the save succeeded when it didn't. Service callers received objects with incorrect state after rollback.

## Investigation Summary

- **Symptoms examined:** After `rollback()`, `hasChanges` correctly returned `false` and the persistent store was reverted, but `@Model` property accessors returned pre-rollback mutated values.
- **Code inspected:** All 13 production `rollback()` call sites in TaskService (4), MilestoneService (4), CommentService (2), TaskEditView (1), ProjectEditView (1), MCPToolHandler (1).
- **Hypotheses tested:** A `fetch()` after `rollback()` forces SwiftData to re-fault model objects, restoring correct in-memory property values. This was already proven in test code (PR #77).

## Discovered Root Cause

SwiftData's `ModelContext.rollback()` reverts the persistent store and clears dirty tracking (`hasChanges → false`), but does NOT re-fault `@Model` property accessors. The lazy property accessors continue to return cached mutated values from memory.

**Defect type:** Framework bug (SwiftData) — missing re-faulting on rollback

**Why it occurred:** SwiftData's rollback implementation clears the dirty flag but does not invalidate the in-memory property cache. This is analogous to Core Data's behaviour with unfaulted managed objects, but SwiftData doesn't expose the same re-faulting APIs.

**Contributing factors:** All 13 production rollback sites called `rollback()` directly without any post-rollback re-faulting, unlike the test code which had already been patched (PR #77).

## Resolution for the Issue

**Changes made:**
- `Transit/Extensions/ModelContext+SafeRollback.swift` — New `safeRollback()` extension method that calls `rollback()` followed by `fetch()` on all entity types to force re-faulting
- `Transit/Services/TaskService.swift` — 4 `rollback()` → `safeRollback()` replacements
- `Transit/Services/MilestoneService.swift` — 4 `rollback()` → `safeRollback()` replacements
- `Transit/Services/CommentService.swift` — 2 `rollback()` → `safeRollback()` replacements
- `Transit/Views/TaskDetail/TaskEditView.swift` — 1 `rollback()` → `safeRollback()` replacement
- `Transit/Views/Settings/ProjectEditView.swift` — 1 `rollback()` → `safeRollback()` replacement
- `Transit/MCP/MCPToolHandler.swift` — 1 `rollback()` → `safeRollback()` replacement
- `TransitTests/TestModelContainer.swift` — Simplified to delegate to production `safeRollback()`
- `TransitTests/CommentServiceTests.swift` — Updated test rollback call for consistency

**Approach rationale:** A single `ModelContext` extension method centralises the workaround, making it impossible to forget the re-faulting step when adding future rollback sites. The `fetch()` calls use `try?` so failures don't crash — worst case is the same behaviour as before (stale values), which is strictly no worse.

**Alternatives considered:**
- Snapshot-and-restore pattern (save property values before mutation, restore manually on error) — rejected as error-prone and requires maintaining snapshot logic for every property on every model
- Re-fetching individual affected objects by ID after rollback — rejected as fragile; callers would need to know which objects were mutated

## Regression Test

**Test file:** `TransitTests/SafeRollbackTests.swift`
**Tests:** 7 tests covering all entity types and multi-entity atomicity

**What it verifies:**
- `safeRollbackRevertsProjectProperties` — Project name, description, gitRepo, colorHex
- `safeRollbackRevertsTaskProperties` — Task name, description, type
- `safeRollbackRevertsTaskStatusChange` — Task status via StatusEngine
- `safeRollbackRevertsMilestoneProperties` — Milestone name, description, status
- `safeRollbackRevertsCommentDeletion` — Comment deletion is undone
- `safeRollbackRevertsMultipleEntityMutationsAtomically` — Cross-entity rollback
- `safeRollbackRevertsTaskMetadata` — Dictionary metadata rollback

**Run command:** `make test-quick` or `xcodebuild test -project Transit/Transit.xcodeproj -scheme Transit -destination 'platform=macOS' -only-testing:TransitTests/SafeRollbackTests test`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Extensions/ModelContext+SafeRollback.swift` | New — `safeRollback()` extension with re-faulting |
| `Transit/Services/TaskService.swift` | 4× `rollback()` → `safeRollback()` |
| `Transit/Services/MilestoneService.swift` | 4× `rollback()` → `safeRollback()` |
| `Transit/Services/CommentService.swift` | 2× `rollback()` → `safeRollback()` |
| `Transit/Views/TaskDetail/TaskEditView.swift` | 1× `rollback()` → `safeRollback()` |
| `Transit/Views/Settings/ProjectEditView.swift` | 1× `rollback()` → `safeRollback()` |
| `Transit/MCP/MCPToolHandler.swift` | 1× `rollback()` → `safeRollback()` |
| `TransitTests/TestModelContainer.swift` | Delegates to production `safeRollback()` |
| `TransitTests/CommentServiceTests.swift` | Uses `safeRollback()` for consistency |
| `TransitTests/SafeRollbackTests.swift` | New — 7 regression tests |

## Verification

**Automated:**
- [x] Regression test passes (7/7)
- [x] Full test suite passes (690/690)
- [x] Linters pass (0 violations)

## Prevention

**Recommendations to avoid similar bugs:**
- Always use `safeRollback()` instead of `rollback()` — consider adding a SwiftLint custom rule to flag bare `rollback()` calls
- When Apple fixes the SwiftData re-faulting bug, the `refaultAllEntities()` calls can be removed from `safeRollback()` without changing any call sites
- When adding new `@Model` entities, add a corresponding `fetch()` to `refaultAllEntities()` in `ModelContext+SafeRollback.swift`

## Related

- T-452: SwiftData rollback() does not re-fault @Model properties in production error handlers
- PR #77: Test-side workaround (TestModelContainer.rollback)
