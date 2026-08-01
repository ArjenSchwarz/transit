# Bugfix Report: Test Contexts Drop Their SwiftData Containers

**Date:** 2026-08-01
**Status:** Investigating

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

Pending implementation.

## Regression Test

**Test file:** `Transit/TransitTests/TestModelContainerLifetimeTests.swift`
**Test name:** `fixtureRetainsBackingContainerForItsFullUse`

**What it verifies:** The backing container remains available while the escaped context and its models are still in use.

**Run command:** `make test-quick`

## Affected Files

Pending implementation inventory.

## Verification

**Automated:**
- [ ] Regression test passes
- [ ] Full test suite passes
- [ ] Linters/validators pass
- [ ] No unsafe context-only helper calls remain

**Manual verification:**
- Review every migrated fixture/helper to confirm container ownership crosses the same boundary as its context.

## Prevention

- Expose one test-support fixture that owns both `ModelContainer` and `ModelContext`.
- Do not add helpers that return a bare `ModelContext` created from a local container.
- Keep a regression/static inventory that makes reintroduction visible.

## Related

- Transit T-2003
- `Flaky SwiftData test crashes from a non-retained ModelContainer.md`
