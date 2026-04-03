# Bugfix Report: Duplicate Milestone Display ID Detection

**Date:** 2026-04-03
**Status:** Fixed

## Description of the Issue

`MilestoneService.findByDisplayID(_:)` returned the first match without guarding against duplicate permanent display IDs. Because SwiftData + CloudKit cannot enforce unique constraints, duplicate milestone display IDs are possible in edge cases (e.g., concurrent creation during sync conflicts). Returning the first match causes non-deterministic behavior -- the caller may get a different milestone depending on the fetch order.

In contrast, `TaskService.findByDisplayID(_:)` already throws `.duplicateDisplayID` when multiple tasks share the same display ID, making this an inconsistency between the two services.

**Reproduction steps:**
1. Create two milestones with the same `permanentDisplayId` (possible via CloudKit sync conflict)
2. Call `MilestoneService.findByDisplayID` with that ID
3. Observe: the first match is returned silently instead of raising an error

**Impact:** Non-deterministic milestone resolution for intent/MCP callers; incorrect milestone could be updated or deleted.

## Investigation Summary

- **Symptoms examined:** `findByDisplayID` uses `.first` without counting results
- **Code inspected:** `MilestoneService.swift`, `TaskService.swift` (reference), `IntentHelpers.swift`, `MCPToolHandler.swift`, `CreateTaskIntent.swift`, `DeleteMilestoneIntent.swift`, `QueryMilestonesIntent.swift`
- **Hypotheses tested:** Single root cause -- missing guard on result count

## Discovered Root Cause

`MilestoneService.findByDisplayID` fetched milestones matching the display ID predicate but only checked for the first result via `guard let milestone = try modelContext.fetch(descriptor).first`, never inspecting how many records matched.

**Defect type:** Missing validation

**Why it occurred:** The milestone service was implemented after the task service but did not replicate the duplicate-detection guard that was added to `TaskService.findByDisplayID`.

**Contributing factors:** CloudKit cannot enforce unique constraints, so duplicate display IDs are possible during sync conflicts.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/Services/MilestoneService.swift` - Added `.duplicateDisplayID` error case; updated `findByDisplayID` to fetch all results and throw when count > 1 (mirrors `TaskService` pattern)
- `Transit/Transit/Intents/IntentHelpers.swift` - Mapped `.duplicateDisplayID` to `IntentError.internalError` in `mapMilestoneError`; added explicit catch in `resolveMilestone`
- `Transit/Transit/Intents/CreateTaskIntent.swift` - Catch `MilestoneService.Error` specifically and route through `mapMilestoneError`
- `Transit/Transit/Intents/DeleteMilestoneIntent.swift` - Catch `MilestoneService.Error` specifically and route through `mapMilestoneError`
- `Transit/Transit/Intents/QueryMilestonesIntent.swift` - Added explicit `duplicateDisplayID` catch returning error JSON
- `Transit/Transit/MCP/MCPToolHandler.swift` - Added `duplicateDisplayID` catches at all `findByDisplayID` call sites (create_task, update_task, query_tasks, query_milestones, resolveMilestone); extracted `lookupMilestoneByDisplayId` helper to reduce cyclomatic complexity

**Approach rationale:** Mirrors the existing `TaskService.findByDisplayID` pattern exactly, ensuring consistency across both services.

**Alternatives considered:**
- Deduplicating at the data layer (merging duplicates on detect) -- too complex for this scope and risks data loss
- Returning all matches and letting callers decide -- breaks the established single-result API contract

## Regression Test

**Test file:** `Transit/TransitTests/MilestoneServiceLookupTests.swift`
**Test name:** `findByDisplayIDThrowsForDuplicates`

**What it verifies:** When two milestones share the same `permanentDisplayId`, `findByDisplayID` throws `MilestoneService.Error.duplicateDisplayID` instead of returning the first match.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Services/MilestoneService.swift` | Added `duplicateDisplayID` error case; updated `findByDisplayID` to detect duplicates |
| `Transit/Transit/Intents/IntentHelpers.swift` | Mapped new error in `mapMilestoneError`; added catch in `resolveMilestone` |
| `Transit/Transit/Intents/CreateTaskIntent.swift` | Catch `MilestoneService.Error` for milestone resolution |
| `Transit/Transit/Intents/DeleteMilestoneIntent.swift` | Catch `MilestoneService.Error` for milestone resolution |
| `Transit/Transit/Intents/QueryMilestonesIntent.swift` | Added explicit `duplicateDisplayID` catch |
| `Transit/Transit/MCP/MCPToolHandler.swift` | Added `duplicateDisplayID` catches; extracted helper to reduce complexity |
| `Transit/TransitTests/MilestoneServiceLookupTests.swift` | Added regression test |
| `Transit/TransitTests/ModelContainerFallbackTests.swift` | Fixed pre-existing nil description bug |
| `Transit/TransitTests/QueryTasksIntentMilestoneTests.swift` | Fixed pre-existing wrong initializer arguments |

## Verification

**Automated:**
- [x] Regression test passes
- [x] Full test suite passes (731 tests, 0 failures)
- [x] Linters/validators pass (0 violations)

## Prevention

**Recommendations to avoid similar bugs:**
- When adding lookup-by-ID methods to new services, always include a duplicate guard (the CloudKit constraint gap affects all model types)
- Consider a shared protocol or base method for `findByDisplayID` across services to enforce consistent behavior

## Related

- T-687: Detect duplicate milestone display IDs in lookup
- `TaskService.findByDisplayID` -- reference implementation with duplicate detection
