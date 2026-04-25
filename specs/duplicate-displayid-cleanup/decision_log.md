# Decision Log: Duplicate Display ID Cleanup

## Decision 1: Best-Effort Per-Group Reassignment

**Date**: 2026-04-24
**Status**: accepted

### Context

Reassigning duplicate display IDs involves one `allocateNextID()` CloudKit round-trip per loser and a SwiftData save per record. A batch may contain many groups. We must decide how partial failures are handled: atomic all-or-nothing rollback versus best-effort progress with per-group reporting.

### Decision

The reassignment run proceeds group-by-group. A failure on one group records the failure in the result and continues with the next group. No outer transaction wraps the run.

### Rationale

`allocateNextID()` is inherently per-call (each hits CloudKit with optimistic locking), so a run that touches N losers cannot be wrapped in a single atomic operation anyway. Best-effort matches the existing `promoteProvisionalTasks` pattern, maximises progress during connectivity blips, and keeps the counter advancing monotonically even when some groups fail.

### Alternatives Considered

- **Atomic all-or-nothing**: Allocate every ID first in-memory, then one `save()`; rollback on any failure — Rejected because allocations must succeed individually against CloudKit and cannot be batched, and a failed rollback would strand the already-incremented counter values.

### Consequences

**Positive:**
- Partial progress on flaky connections.
- Straightforward control flow matching existing promotion code.

**Negative:**
- A run can end in a partially-cleaned state that requires a second run to finish.

---

## Decision 2: Agent-Authored Comment on Reassigned Tasks

**Date**: 2026-04-24
**Status**: accepted

### Context

Reassigning a task's display ID breaks external references (commit messages, notes). Users need a way to trace stale references back to the current task.

### Decision

When a task's display ID is reassigned, add a `Comment` with `isAgent=true` stating the previous ID, the new ID, and the date. Milestones receive no comment because the `Milestone` model has no comment relationship.

### Rationale

Comments are the existing Transit mechanism for recording agent-side activity on a task, and they are visible in the task detail view. Writing to an existing surface avoids introducing a new audit schema.

### Alternatives Considered

- **No audit trail, report only**: The scan report is the single record — Rejected because the report is ephemeral; a user opening a task three months later needs to see why its ID changed.
- **Metadata field on the task**: Add a key to the task's `metadata` dictionary — Rejected because metadata is free-form agent state and is not surfaced in the UI by default.

### Consequences

**Positive:**
- Persistent, user-visible audit trail per task.
- No schema change.

**Negative:**
- Milestones have no equivalent trail (acceptable — milestones are referenced externally far less often than tasks).
- Comment save failures are a new failure mode to report per group.

---

## Decision 3: No Confirmation Flag on MCP Mutating Tool

**Date**: 2026-04-24
**Status**: accepted

### Context

The `reassign_duplicate_display_ids` MCP tool mutates display IDs across records. We considered requiring an explicit `confirm: true` parameter to prevent accidental runs.

### Decision

The tool has no required confirmation parameter. The MCP client's own approval prompt and the explicit tool name are considered sufficient.

### Rationale

Transit's other mutating MCP tools (`update_task`, `delete_milestone`) do not require confirmation flags, and adding one here would be inconsistent. Users running via MCP have already accepted that tool calls are deliberate actions.

### Alternatives Considered

- **Require `confirm: true`**: Reject calls without the flag — Rejected for inconsistency with the existing tool surface and because the MCP client's approval prompt already serves this role.

### Consequences

**Positive:**
- Consistent with existing MCP tool conventions.

**Negative:**
- An agent could call the tool without first running scan; mitigated by returning a clear per-group report so the effects are legible.

---

## Decision 4: No Launch-Time Counter Self-Heal

**Date**: 2026-04-24
**Status**: accepted

### Context

The most likely root cause of existing duplicates is CloudKit counter record loss, which makes `loadCounter()` restart from 1. A launch-time check could compare `max(existingId)` to the counter and advance it automatically.

### Decision

This feature does not add a launch-time self-heal. It advances the counter only once at the end of a cleanup run.

### Rationale

Self-heal is a separate concern from cleanup. Adding a CloudKit round-trip to every cold start has its own reliability cost, and the cleanup tool's end-of-run counter advance plus the fix for the root cause (tracked separately) together cover the recurrence case. Scope creep on a maintenance feature is undesirable.

### Alternatives Considered

- **Add launch-time check**: On every cold start, read max(existingId) and advance counter if behind — Rejected to keep scope tight; can be a follow-up ticket once the counter-reset root cause is understood.

### Consequences

**Positive:**
- Smaller surface; faster to deliver.
- No new CloudKit calls at cold start.

**Negative:**
- If the counter resets again between runs, new duplicates can appear before the next cleanup.

---

## Decision 5: Winner Policy — Oldest creationDate, UUID Tiebreaker

**Date**: 2026-04-24
**Status**: accepted

### Context

