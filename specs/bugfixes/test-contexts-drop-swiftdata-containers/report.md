# Bugfix Report: Test Contexts Drop Their SwiftData Containers

**Date:** 2026-08-01
**Status:** Fixed

## Description of the Issue

Test helpers create an in-memory SwiftData `ModelContainer` locally and return only its `ModelContext`. The context does not keep the backing container/store safely alive, so later model access can trap after ARC releases the container.

**Reproduction steps:**
1. Create a context with `TestModelContainer.newContext()` or one of the bespoke context-only helpers.
2. Let the helper return, dropping its local strong reference to the container.
3. Access or mutate a SwiftData model through the escaped context and observe an intermittent `SIGTRAP`/`EXC_BREAKPOINT` in SwiftData.

**Impact:** The unit-test host can crash nondeterministically, moving the apparent failure between unrelated tests and making the suite unreliable.

## Investigation Summary

The investigation followed the systematic debugger workflow.

- **Phase 1 — overview:** Expected every context to have a live in-memory store for the full test. Actual behavior allows the store owner to die when helper scope ends.
- **Phase 2 — inspection:** Inspected `TestModelContainer.swift`, all `newContext()` callers, `TaskEntityTests.swift`, `TaskCreationResultTests.swift`, `ReportLogicTestHelpers.swift`, context-only wrappers, and setup structs that retain contexts.
- **Phase 3 — root cause:** Ownership is erased at helper boundaries: containers are local variables while only contexts or models escape.
- **Phase 4 — solution:** Replace the bare-context API with a container-owning fixture, migrate all callers, consolidate bespoke helpers, and add a lifetime regression plus static call-site verification.

## Discovered Root Cause

A `ModelContext` was treated as if it owned its `ModelContainer`. It does not provide that lifetime guarantee. Helpers returned the context while the only strong container reference was a local variable, so ARC could release the persistent-store owner before the test finished.

**Defect type:** Data lifetime / ownership error

**Five Whys:**
1. Why did arbitrary SwiftData model access trap? The backing store was no longer valid.
2. Why was the store no longer valid? Its `ModelContainer` had been released.
3. Why was the container released? Helpers returned only `ModelContext`.
4. Why did this recur? Test support exposed a context-only API and suites copied that shape locally.
5. Why was it nondeterministic? ARC release timing and the next model access varied with test execution.

**Contributing factors:** More than 100 shared-helper calls, additional local wrappers, and fixtures that retained services/contexts but not their container owner.

## Resolution for the Issue

**Changes made:**
- `Transit/TransitTests/TestModelContainer.swift` — replaced `newContext()` with a fixture that owns both `ModelContainer` and `ModelContext`; created containers are centrally retained so temporary fixture extraction cannot orphan a store.
- `Transit/TransitTests/TestModelContainerLifetimeTests.swift` — added an API/lifetime regression covering model access through the owning fixture.
- `Transit/TransitTests/TaskEntityTests.swift`, `TaskCreationResultTests.swift`, and `ReportLogicTestHelpers.swift` — removed bespoke local-container/context-only factories and delegated to shared test support.
- 89 additional `TransitTests` files — migrated all remaining direct and wrapper-based context acquisition to `TestModelContainer`.
- `CLAUDE.md` and `docs/agent-notes/technical-constraints.md` — documented the owning-fixture rule and removed stale `newContext()` guidance.
- `scripts/validate_test_model_container_ownership.py`, `tests/validation/`, and `Makefile` — added an executable ownership boundary that rejects raw container construction/factories and proves unsafe bare, tuple, and environment forms fail while owning forms pass.

**Approach rationale:** A container-owning fixture preserves each test's isolated in-memory store while making ownership explicit at the call site. Central container retention is a defensive backstop for existing setup structs and the two size-constrained tests that extract a temporary fixture's context.

**Alternatives considered:**
- Return a `(ModelContainer, ModelContext)` tuple — callers can discard the container and recreate the bug.
- Wrap every test body in a closure — lifetime-safe but much more invasive, especially for setup structs that escape helper boundaries.
- Change production code — rejected because the defect is isolated to test fixture ownership.

## Regression Test

**Test file:** `Transit/TransitTests/TestModelContainerLifetimeTests.swift`
**Test name:** `escapedContextKeepsBackingContainerAvailableForItsFullUse`

**What it verifies:** A helper can let its local fixture go out of scope and return only the context; the centrally retained backing container remains available through subsequent model insertion and property access.

**Run command:** `make test-quick PIPE_PRETTY=`

## Affected Files

| File group | Change |
|------|--------|
| `Transit/TransitTests/TestModelContainer.swift` | Owning fixture API and defensive process-lifetime retention |
| `Transit/TransitTests/TestModelContainerLifetimeTests.swift` | Regression coverage |
| 92 migrated test/helper files | 207 context-acquisition call sites moved to the fixture API |
| `CLAUDE.md` | Updated test-infrastructure guidance |
| `docs/agent-notes/technical-constraints.md` | Corrected SwiftData container-lifetime rule |
| `.swiftlint.yml`, `Makefile`, `scripts/`, and `tests/` | Replaced the narrow regex with executable ownership validation and positive/negative fixtures |
| `CHANGELOG.md` | Recorded T-2003 fix |

## Verification

**Automated:**
- [x] Escaped-context regression passes as part of `make test-quick PIPE_PRETTY=`
- [x] Complete macOS unit suite passes via `make test-quick PIPE_PRETTY=`
- [x] `make lint` passes, including executable unsafe/owning fixtures and repository ownership validation
- [x] Ownership validation finds zero raw test `ModelContainer` construction outside `TestModelContainer`, or calls to removed `newContext()`/`newContainer()` APIs
- [ ] Full iOS scheme passes: all unit tests completed successfully, then unrelated UI tests `testClearAll` and `testEditViewPreservesTaskMilestone` failed and the runner hung retrying simulator launches with `DebuggerLLDB.DebuggerVersionStore.StoreError` / `no debugger version`; the hung run was terminated after preserving its log

**Manual verification:**
- Reviewed representative direct callers, helper wrappers, report fixtures, MCP setup, and all three ticket-named bespoke helpers.
- Confirmed the diff contains test support/tests/docs only; production sources are unchanged.

## Prevention

- Construct `TestModelContainer` at test/setup boundaries and derive its `context`; helpers should carry the fixture when practical.
- Keep `TestModelContainer`'s central retention backstop for setup structs that expose services/contexts without forwarding the fixture.
- Run `make lint`; it executes rule fixtures and rejects raw test container construction outside the retained fixture boundary.

## Related

- Transit T-2003
- `Flaky SwiftData test crashes from a non-retained ModelContainer.md`
