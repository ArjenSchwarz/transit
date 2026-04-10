# Bugfix Report: safeRollback omits SyncHeartbeat re-fault

**Date:** 2026-04-10
**Status:** Fixed
**Ticket:** T-777

## Description of the Issue

`ModelContext.safeRollback()` re-faults all `@Model` entities after `rollback()` to work around a SwiftData bug where in-memory properties retain mutated values. However, `refaultAllEntities()` only fetched four entity types (Project, TransitTask, Comment, Milestone) and omitted `SyncHeartbeat`. After a rollback, loaded `SyncHeartbeat` instances could retain stale in-memory values.

**Reproduction steps:**
1. Load a `SyncHeartbeat` instance into a `ModelContext`
2. Mutate `lastBeat` in memory
3. Call `context.safeRollback()`
4. Observe that `lastBeat` retains the mutated value instead of reverting to the saved value

**Impact:** Low severity in practice since `SyncHeartbeat` is a singleton used only for triggering CloudKit sync cycles, but it violates the documented invariant that `safeRollback()` re-faults all entity types.

## Investigation Summary

- **Symptoms examined:** `refaultAllEntities()` listing vs actual `@Model` types in the schema
- **Code inspected:** `ModelContext+SafeRollback.swift`, `SyncHeartbeat.swift`, `TestModelContainer.swift`
- **Hypotheses tested:** Confirmed `SyncHeartbeat` was added after the original `safeRollback()` implementation and was never included in the re-fault list

## Discovered Root Cause

`SyncHeartbeat` was added as a new `@Model` entity but was not added to the `refaultAllEntities()` method, which has an explicit comment: "If you add a new `@Model` entity, add a fetch for it here."

**Defect type:** Missing entity registration

**Why it occurred:** The `SyncHeartbeat` model was added in a later feature, and the developer did not update `refaultAllEntities()` despite the comment.

**Contributing factors:** No compile-time enforcement that all `@Model` types are included in the re-fault list; relies on developer awareness of the comment.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/Extensions/ModelContext+SafeRollback.swift:30` - Added `_ = try? fetch(FetchDescriptor<SyncHeartbeat>())` to `refaultAllEntities()`

**Approach rationale:** Follows the exact same pattern used for the other four entity types. Minimal, targeted fix.

**Alternatives considered:**
- Automatic discovery of all model types from the container's schema at runtime - Over-engineered for a five-entity app; the explicit list is clear and maintainable

## Regression Test

**Test file:** `Transit/TransitTests/SafeRollbackTests.swift`
**Test name:** `safeRollbackRevertsSyncHeartbeatProperties`

**What it verifies:** After mutating `SyncHeartbeat.lastBeat` in memory and calling `safeRollback()`, the property reverts to its saved value.

**Run command:** `xcodebuild test -project Transit/Transit.xcodeproj -scheme Transit -destination 'platform=macOS' -only-testing:TransitTests/SafeRollbackTests/safeRollbackRevertsSyncHeartbeatProperties`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Extensions/ModelContext+SafeRollback.swift` | Added `SyncHeartbeat` fetch to `refaultAllEntities()` |
| `Transit/TransitTests/SafeRollbackTests.swift` | Added regression test for SyncHeartbeat re-faulting |

## Verification

**Automated:**
- [x] Regression test passes
- [x] Full test suite passes (4 pre-existing failures unrelated to this change)
- [x] Linters pass (1 pre-existing violation in MCPToolHandler.swift unrelated to this change)

## Prevention

**Recommendations to avoid similar bugs:**
- When adding a new `@Model` entity, search for `refaultAllEntities` and update it
- Consider adding a compile-time or test-time check that all `@Model` types in the schema are covered by `refaultAllEntities()`

## Related

- T-452: Original production-side `safeRollback()` implementation
- `docs/agent-notes/technical-constraints.md`: Documents the SwiftData rollback re-fault bug
