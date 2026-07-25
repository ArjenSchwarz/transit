# Bugfix Report: Invariant Helpers Swallow Fetch Failures

**Date:** 2026-07-26
**Status:** Fixed
**Tickets:** T-1614 (name uniqueness), T-1621 (used display IDs)

## Description of the Issue

Five service-layer helpers derive an invariant from a SwiftData fetch and wrote that fetch as
`(try? modelContext.fetch(...)) ?? []`. A storage failure therefore produced the same value as
a genuinely empty store, and every caller read it as an authoritative negative answer:

| Helper | Answer on fetch failure | What the caller then did |
|---|---|---|
| `ProjectService.projectNameExists` | `false` — "name is free" | `createProject` / `updateProject` committed a duplicate project name |
| `MilestoneService.milestoneNameExists` | `false` — "name is free" | `createMilestone` / `updateMilestone` committed a duplicate milestone name in the project |
| `TaskService.usedDisplayIDs` | `[]` — "no IDs in use" | `allocateNextID`'s collision guard never fired; a stale counter candidate was accepted |
| `MilestoneService.usedDisplayIDs` | `[]` | same, for milestone creation and promotion |
| `DisplayIDAllocator.usedTaskDisplayIDs(in:)` | `[]` | same, for `promoteProvisionalTasks` |

