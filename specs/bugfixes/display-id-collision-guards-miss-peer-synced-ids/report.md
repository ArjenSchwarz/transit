# Bugfix Report: Display ID Collision Guards Miss Peer-Synced IDs

**Date:** 2026-08-03
**Status:** Investigating
**Ticket:** T-1939

## Description of the Issue

Display-ID allocation asks each caller for IDs already in use before accepting a counter candidate. Every production closure currently fetches through the shared main `ModelContext`. When that context has a registered `@Model` whose cached display ID predates a peer merge, the fetch can return the cached value instead of the newer committed row. A stale counter can then offer the peer-committed ID and the guard accepts it.

**Reproduction steps:**
1. Register a task or milestone carrying display ID 9 in the main context.
2. Through a peer context on the same store, commit display ID 10 for that UUID while the main registered object still reads 9 and has no pending changes.
3. Make the counter offer 10 during creation, provisional promotion, or duplicate repair.
4. Observe the existing main-context-only guard accept 10 and assign it to another record.

**Impact:** Task and milestone creation, provisional promotion, and duplicate repair can report success while creating a duplicate human-facing T-/M- identifier. SwiftData + CloudKit cannot enforce `@Attribute(.unique)`, so there is no downstream uniqueness constraint to reject the write.

## Investigation Summary

### Phase 1: Initial overview

- **Expected:** A candidate is blocked when either the committed local store, live/pending main-context state, or allocator-issued state already uses it.
- **Actual:** Caller closures supply only main-context fetch results; allocator-issued IDs are unioned separately inside `DisplayIDAllocator`.
- **Context:** The defect appears after a peer/CloudKit merge reaches the persistent store while a registered main-context model remains cached at its older value.

### Phase 2: Systematic inspection

- **Data-flow defect:** `UsedDisplayIDs` accepts one `ModelFetching` and treats that single view as authoritative.
- **Affected call sites:** `TaskService.createTask`, `MilestoneService.createMilestone`, `DisplayIDAllocator.promoteProvisionalTasks`, `MilestoneService.promoteProvisionalMilestones`, and both task/milestone branches of `DisplayIDMaintenanceService.reassignDuplicates`.
- **Existing compatible pattern:** `DisplayIDRecordLookup` uses a fresh transient `ModelContext(modelContext.container)` to bypass registered-object snapshots for T-1061/T-2019/T-2020 probes.
- **Preserved safeguards:** Allocation serialization and issued-ID reservation live inside `DisplayIDAllocator`; loser post-allocation re-probes, promotion precondition probes, cancellation checks, selective save recovery, single-flight maintenance guards, and throwing fetch semantics are independent and must remain unchanged.

### Phase 3: Root cause analysis

**Defect type:** Stale-context data-flow error.

**Five Whys:**
1. Why can a used ID be reissued? The collision set does not contain the committed candidate.
2. Why is it absent? The used-ID closure sees a registered object's cached pre-merge value.
3. Why does the closure trust that value? It fetches only through the main context.
4. Why is the main context insufficient? SwiftData can retain registered `@Model` values after another context commits a newer row, and it exposes no public per-object refresh API.
5. Why do existing transient probes not prevent this? They validate only the loser/provisional target, not unrelated bystanders that occupy the allocator candidate.

**Root cause:** Candidate blocking incorrectly treats one cached main-context view as the committed-store truth. The correct set must combine independent committed-store and live/pending views.

### Phase 4: Solution and verification plan

1. Make `UsedDisplayIDs` build each set from a fresh transient-context committed fetch unioned with the live/pending main-context fetch.
2. Preserve the injectable failing-fetch seam so either required view failing still fails closed as T-1621 requires.
3. Keep allocator `issuedIDs` unioning unchanged so uncommitted allocations remain reserved.
4. Route every affected creation, promotion, and maintenance call through the same helper.
5. Add deterministic stale-registered-bystander regressions for task and milestone creation, promotion, and repair.
6. Re-run T-1061/T-1621/T-1766/T-2019/T-2020, cancellation, rollback, and full unit/lint validation.

## Discovered Root Cause

`UsedDisplayIDs` reads only the registered main `ModelContext`. That context is the correct source for live/pending in-process values but is not a reliable source for peer-committed store values. Unrelated transient probes do not add bystander IDs to the allocation candidate set.

**Defect type:** Stale cache / missing authoritative store read.

**Contributing factors:** SwiftData has no uniqueness constraint under CloudKit and no public targeted refresh API; display-ID assignment spans a direct CloudKit counter and SwiftData model save.

## Resolution for the Issue

Pending implementation and green verification.

## Regression Test

**Test file:** `Transit/TransitTests/StaleRegisteredBystanderDisplayIDTests.swift`

**Test names:**
- `taskCreationBlocksPeerCommittedIDHiddenByStaleRegisteredBystander`
- `milestoneCreationBlocksPeerCommittedIDHiddenByStaleRegisteredBystander`
- `taskPromotionBlocksPeerCommittedIDHiddenByStaleRegisteredBystander`
- `milestonePromotionBlocksPeerCommittedIDHiddenByStaleRegisteredBystander`
- `taskRepairBlocksPeerCommittedIDHiddenByStaleRegisteredBystander`
- `milestoneRepairBlocksPeerCommittedIDHiddenByStaleRegisteredBystander`

**What they verify:** The fixture commits ID 10, then changes only the registered main-context bystander back to ID 9 without saving or refetching it. This is the established deterministic T-1061 stale-cache simulation and also exercises the required union with live/pending state. A counter offering 10 must skip to 11 on all six affected paths.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Services/UsedDisplayIDs.swift` | Planned shared committed + live/pending candidate-blocking set |
| `Transit/Transit/Services/TaskService.swift` | Planned task-creation wiring |
| `Transit/Transit/Services/MilestoneService.swift` | Planned milestone creation/promotion wiring |
| `Transit/Transit/Services/DisplayIDAllocator.swift` | Planned task-promotion wiring |
| `Transit/Transit/Services/DisplayIDMaintenanceService.swift` | Planned duplicate-repair wiring |
| `Transit/TransitTests/StaleRegisteredBystanderDisplayIDTests.swift` | Six deterministic regressions |
| `CHANGELOG.md` | Final behavior entry after verification |

## Verification

**Automated:**
- [x] Regressions fail before the fix (all six accepted ID 10; verified in the macOS xcresult bundle)
- [ ] Regressions pass after the fix
- [ ] Full macOS unit suite passes
- [ ] Relevant iOS/full suite passes
- [ ] Linters/validators pass

## Prevention

- Treat a registered main-context fetch as live/pending state, not as an authoritative committed-store snapshot.
- Centralize display-ID candidate blocking so every allocator caller combines the same state sources.
- Keep transient regression probes independent from the main context so tests do not accidentally refresh away the stale condition.

## Related

- T-1061 — transient committed loser probes.
- T-1395 — allocation serialization and allocator-issued ID reservation.
- T-1621 — used-ID fetch failures fail closed.
- T-1766 — maintenance collision guards.
- T-2019 — duplicate-repair post-allocation loser re-probe.
- T-2020 — promotion post-allocation provisional-state re-probe.
