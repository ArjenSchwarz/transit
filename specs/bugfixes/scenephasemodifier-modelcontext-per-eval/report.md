# Bugfix Report: ScenePhaseModifier Creates New ModelContext Per Body Evaluation

**Date:** 2026-02-20
**Status:** Fixed

## Description of the Issue

`ScenePhaseModifier` in `TransitApp.swift` was constructed inline in the `body` computed property with `ModelContext(container)` as an argument. Since `body` is a computed property on a value type (`App` struct), SwiftUI re-evaluates it on every state change, creating a new `ModelContext` each time. This separate context was also different from the one shared by `TaskService`, `ProjectService`, `CommentService`, and `ConnectivityMonitor`, leading to potential context mismatch issues where promoted display IDs might not be immediately visible to the services.

**Reproduction steps:**
1. Any state change in `TransitApp` triggers `body` re-evaluation
2. Each evaluation constructs `ModelContext(container)` inline
3. `ScenePhaseModifier` uses this transient context for `promoteProvisionalTasks`
4. Promotions write to a context separate from the services' shared context

**Impact:** Wasted allocations on every body evaluation, and potential data visibility issues between the promotion context and the services' shared context.

## Investigation Summary

- **Symptoms examined:** `TransitApp.body` at line 102 passed `ModelContext(container)` inline to `ScenePhaseModifier`, creating a new context per evaluation.
- **Code inspected:** `TransitApp.swift` (init and body), `DisplayIDAllocator.promoteProvisionalTasks(in:)`, `ScenePhaseModifier`.
- **Hypotheses tested:** Confirmed that the `ModelContext` created in `init()` at line 46 is passed to all services but was not stored as a property, so it could not be referenced in `body`.

## Discovered Root Cause

The `ModelContext` created in `TransitApp.init()` was only stored as a local variable `context` and passed to the services. It was not retained as a property on `TransitApp`. When `ScenePhaseModifier` needed a context in `body`, a new `ModelContext(container)` was constructed inline rather than reusing the existing shared one.

**Defect type:** Resource waste and context isolation mismatch.

**Why it occurred:** The shared `ModelContext` was not promoted to a stored property during initial implementation, so it could not be referenced from `body`.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/TransitApp.swift` -- Added `private let sharedModelContext: ModelContext` property. Assigned the existing `context` local from `init()` to this property. Changed the `ScenePhaseModifier` construction in `body` from `modelContext: ModelContext(container)` to `modelContext: sharedModelContext`.

**Approach rationale:** The services, connectivity monitor, and now `ScenePhaseModifier` all share a single `ModelContext`. This ensures promotions are immediately visible to all consumers and eliminates per-evaluation allocations.

**Alternatives considered:**
- Using `container.mainContext` -- rejected because this is a different context from the one services use, so it would still cause a mismatch
- Using `@State` in `ScenePhaseModifier` -- rejected because `ScenePhaseModifier` is a `ViewModifier` value type that receives its context from outside; the root problem is at the call site, not in the modifier itself

## Regression Test

**Test file:** `Transit/TransitTests/SharedContextPromotionTests.swift`
**Test names:** `promotionOnSharedContextIsVisibleToService`, `promotionOnSeparateContextIsNotImmediatelyVisibleToService`

**What it verifies:** That display ID promotion on a shared context is immediately visible to code using that same context, and that promotion on a separate context is NOT visible to the original context's in-memory objects (demonstrating why the bug was problematic).

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/TransitApp.swift` | Store shared `ModelContext` as property, pass to `ScenePhaseModifier` |
| `Transit/TransitTests/SharedContextPromotionTests.swift` | New regression test suite for shared vs separate context promotion |

## Verification

**Automated:**
- [x] Regression test passes
- [x] Full test suite passes (pre-existing unrelated build issue in `ProjectServiceTests.swift` excluded)
- [x] Linters/validators pass

**Manual verification:**
- Build succeeds on macOS and iOS

## Prevention

**Recommendations to avoid similar bugs:**
- When constructing objects in SwiftUI `body`, avoid creating new instances of reference types like `ModelContext` -- these should be stored as properties or injected
- Consider a code review checklist item for `ModelContext(container)` appearing inside `body` or `View` structs

## Related

- Transit ticket: T-158