When N records share a display ID, one must keep the ID and the rest must receive new ones. The "winner" selection affects which external references stay valid.

### Decision

The winner is the record with the earliest `creationDate`. When two records share the same `creationDate`, the tiebreaker is lexicographically smallest UUID string.

### Rationale

The oldest record is most likely the original "real" one referenced in external notes and commit messages. Keeping it preserves the largest number of external references. UUID tiebreaker guarantees deterministic selection without needing a separate rule.

### Alternatives Considered

- **Most recent wins**: Keep the newest — Rejected because the most recent record is least likely to have accumulated external references.
- **Most-commented wins**: Keep the record with the most comments — Rejected because it only applies to tasks and introduces a secondary query per group.

### Consequences

**Positive:**
- Deterministic, simple to implement, maximises retained external references.

**Negative:**
- Ties on `creationDate` are resolved arbitrarily by UUID, which does not consider any user-visible signal.

---

## Decision 6: Re-Fetch Before Writing a Reassignment (Stale-ID Guard)

**Date**: 2026-04-24
**Status**: accepted

### Context

Between scan and reassign, a peer device can sync a change that already resolves the duplicate (e.g. the other device ran the same tool and the new IDs have arrived locally). Writing without checking could clobber a good state.

### Decision

Just before writing a loser's new `permanentDisplayId`, the service re-fetches the record. If the stored `permanentDisplayId` no longer equals the value observed during the scan, the group is skipped and reported with outcome `stale-id`.

### Rationale

A single extra fetch per loser is cheap relative to the CloudKit allocation round-trip. Skipping on mismatch preserves whatever the converged state now is, which is usually correct, and avoids re-introducing duplicates by overwriting a record another device has already moved.

### Alternatives Considered

- **Overwrite unconditionally**: Skip the re-fetch and trust the scan snapshot — Rejected because it can re-introduce duplicates after a peer device has already resolved them.
- **Transactional re-scan per group**: Rescan and recompute winner/losers for each group just before writing — Rejected as over-engineered for a single-user tool.

### Consequences

**Positive:**
- Safer across devices and across quick reruns of scan+reassign.
- Explicit `stale-id` outcome tells the user what happened.

**Negative:**
- One extra CloudKit/SwiftData fetch per loser.

---

## Decision 7: Two-Save Audit Trail

**Date**: 2026-04-24
**Status**: accepted

### Context

Reassigning a task writes both a new `permanentDisplayId` and an audit `Comment`. These could share a single `save()` (atomic) or be written in two saves (independent).

### Decision

The ID save happens first on its own. The audit comment save happens second. A comment-save failure does not undo the ID save; it is reported as a `comment-failed` warning for the group.

### Rationale

The ID rewrite is the critical outcome — losing a failed comment write must not cause the run to abort or to leave the record mis-identified. Best-effort semantics (Decision 1) extend naturally to the comment step. The orphan-comment risk does not apply because the comment is created in the same operation and cannot exist without the ID change.

### Alternatives Considered

- **Single atomic save**: Write both in one `save()` and roll back both on failure — Rejected because a comment-save failure would defeat the ID cleanup purpose.
- **Skip the comment on ID-save failure**: Obvious and already implied; called out for clarity.

### Consequences

**Positive:**
- ID cleanup proceeds even when comment writes are unreliable.
- Failure mode is narrow: `comment-failed` is a warning, not a group failure.

**Negative:**
- A task can be reassigned without its audit comment during the small window between the two saves; the group result records this explicitly.

---

## Decision 8: Cancellation Is a Non-Goal

**Date**: 2026-04-24
**Status**: accepted

### Context

Reassigning N losers performs N CloudKit round-trips and can take seconds to tens of seconds. A Cancel button on the Settings view, or cancel support in App Intents and MCP, would let a user stop partway.

### Decision

No surface supports cancellation. The feature is documented as non-cancellable in the Non-Goals section.

### Rationale

Typical Transit duplicate counts are small (single-user tracker). Adding cancel support introduces a state machine (running / cancelled / post-cancel cleanup) across three surfaces for a rare case. Best-effort per-group reporting already allows a user to observe progress; a user who has to stop can close the app and accept whatever work has already been committed.

### Alternatives Considered

- **UI-only cancel**: Cancel button in Settings — Rejected because it leaves MCP/Intent surfaces inconsistent and still requires the state machine.
- **Cancel on all surfaces**: MCP and Intent cancellation too — Rejected as larger scope than the feature warrants.

### Consequences

**Positive:**
- Smaller scope; single code path per operation.

**Negative:**
- A run that is much slower than expected cannot be stopped cleanly; user must wait or force-quit.

---

## Decision 9: MCP Maintenance Tools Default Off, Toggleable

**Date**: 2026-04-24
**Status**: accepted

### Context

The two maintenance MCP tools (`scan_duplicate_display_ids`, `reassign_duplicate_display_ids`) are used rarely but appear in every session's tool list, costing context tokens for every agent conversation. Other Transit MCP tools are general-purpose and justify always-on exposure; these do not.

