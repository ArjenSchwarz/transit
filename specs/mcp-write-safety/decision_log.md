# Decision Log: MCP Write Safety

## Quick Decisions

| ID | Date | Decision | Rationale |
|----|------|----------|-----------|
| Q1 | 2026-10-03 | Use the full spec workflow for T-2380. | Approved scope assessment: the feature changes a public mutation contract and may require persisted retry state. |
| Q2 | 2026-10-03 | Name the feature `mcp-write-safety`. | User approved the proposed name. |
| Q3 | 2026-10-03 | Compatibility with callers omitting safety fields is not required. | User stated existing MCP callers can update; draft requires keys on protected writes and revisions on updates/deletion. |
| Q4 | 2026-10-03 | Guarantee replay within the same local store across app restarts. | User accepted the recommendation; cross-device deduplication would need stronger coordination than local writes. |
| Q5 | 2026-10-03 | Guarantee replay for at least seven days after completion, with returned expiry. | User accepted the recommended retention window. |
| Q6 | 2026-10-03 | Clarify status-plus-comment persistence as both-or-neither through interruption; include expiry on retained rejection outcomes. | Critic and both independent validation peers found these necessary to make retry outcomes unambiguous. |
| Q7 | 2026-10-03 | Approve requirements and proceed to design. | User approved the reviewed requirements, including the revision boundary in Decision 1. |
| Q8 | 2026-10-03 | Approve design, including Decisions 3–5, and proceed to task planning. | User approved the design after final critic and peer review. |
| Q9 | 2026-10-03 | Approve the 14-task implementation plan. | User approved seven red/green pairs with persistence verification before dependent integration. |
| Q10 | 2026-10-03 | Create branch `T-2380/mcp-write-safety`. | User chose this branch and created it after sandbox access blocked the agent's attempt. Verified the checkout is now on this branch. |
| Q11 | 2026-10-03 | Mark T-2380 ready for implementation. | Requirements, design and all 14 planned tasks are approved; branch selection is complete. |
| Q12 | 2026-10-03 | Add review-fix red/green tasks 15–16 within the approved scope. | Phase review found lossy numeric request identity and missed legacy safety/envelope migrations; both fixes are required to satisfy existing acceptance criteria. |
| Q13 | 2026-10-03 | Retain In Progress status after coding and focused review. | All 16 tasks are implemented, but full application/transport verification and required Git commits are blocked by the current environment; do not claim these gates passed. |
| Q14 | 2026-10-03 | Add application-gate red/green tasks 17–18 and preserve established domain behavior. | Actual execution exposed compiler issues and 16 contract/fixture failures; fixes distinguish mandatory safety/full-write-record changes from unintended validation, normalization and summary-query regressions. |
| Q15 | 2026-10-03 | Complete implementation verification and move to review. | Permission restrictions resolved; all 18 tasks complete, focused 115/115, macOS 1,853/1,853 and iOS unit/UI 1,308/1,308 pass. Final review has no material findings; implementation and changelog commits are confirmed. |
| Q16 | 2026-10-03 | Validate one keyed guard snapshot and one receipt pass per cleanup. | Pre-push review found repeated guard scans made maintenance quadratic; a per-pass snapshot preserves validation and lock semantics without a stale persistent cache. |
| Q17 | 2026-10-03 | Require complete terminal envelopes before replay and reuse shared scalar parsers. | Malformed receipts must remain uncertain; exact integer boundaries must agree with existing intent parsing. Focused regression probes passed. |

## Decision 1: Limit Revisions to Defined Entity State

**Date**: 2026-10-03
**Status**: accepted

### Context

MCP responses can include related records and summaries. Covering every expanded value would make a project rename invalidate assigned tasks even when their own state did not change. Revision coverage must be explicit to make conflict behavior testable.

### Decision

Cover each entity's own stored scalar fields and explicit relationship IDs. Task revisions additionally cover comment membership and comment fields. Exclude related project/milestone descriptive fields, parent collections, and derived summaries.

### Rationale

This detects changes to a task's editable state and discussion while avoiding unrelated task conflicts after a project or milestone rename. The user approved this boundary with the requirements.

### Alternatives Considered

- **Cover all expanded response fields**: Detects any visible response difference but couples task updates to unrelated parent edits and summary changes.
- **Cover only each entity's scalar fields**: Reduces conflicts but misses task assignment changes and additions or edits to its discussion.

### Consequences

**Positive:**
- Callers have a defined conflict boundary across local write paths and imported sync.
- Renaming an assigned project or milestone does not invalidate task preconditions.

**Negative:**
- A task's revision does not prove that every related descriptive value in an expanded response is unchanged.
- Appending a comment invalidates outstanding task update preconditions.

---

## Decision 2: Persist Receipts Alongside Domain Records

**Date**: 2026-10-03
**Status**: accepted

