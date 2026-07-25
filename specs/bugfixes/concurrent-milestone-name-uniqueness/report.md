# Bugfix Report: Concurrent Milestone Creation Bypasses Name Uniqueness

**Date:** 2026-07-26
**Status:** Fixed
**Ticket:** T-1764

## Description of the Issue

Milestone names must be unique (case-insensitively) within a project. `MilestoneService.createMilestone`
enforces that with a `milestoneNameExists` check — but the check runs *before* the method awaits
display-ID allocation. The await is a suspension point, so two overlapping creates can both pass the
check while neither has inserted anything, then both resume and commit the same name in the same
project.

**Reproduction steps:**
1. Start a milestone create for name "Beta" in project P. It passes the uniqueness check and suspends
   inside `DisplayIDAllocator.allocateNextID`.
2. While that create is suspended, start a second create for "beta" in project P. It runs its own
   uniqueness check — still clean, because the first create has not inserted — then queues on the
   allocator's gate.
3. Let both resume. Both insert and save. Project P now holds two milestones whose names differ only
   in case.

In production the overlap comes from ordinary sources: an MCP `create_milestone` call landing while a
`CreateMilestoneIntent` is in flight, two automation runs, or a UI create racing an agent create.
All of them are MainActor tasks that suspend at the same allocation await.

**Impact:** The per-project case-insensitive name invariant can be violated. `findByName` returns
`milestones.first { ... }`, so once duplicates exist, name-based lookup silently resolves to an
arbitrary one of them — every name-addressed operation (MCP `update_milestone`, `delete_milestone`,
task assignment by milestone name) can hit the wrong record. Sequential creates were never affected,
which is why the gap survived: existing coverage only exercised the sequential path.

## Investigation Summary

- **Symptoms examined:** Duplicate case-insensitive milestone names inside a single project, with no
  error surfaced to either caller.
- **Code inspected:**
  - `Transit/Transit/Services/MilestoneService.swift` — `createMilestone`, `milestoneNameExists`,
    `findByName`.
  - `Transit/Transit/Services/DisplayIDAllocator.swift` — `allocateNextID` and the `AllocationGate`
    actor, to establish exactly where `createMilestone` suspends and in what order queued callers
    resume.
  - `Transit/TransitTests/CancelledCreateTests.swift` and `ConcurrentDisplayIDCreationTests.swift` —
    existing precedents for driving a deterministic interleave through the allocation gate.
- **Hypotheses tested:**
  - *A database constraint backs the check.* Ruled out: SwiftData + CloudKit forbids
    `@Attribute(.unique)` (CLAUDE.md, "Key Technical Constraints"), so the service check is the whole
    invariant.
  - *The allocation gate already serialises the whole create.* Ruled out: the gate only serialises
    `allocateNextID` itself. It is released before the caller inserts, and — crucially — it is
    acquired *after* the uniqueness check, so it protects nothing about names.
  - *`milestoneNameExists` misses unsaved inserts.* Ruled out as the root cause: the fetch does see
    pending changes, and in the failing interleave the first create has not even inserted yet when the
    second one checks. The problem is ordering, not fetch visibility.

## Discovered Root Cause

`createMilestone` performs time-of-check-to-time-of-use across an `await`. The sequence is:

```
check name  ->  await allocateNextID  ->  insert  ->  save
     ^                    ^
     |                    +-- suspension point: other MainActor creates run here
     +-- result is stale by the time the insert happens
```

The check result is consumed after a suspension during which any other create can run its own check
and, later, commit. Nothing re-validated between the resume and the insert.

**Defect type:** Race condition (TOCTOU across an await boundary).

**Why it occurred:** The check was written when it was adjacent to the insert. Display-ID allocation
was later made `async` (CloudKit counter with optimistic locking), which inserted a suspension point
between the check and the insert. The uniqueness check was not revisited at that time. Subsequent
concurrency work on this same code path (T-1395 gate, T-1426 cancellation) hardened *ID* allocation
against interleaving but treated the name check as unrelated.

**Contributing factors:**
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` makes the code *look* single-threaded. It is
  single-threaded, but not atomic — every `await` is a yield point, and that is easy to overlook.
- CloudKit forbids `@Attribute(.unique)`, so there is no database-level backstop to catch the escape.
- Existing tests only covered sequential creates, which reject duplicates correctly.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/Services/MilestoneService.swift` — in `createMilestone`, re-check
  `milestoneNameExists` immediately after display-ID allocation returns and before
  `modelContext.insert`, throwing `Error.duplicateName` when a concurrent create committed the name
  during the suspension.

**Approach rationale:** After the allocation await there are no further suspension points in
`createMilestone` — the re-check, `insert`, and `save` all run in one uninterrupted MainActor job. So
re-checking at that point makes check-and-insert genuinely atomic with respect to other MainActor
creates, which is the only concurrency that exists here. The early check is kept as a cheap fast-fail
so the common duplicate case does not consume a display ID from the CloudKit counter.