### Decision

The two maintenance tools are gated behind a new persistent setting, defaulting to off. When off, the tools are omitted from the server's `tools/list` response and `tools/call` returns a tool-not-found error for either name. The toggle lives in the existing macOS MCP Server settings pane, alongside the existing server enable/port settings. The change takes effect without an app restart.

The in-app Settings UI and the App Intents remain always available — they do not pollute MCP context and are triggered deliberately by the user.

### Rationale

Hiding the tools behind a toggle preserves the "run this when I need it" ergonomic while keeping every-session MCP context lean. Defaulting to off means a user who has never needed cleanup never sees them; a user running a cleanup session turns them on, runs the tools, and turns them off again.

### Alternatives Considered

- **Always listed**: Keep parity with other MCP tools — Rejected because maintenance tools are a distinct class with different usage patterns.
- **Gate App Intents and UI behind the same toggle**: Single switch for all maintenance surfaces — Rejected because UI and Intents do not contribute per-session context cost, and hiding them behind a macOS-only toggle would break parity on iOS.
- **Require app restart when toggled**: Simpler implementation — Rejected because restarting the app to enable a maintenance session defeats the ergonomic goal.

### Consequences

**Positive:**
- Zero MCP context cost for every agent session that is not running cleanup.
- Matches the user's mental model of maintenance as a deliberate, infrequent operation.

**Negative:**
- One more setting to document and surface in the UI.
- An agent that attempts a call before the user enables the toggle receives a tool-not-found error; the failure is diagnosable only by the human (the agent cannot toggle the setting itself).

---

## Decision 10: Counter Advance at Start of Run, Not End

**Date**: 2026-04-24
**Status**: accepted

### Context

The initial design advanced the CloudKit counter at the end of a reassignment run. A subsequent review noted that while maintenance is running, a concurrent provisional-ID promotion pass can call `allocateNextID()` with a counter that is still behind the existing `max(permanentDisplayId)` — the very condition that produced the duplicates in the first place. Promotion could mint a new ID that collides with an existing duplicate group we are about to clean up, leaving a residual duplicate that the current run will not iterate.

### Decision

`reassignDuplicates` advances the counter to `max(sampledMax, currentCounter) + 1` *before* allocating any replacement IDs for losers. The advance is attempted once per record type that has observed records; it is skipped if the counter is already ahead. A counter-advance failure aborts reassignment for that record type only.

### Rationale

Once the counter is past the existing max, every `allocateNextID` — from this run or a racing promotion/creation — returns a value strictly greater than any existing `permanentDisplayId`. This closes the duplicate-introduction window during the run itself, rather than hoping the end-of-run fence arrives before the next promotion. It also simplifies idempotence: even if the run aborts after advance, the fence is already in place and subsequent runs start from a cleaner baseline.

### Alternatives Considered

- **End-of-run advance with documented race**: Keep the original design and list the race in the Risks section — Rejected because the race is narrow but correctable, and the fix is local.
- **Share the single-flight flag with promotion**: Make reassign and promotion mutually exclusive — Rejected because it couples unrelated subsystems and the counter-advance approach gives the same safety property without coupling.

### Consequences

**Positive:**
- Race-free with respect to concurrent provisional promotion and creation.
- Fence is set even if later reassignment steps fail.

**Negative:**
- Counter jumps are visible earlier in the run, slightly harder to interpret if a user watches logs.
- A counter-advance failure fails the run for that record type before any reassignment is attempted; the "best effort per group" principle does not apply to the advance step itself.

---

## Risks Acknowledged (Not Addressed)

- **Cross-device counter-stale race between runs.** If device A runs cleanup and advances the counter, but device B is offline with a stale local view of the counter, device B's next allocation can collide with an ID A just reassigned. End-of-run CAS on the counter (AC 2.4) prevents A from moving the counter backwards but does not help B. Proper mitigation requires launch-time counter self-heal, which Decision 4 explicitly defers.
- **Windows where a reassigned task is seen without its audit comment.** Decision 7's two-save order leaves a short window where a reader can see the new ID without the comment explaining the change.
- **Winner changed between scan and reassign.** AC 2.3's stale-ID guard covers losers only. If a peer device has mutated the winner's `permanentDisplayId` between scan and reassign, the group still proceeds with the scanned winner identity. The worst case is a residual duplicate detected on the next run, which is acceptable for a deliberately-run maintenance operation.
- **Local-only visibility of peer changes via `refresh(_:mergeChanges:)`.** The stale-ID re-fetch calls `ModelContext.refresh(_:mergeChanges: true)`, which re-reads from the local SwiftData store. Peer-device changes are only visible after CloudKit has merged them locally; a change in flight is not detected. Acceptable because the counter-advance fence (Decision 10) prevents the race the stale-ID guard primarily exists to catch; the refresh is a belt-and-braces measure.
