# Bugfix Report: Concurrent ID Promotion Can Overwrite Assigned IDs

**Date:** 2026-03-27
**Status:** In Progress
**Ticket:** T-597

## Description of the Issue

When the app launches or returns to the foreground, display ID promotion for provisional tasks and milestones can be triggered concurrently from multiple sources. This causes overlapping runs to fetch the same provisional records, allocate separate permanent IDs for each, and overwrite earlier assignments — wasting counter values and leaving records with unexpected IDs.

**Reproduction steps:**
1. Create a task or milestone while offline (gets a provisional ID)
2. Return online while the app transitions to active (triggers both ScenePhaseModifier and ConnectivityMonitor)
3. Observe that the record's permanent ID is higher than expected, with gaps in the sequence

**Impact:** Moderate. Skipped display IDs (e.g. T-5 never exists because it was overwritten by T-6) cause confusion. In the worst case, a record that was already promoted gets a second permanent ID, wasting the first one permanently.

## Investigation Summary

- **Symptoms examined:** Three independent call sites trigger `promoteProvisionalTasks` and `promoteProvisionalMilestones` without any mutual exclusion.
- **Code inspected:** `TransitApp.swift` (ScenePhaseModifier + onRestore wiring), `DisplayIDAllocator.swift`, `MilestoneService.swift`, `ConnectivityMonitor.swift`
- **Hypotheses tested:** Confirmed that there is no guard preventing overlapping promotion runs.

## Discovered Root Cause

**Defect type:** Race condition (missing single-flight guard)

**Why it occurred:** Three sites trigger promotion:
1. `ScenePhaseModifier.body` — `.task { ... }` on initial view appearance
2. `ScenePhaseModifier.body` — `.onChange(of: scenePhase == .active)` on foregrounding
3. `ConnectivityMonitor.onRestore` — when network connectivity is restored

All three call the same async promotion methods. Since these are async and run on MainActor, they can interleave at suspension points. When two runs overlap, both fetch the same provisional records before either has saved, leading to double ID allocation.

**Contributing factors:**
- `DisplayIDAllocator.promoteProvisionalTasks(in:)` and `MilestoneService.promoteProvisionalMilestones()` have no reentrancy guard
- `ConnectivityMonitor.onRestore` was typed as `@Sendable` instead of `@MainActor @Sendable`, causing a Swift 6.3 build error that masked the issue

## Resolution for the Issue

*To be filled after fix is implemented.*

## Regression Test

**Test file:** `Transit/TransitTests/ConcurrentPromotionTests.swift`

**What it verifies:**
- Sequential promotion calls don't waste IDs (second call is a no-op)
- The promotion guard resets after successful completion
- The promotion guard resets after save failure (allowing retry)
- Same invariants for both task and milestone promotion

**Run command:** `make test-quick` or `xcodebuild test ... -only-testing:TransitTests/ConcurrentPromotionTests`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Services/DisplayIDAllocator.swift` | Add `isPromoting` single-flight guard |
| `Transit/Transit/Services/MilestoneService.swift` | Add `isPromoting` single-flight guard |
| `Transit/Transit/Services/ConnectivityMonitor.swift` | Fix `onRestore` type to `@MainActor @Sendable` |
| `Transit/TransitTests/ConcurrentPromotionTests.swift` | Regression tests |

## Verification

**Automated:**
- [ ] Regression test passes
- [ ] Full test suite passes
- [ ] Linters/validators pass

## Prevention

**Recommendations to avoid similar bugs:**
- Any async method that should not overlap with itself needs a single-flight guard
- Use `@MainActor @Sendable` for closures that capture MainActor-isolated state and are called from non-isolated contexts

## Related

- T-449: Previous promotion rollback fix (related promotion code)
- T-597: This ticket