**Alternatives considered:**
- **Drop the early check, check only after allocation.** Rejected: every duplicate attempt would burn
  a counter allocation (and a CloudKit round trip) before failing.
- **Hold a name-scoped async lock across the whole create.** Rejected: it adds a second serialisation
  primitive alongside the existing `AllocationGate`, for no benefit — the create has exactly one
  suspension point, so a re-check after it is equivalent and far simpler.
- **Move allocation before the name check.** Rejected: it does not close the window (the insert still
  follows a suspension) and it would consume an ID for every rejected create.
- **Enforce uniqueness in the data layer.** Not available: CloudKit-backed SwiftData does not support
  `@Attribute(.unique)`.

## Regression Test

**Test file:** `Transit/TransitTests/ConcurrentMilestoneNameUniquenessTests.swift`

**Test names:**
- `interleavedCreatesWithSameNameRejectTheSecond()` — the regression proper.
- `interleavedCreatesWithDifferentNamesBothSucceed()` — guards against the re-check over-rejecting.
- `interleavedCreatesWithSameNameInDifferentProjectsBothSucceed()` — guards that the re-check stays
  project-scoped.

**What it verifies:** That the second of two *interleaved* same-name creates is rejected with
`MilestoneService.Error.duplicateName` and that exactly one milestone with that name is persisted.

**How the interleaving is made deterministic** (a test that merely calls create twice in sequence
passes against the broken code and proves nothing):

1. A `GatedCounterStore` test double blocks its **first** `loadCounter` call until the test releases
   it. Because `allocateNextID` reads the counter while holding the allocation gate, this parks the
   first create precisely in the window under test — after its uniqueness check, before its insert.
   `waitUntilGateHeld()` lets the test await that exact state instead of guessing at timing.
2. The contender is then launched. An `EntryFlag` is set as the first statement of its task body.
   Everything from that assignment through `createMilestone`'s uniqueness check runs inside a single
   MainActor job with no suspension, so when the test observes the flag set — necessarily from a
   *later* job — the contender has provably already made its (now stale) check and parked on the
   allocation gate.
3. Only then does the test release the gate. The first create commits; the contender resumes and must
   reject.

The flag is also asserted with `#expect`, so if MainActor scheduling ever changed such that the
contender never ran, the test would fail loudly rather than pass vacuously.

**Run command:**
```
xcodebuild test -project Transit/Transit.xcodeproj -scheme Transit \
  -destination 'platform=macOS' \
  -only-testing:TransitTests/ConcurrentMilestoneNameUniquenessTests test
```

Confirmed red before the fix: `Expectation failed: an error was expected but none was thrown` and
`(matches.count -> 2) == 1: Only one milestone named 'Beta' may exist in the project, found 2`.

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Services/MilestoneService.swift` | Re-check name uniqueness after the allocation await, before insert |
| `Transit/TransitTests/ConcurrentMilestoneNameUniquenessTests.swift` | New deterministic interleaving regression suite |

## Verification

**Automated:**
- [x] Regression test fails before the fix, passes after
- [x] Full unit test suite passes (`make test-quick`)
- [x] `make lint` clean

## Prevention

**Recommendations to avoid similar bugs:**
- Treat every `await` in a service method as a point where another caller of the same method can run
  to completion. Validation performed before an await must be re-affirmed after it if the result is
  consumed by a mutation.
- Where a model invariant cannot be expressed in the store (all CloudKit-backed uniqueness in this
  app), the enforcing check and the mutation it guards should be adjacent and suspension-free.
  `MilestoneService.updateMilestone` does the same name check but is synchronous end to end, so it is
  safe today — it would need the same treatment if it ever gains an await.
- Concurrency regression tests must pin the interleaving with an explicit hand-off (gate the
  suspension, then assert the other caller reached its check). Launching two tasks and hoping for a
  race produces a test that passes against broken code.

## Related

- T-1395 — concurrent task creation could duplicate display IDs; introduced the `AllocationGate` that
  this fix relies on for its deterministic test hand-off.
- T-1426 — cancelled creates persisted provisional records; same create path, and
  `CancelledCreateTests.swift` is the source of the `GatedCounterStore` pattern reused here.
- T-1614 — `milestoneNameExists` swallows fetch failures via `try?`, so a failed fetch reads as "no
  duplicate". That weakens both the original check and this new re-check, but it is a separate defect
  with a separate fix (surface the fetch error) and is deliberately **not** addressed here.
- T-1765 — pre-cancelled creates can still persist records, also in `createMilestone` around the
  post-allocation cancellation check. It touches adjacent lines but is a distinct defect and is **not**
  addressed here.