Both groups are load-bearing precisely because there is nothing underneath them.
CloudKit-backed SwiftData forbids `@Attribute(.unique)` (CLAUDE.md, "Key Technical
Constraints"), so these checks *are* the uniqueness invariants for project names, milestone
names, and permanent display IDs.

**Reproduction steps (name uniqueness, T-1614):**

1. A project named "Transit" exists.
2. The duplicate-check fetch inside `projectNameExists` fails while the context can still
   insert and save.
3. `createProject(name: "transit", ...)` reads "no duplicate", inserts, and saves.
4. Two projects now differ only in case. `findProject(name:)` reports `.ambiguous` from then
   on, so every name-addressed automation call against that project fails.

**Reproduction steps (display IDs, T-1621):**

1. A task holds permanent display ID 5.
2. The CloudKit counter reads back a stale `nextDisplayID` of 5 (ordinary eventual
   consistency, or a counter whose writes are not yet visible).
3. The `usedDisplayIDs` fetch fails, so the `excluding:` snapshot is empty.
4. `allocateNextID` sees no collision, hands back 5, and a second T-5 is saved.

**Impact:** Medium severity, silent and persistent. Both failure modes corrupt data the app
then cannot address unambiguously — duplicate project/milestone names break name-based lookup
for MCP and App Intents callers; duplicate display IDs break `findByDisplayID`
(`Error.duplicateDisplayID`) and need the duplicate-cleanup maintenance flow to repair.
Nothing is reported at the time of the write: the caller sees success.

The two tickets were fixed together because they are the same defect shape, they overlap in
`MilestoneService.swift`, and T-1621 changes the `excluding:` closure type that T-1614's
`createMilestone` path also touches. Fixing them separately would have produced two different
error-propagation designs in one file.

## Investigation Summary

- **Symptoms examined:** `(try? fetch) ?? []` / `guard let ... else { return [] }` in five
  helpers, and what each caller concludes from the resulting value.
- **Code inspected:**
  - `Transit/Transit/Services/ProjectService.swift` — `projectNameExists`, `createProject`,
    `updateProject`
  - `Transit/Transit/Services/MilestoneService.swift` — `milestoneNameExists`,
    `usedDisplayIDs`, `createMilestone`, `updateMilestone`, `promoteProvisionalMilestones`
  - `Transit/Transit/Services/TaskService.swift` — `usedDisplayIDs`, `createTask`
  - `Transit/Transit/Services/DisplayIDAllocator.swift` — `allocateNextID` / `allocateLocked`
    (the `usedIDs` contract) and `promoteProvisionalTasks`
  - `Transit/Transit/Services/DisplayIDRecordLookup.swift`,
    `DisplayIDMaintenanceService.swift` — the maintenance copies of the used-ID read
  - `Transit/Transit/MCP/MCPToolHandler.swift`,
    `Transit/Transit/Intents/UpdateMilestoneIntent.swift` — the two external callers of
    `milestoneNameExists`
- **Hypotheses tested and ruled out:**
  - *A database constraint backs the name checks.* No. SwiftData + CloudKit cannot express
    `@Attribute(.unique)`, so the service check is the entire invariant.
  - *The counter-advance fence makes the used-ID snapshot redundant.* No — established during
    T-1766: the fence and the allocation are two separate counter reads, and a stale read
    between them lands back inside the occupied range.
  - *The allocator's in-process `issuedIDs` set covers the gap.* No. It only tracks IDs handed
    out during this launch; IDs already sitting on records are exactly what `usedIDs` reports.
  - *A failing fetch implies a failing save, so the mutation would be rejected anyway.* No.
    The failures are per-query (a faulting error, a partially migrated entity, a predicate
    that cannot be evaluated), and the regression tests exercise the dangerous combination
    directly: the invariant read fails while insert and save succeed.

## Discovered Root Cause

`try?` erases the distinction between "the store answered, and the answer is nothing" and
"the store did not answer". Both helper families then chose the *permissive* reading of that
ambiguous value — `false` for "does this name exist", `[]` for "which IDs are taken" — which
is precisely the reading that lets the guarded mutation proceed.

**Defect type:** Swallowed error / failure-mode conflation (fail-open rather than fail-safe).

**Why it occurred:** The helpers return non-optional value types (`Bool`, `Set<Int>`) whose
signatures have no room to express "unknown". Staying non-throwing kept the call sites terse
(`guard !milestoneNameExists(...)`, `excluding: { self.usedDisplayIDs() }`) and the degraded
value looks harmless in isolation. The danger only appears one level up, at the mutation the
value is guarding.

**Contributing factors:**

- The two fixes that most recently hardened these paths inherited the weakness rather than
  removing it. T-1764 (PR #188) added a post-allocation re-check of `milestoneNameExists` to
  close a TOCTOU window — a re-check no stronger than the helper it calls. T-1766 (PR #186)
  fixed duplicate cleanup reassigning onto an in-use ID by passing used-ID closures, and
  deliberately copied the existing `try?` behaviour so all call sites matched; its report
  flagged that on a fetch failure the maintenance path degrades to exactly the pre-fix
  behaviour and left the swallowed error to T-1621.
- `allocateNextID(excluding:)` defaults `usedIDs` to `{ [] }`, so "no collision protection"
  is already the shape of a legitimate call — an empty set produced by a failure is
  indistinguishable from an ordinary caller opting out.

## Resolution for the Issue

One approach applied uniformly to all five helpers: **make the read throwing and propagate the
error to the caller, which turns it into a normal failure response.** No helper converts a
storage failure into a value.

**Changes made:**

- `Transit/Transit/Services/ModelFetching.swift` (new) — a narrow `@MainActor` protocol over
  `ModelContext.fetch<T>(_:)` that `ModelContext` conforms to directly. It is the seam the
  invariant reads go through, so tests can inject a failing store without a broken
  `ModelContainer`. Follows the `TaskFetching` / `MilestoneFetching` precedent from T-1566.
- `Transit/Transit/Services/UsedDisplayIDs.swift` (new) — one throwing implementation of the
  committed-display-ID snapshot for tasks and milestones, replacing four near-identical copies
  (`TaskService`, `MilestoneService`, `DisplayIDAllocator`, `DisplayIDRecordLookup`).
- `Transit/Transit/Services/DisplayIDAllocator.swift` — `excluding:` is now
  `@MainActor @Sendable () throws -> Set<Int>`. When it throws, `allocateLocked` fails the
  allocation with a new `Error.usedIDLookupFailed(description:)` rather than continuing against
  an unevaluated guard. `promoteProvisionalTasks` gained an injectable `usedTaskIDs:` closure
  (defaulting to `UsedDisplayIDs(context).tasks()`); its private static probe is gone.
- `Transit/Transit/Services/TaskService.swift`, `MilestoneService.swift` — the private
  `usedDisplayIDs()` copies are gone; both use `UsedDisplayIDs`. `createTask` and
  `createMilestone` catch `usedIDLookupFailed` **before** the provisional fallback and rethrow
  it: a provisional ID is the app's answer to *CloudKit being unreachable*, not to the local
  store being unreadable, and using it here would hide the failure behind a normal-looking
  create.
- `Transit/Transit/Services/ProjectService.swift`, `MilestoneService.swift` —
  `projectNameExists` and `milestoneNameExists` are `throws`; `createProject`, `updateProject`,
  `createMilestone` (both the initial check and the T-1764 re-check) and `updateMilestone` call
  them with `try`, so a storage failure aborts the mutation.
- `Transit/Transit/Services/DisplayIDRecordLookup.swift`, `DisplayIDMaintenanceService.swift` —
  the two used-ID copies moved to `UsedDisplayIDs`; maintenance reports the failure as an
  existing `.allocationFailed` group failure and leaves the loser's ID untouched.
- `Transit/Transit/MCP/MCPToolHandler.swift`,
  `Transit/Transit/Intents/UpdateMilestoneIntent.swift` — the two external
  `milestoneNameExists` callers now distinguish "name is taken" from "could not check". The
  intent returns `INTERNAL_ERROR`; MCP returns an error result. Both checks were extracted into
  a `milestoneRenameConflict` / `renameConflict` helper, because inlining the `do`/`catch`
  pushed the enclosing validators past SwiftLint's cyclomatic-complexity limit.

**Approach rationale:** Making the helpers throwing is the only change that removes the
ambiguity at its source. Every alternative (an optional, an enum, a sentinel value) still
requires each caller to remember to handle a third state, which is the habit that produced the
bug in the first place. Propagating rather than defaulting also matches the precedent this
project already set for storage failures reaching automation callers: T-1566's JSON query
intents return `INTERNAL_ERROR` rather than a plausible-looking empty array, and PR #181's
`PersistenceAvailability` work refuses writes rather than reporting a success that will not
survive a relaunch.

Consolidating the four used-ID copies into `UsedDisplayIDs` was necessary rather than cosmetic:
with four implementations the throwing contract would have had four places to drift, and
`TaskService.swift` sat at 394 of SwiftLint's 400-line limit, so new code had to displace
something rather than be appended (precedent: `CloudKitCounterStore` in PR #182,
`DisplayIDRecordLookup` in PR #186).

**Alternatives considered:**

- **Return `Bool?` / `Set<Int>?` and let callers decide.** Rejected: it preserves the third
  state that callers must remember to handle, and `nil` reads as absence just as easily as
  `[]` does.
- **Keep the helpers non-throwing but fail *closed* (report `true`, or a "poisoned" ID set).**
  Rejected: it converts a storage failure into a wrong but plausible domain error
  (`duplicateName`) that a caller cannot distinguish from a genuine conflict, and retry logic
  would loop on a phantom duplicate.
- **Let `createTask` / `createMilestone` fall back to a provisional ID when the used-ID read
  fails.** Rejected: it is safe for the *duplicate-ID* invariant (a provisional ID cannot
  collide) but it silently converts an unreadable local store into an offline-looking create,
  and the record then carries no display ID until a promotion pass that fails the same way.
- **Fix T-1614 and T-1621 separately.** Rejected — see the pairing rationale above.
- **`// swiftlint:disable file_length` on `TaskService.swift`.** Rejected: suppressing the
  limit rather than addressing it.

**Explicitly out of scope:** T-1926 (making `allocateNextID`'s `excluding:` parameter
required). Not implemented here; see *Prevention* for how this change interacts with it.

## Regression Test

**Test file:** `Transit/TransitTests/FetchFailureInvariantTests.swift`

**Test names:**

- `projectCreateWithUnreadableStoreDoesNotCommitDuplicateName`
- `projectRenameWithUnreadableStoreDoesNotCommitDuplicateName`
- `milestoneCreateWithUnreadableStoreDoesNotCommitDuplicateName`
- `milestoneRenameWithUnreadableStoreDoesNotCommitDuplicateName`
- `taskCreateWithUnreadableStoreDoesNotReissueCommittedDisplayID`
- `milestonePromotionWithUnreadableStoreDoesNotReissueCommittedDisplayID`
- `taskPromotionWithUnreadableStoreDoesNotReissueCommittedDisplayID`
- `taskCreateWithReadableStoreStillSkipsPastTheInUseID` (control)
- `taskPromotionWithReadableStoreStillPromotesPastTheInUseID` (control)

**What they verify:** every test asserts at the *caller*, not at the helper. Asserting that a
helper throws would miss the point of the bug entirely, which is what the caller does with the
answer.

- The four T-1614 tests assert that a create or rename against a failing duplicate check throws
  **and** that the store still holds exactly one record with that name.
- The three T-1621 tests park the counter on an ID a record already holds
  (`InMemoryCounterStore(initialNextDisplayID: 5)` against a committed `-5`) and assert that
  with an unreadable used-ID snapshot the allocation fails and no second record ends up holding
  5. All three consumers are covered: `TaskService` (create), `MilestoneService` (promotion,
  which never touches the name check, so the used-ID read is the only thing broken), and
  `DisplayIDAllocator`'s own committed-ID probe (via the injected `usedTaskIDs:` closure).
- The two controls run the identical scenario with a working fetch and assert the allocator
  still advances past the occupied ID (5 to 6), so the fix did not convert a live path into a
  failure path.

**The seam:** `FailingFetcher` is a `ModelFetching` whose every fetch throws. It is injected
into the service under test while inserts and saves still go to the real in-memory context —
deliberately, because a fetcher that also broke saving would mask the bug. The pre-fix
behaviour needs exactly this combination: the guard read fails, the write succeeds, and nothing
surfaces.

**Run command:**

```bash
make test-quick
# or, focused:
xcodebuild test -project Transit/Transit.xcodeproj -scheme Transit \
  -destination 'platform=macOS' \
  -only-testing:TransitTests/FetchFailureInvariantTests test
```

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Services/ModelFetching.swift` | New — `@MainActor` seam over `ModelContext.fetch`; `ModelContext` conforms directly |
| `Transit/Transit/Services/UsedDisplayIDs.swift` | New — single throwing implementation of the committed-display-ID snapshot for tasks and milestones |
| `Transit/Transit/Services/DisplayIDAllocator.swift` | `excluding:` is throwing; new `Error.usedIDLookupFailed`; `promoteProvisionalTasks` takes an injectable `usedTaskIDs:`; private static probe removed |
| `Transit/Transit/Services/TaskService.swift` | Uses `UsedDisplayIDs`; `createTask` rethrows `usedIDLookupFailed` instead of falling back to provisional; injectable `fetcher:` |
| `Transit/Transit/Services/MilestoneService.swift` | `milestoneNameExists` throws; uses `UsedDisplayIDs`; both `createMilestone` name checks and the `updateMilestone` check propagate; `createMilestone` rethrows `usedIDLookupFailed`; injectable `fetcher:` |
| `Transit/Transit/Services/ProjectService.swift` | `projectNameExists` throws; `createProject` / `updateProject` propagate; injectable `fetcher:` |
| `Transit/Transit/Services/DisplayIDRecordLookup.swift` | Used-ID snapshots removed (moved to `UsedDisplayIDs`) |
| `Transit/Transit/Services/DisplayIDMaintenanceService.swift` | Reassignment allocations use the throwing `UsedDisplayIDs`; failure reported as `.allocationFailed` |
| `Transit/Transit/MCP/MCPToolHandler.swift` | `update_milestone` rename check distinguishes "taken" from "could not check"; extracted `milestoneRenameConflict` |
| `Transit/Transit/Intents/UpdateMilestoneIntent.swift` | Same, returning `INTERNAL_ERROR`; extracted `renameConflict` |
| `Transit/TransitTests/FetchFailureInvariantTests.swift` | New — `FailingFetcher` seam and nine caller-level tests |
| `Transit/TransitTests/ProjectServiceTests.swift` | `projectNameExists` call sites now use `try` |
| `Transit/TransitTests/MilestoneServiceLookupTests.swift` | `milestoneNameExists` call sites now use `try` |

## Verification

**Automated:**

- [x] Regression tests fail before the fix, pass after
- [x] Full macOS unit suite passes (`make test-quick`)
- [x] `make lint` (SwiftLint `--strict`) passes, 0 violations

**Manual verification:** None. Both failure modes need a SwiftData fetch to fail while the same
context still saves, which is not reproducible by hand; the injected fetcher models it directly.

## Prevention

- **`try?` on a read that feeds an invariant is a bug, not a convenience.** The question is not
  "can this fetch fail?" but "if it fails, does the caller do something it would not otherwise
  have done?". Where the answer is yes, the read must throw.
- **Fail closed or fail loudly, never fail permissive.** A degraded value that happens to mean
  "go ahead" (`false`, `[]`, `nil`) is the worst of the options, because it is indistinguishable
  from the common success case.
- **When a value type has no room for "unknown", the function needs `throws`.** `Bool` and
  `Set<Int>` cannot express it, so the signature has to.
- **Interaction with T-1926** (make `allocateNextID`'s `excluding:` required): this change makes
  it slightly *easier* and certainly no harder. All call sites now pass an explicit closure,
  there is a single shared `UsedDisplayIDs` for a required argument to be built from, and the
  throwing closure type makes the permissive `{ [] }` default read as a deliberate "assert
  nothing is in use" rather than incidental terseness. The remaining work for T-1926 is
  unchanged: drop the default and update the handful of tests that call `allocateNextID()` bare.

## Related

- T-1614 — name-uniqueness half of this bug.
- T-1621 — used-display-ID half of this bug.
- T-1764 (PR #188) — added the post-allocation `milestoneNameExists` re-check that closes the
  create TOCTOU window. That re-check now actually holds when the store is unreadable.
- T-1766 (PR #186) — passed used-ID closures to the maintenance allocations and explicitly
  deferred the swallowed fetch error to T-1621; `DisplayIDRecordLookup`'s copies are now gone.
- T-1395 — introduced the `excluding:` collision guard and the `AllocationGate`.
- T-1566 (PR #179) — the `TaskFetching` / `MilestoneFetching` precedent for a narrow fetch seam
  and for returning `INTERNAL_ERROR` rather than an empty result.
- T-1818 / T-1836 (PR #181) — `PersistenceAvailability`; same principle applied to writes on
  fallback storage.
- T-1926 (open) — make `allocateNextID`'s `excluding:` parameter required. Deliberately not
  implemented here.