### Context

Retry safety after restart requires durable evidence of whether a write completed. Storing that evidence separately from the domain store creates a failure window between two independent commits.

### Decision

Store receipts in the existing SwiftData store and complete them in the same save as domain changes. Scope keys using a local persistent identity even when CloudKit synchronizes receipts. Verify local crash atomicity before integrating the handlers.

### Rationale

The user approved this approach after considering its sync behavior. Apple documents a ModelContext save as the boundary grouping pending changes; the implementation probe checks that the required recovery behavior holds on Transit's runtime.

### Alternatives Considered

- **Separate local journal**: Avoids syncing receipts but requires recovery across independent commits, including an ambiguous window after domain persistence.
- **Memory-only receipts**: Avoids a schema change but fails replay protection across app restart.

### Consequences

**Positive:**
- Durable completion evidence does not depend on the target continuing to exist.
- One local commit binds the effect to its normalized result.

**Negative:**
- Receipt payloads and results consume synced storage when CloudKit is active.
- Shipping requires an additive entity and CloudKit schema publication.
- Local crash/save behavior must pass the early disk-backed probe.

---

## Decision 3: Derive Revisions from Covered Content

**Date**: 2026-10-03
**Status**: accepted

### Context

Tasks can change through UI, intents, maintenance, and imported sync. A counter updated only by MCP would miss these paths; a shared counter field would also need reliable distributed merge semantics.

### Decision

Hash exact versioned snapshots of the covered state with SHA-256. Do not add persisted revision counters. Treat tokens as content equality, including the possibility of an identical token after an edit is reverted completely.

### Rationale

Snapshots capture any locally visible change without new write hooks. Requirements define equality comparisons and stable no-op tokens rather than an edit-history sequence.

### Alternatives Considered

- **Increment a persisted counter on every write**: Requires hooks in all writers and still cannot detect imported edits reliably from merged counter values.
- **Use lastStatusChangeDate**: Misses ordinary field/comment edits and loses precision in current MCP timestamp formatting.

### Consequences

**Positive:**
- Local UI/intent/maintenance and synced state use the same revision logic.
- Identical covered state has a stable token across launches.

**Negative:**
- Tokens do not detect intervening changes that restore exactly the same state.
- Task snapshot capture requires reading its comments.

---

## Decision 4: Retain the Shared Main Context

**Date**: 2026-10-03
**Status**: accepted

### Context

Transit's services share the view context. A context-wide rollback can otherwise discard unrelated unsaved work, and creation helpers can leave ghost models if new inserts are not explicitly removed.

### Decision

Save any existing pending changes before acceptance and again after asynchronous preparation, before domain mutation. Keep the mutation, snapshot encoding, receipt completion, and final save synchronous; remove fresh inserts before rollback. A baseline save failure preserves pending edits and does not invoke rollback.

### Rationale

This retains the existing service/context integration while isolating rollback to the newly staged operation. It requires creation preparation to allocate IDs before inserting models.

### Alternatives Considered

- **Independent writable MCP context/services**: Isolates rollback but changes model visibility and would require independent fresh-read and UI merge behavior throughout the MCP service graph.
- **Hold an unsaved transaction across allocation waits**: Allows UI/autosave work to persist or become entangled with partial MCP changes.

### Consequences

**Positive:**
- Existing view/service model identity stays intact.
- Failure cleanup cannot discard edits made while ID allocation was suspended.

**Negative:**
- A protected request can flush pending changes from other local work, matching existing shared-context saves.
- Task/milestone create services need separate preparation and synchronous application APIs.

---

## Decision 5: Preserve Uncertain Bindings in Local Guards

**Date**: 2026-10-03
**Status**: accepted

### Context

A receipt can become unreadable or missing after confirmed acceptance. An in-memory block cannot protect that key after another restart; creating quarantine only after discovering the loss also leaves a crash window.

### Decision

Persist local reservation guards before acceptance, retaining canonical payload and receipt identity through terminal retention. A guard without a valid receipt yields uncertainty and prevents another effect. Unreadable guard storage fails closed for new writes in that scope. Domain outcomes still commit with receipts in the single SwiftData save.

### Rationale

The critic and both validation peers identified this gap. A durable payload binding enforces required uncertain-key retention without interpreting missing domain records as proof of rejection.

### Alternatives Considered

- **Reactive quarantine only**: Cannot cover a crash before the quarantine marker is persisted.
- **Volatile blocking or assuming missing means uncommitted**: Can lose accepted-key protection on restart and duplicate an uncertain effect.

### Consequences

**Positive:**
- Matching and mismatched uncertain retries remain identifiable across restart.
- Outcome persistence remains atomic with the domain effect.

**Negative:**
- A local guard store adds durable metadata and cleanup coordination.
- Receipt loss can require manual reconciliation even when no domain effect actually occurred.
