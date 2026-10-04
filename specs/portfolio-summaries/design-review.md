# Portfolio summaries: design review

Status: design approved unchanged in parent Sentinel_541ceb19e7c8819193d04d23c5263041, including final aligned scope/publication amendments at T-2382 3932e88 and T-63 5639c40; user approved all requirements in Sentinel_fa39017e21a08191abdcd0b7ae6c9e8e. No tasks or production implementation approved.

Saved-only read clarification is explicitly approved in Sentinel_bb00a4d9d8688191a33a0e6a34ea38db. The isolated spec branch is based on merged T-2380 `201205bd4e786c7f152d8f99006b37da7da888c7`; the merged MCP tree equals the inspected PR head `b618acf`, so revision/capture integration conclusions remain valid. Canonical checkout and other worktrees were preserved.

## Explanation self-validation (local explain-like skill)

### Beginner

The server takes a saved picture of local projects and tasks, counts that picture, and gives it a short-lived ID. Asking for task detail with the same ID shows the same picture, even if records have changed. Its timestamps describe local observation, not proof that another device's edits have arrived. A separate response controller can report a timeout while the database worker is still blocked; that blocked worker continues to occupy one of eight slots.

### Intermediate

T-63 admits reads before MainActor queueing and captures Sendable values from a separate autosave-disabled context with a history/store fence. T-2382 aggregates those values and retains them with encoded pages for five minutes. Ordinary task queries keep their existing semantics; explicit snapshot queries use effective-status filtering and full captured task fields without comment bodies. Common schema/handler/server files have T-63 as the sole writer. Publication is staged until response encoding and the one-shot deadline/lifecycle gate both succeed.

### Expert

Completion-window and activity computations are pure over one fenced capture. Physical identity prevents UUID/display-ID deduplication from corrupting totals. Snapshot-scoped projections share root capture metadata and original monotonic expiry; new task pages cannot extend lifetime. Deadline state and physical-work accounting are distinct: timeout chooses one preencoded response, but completion alone frees the physical slot. Atomic completion/store insertion prevents late workers, lifecycle changes and encoding failures from creating unreachable or stale views. T-2380 revisions must be minted from raw canonical stored content including comments before derived statuses and omitted bodies change the returned projection.

### Validation findings

The beginner explanation exposed an important boundary: snapshots describe committed local store state, not unsaved UI forms or remote convergence. The expert pass requires a publication transaction covering both the response gate and retained store entry, and a capture fence that does not save unrelated UI edits. These contracts are explicit in the design. Actual transport timer reserve, CloudKit history correlation and real-volume revision capture remain prototype/measurement gates rather than inspection-based guarantees.

## Prototype evidence

The separate prototype uses Swift 6.4 with MainActor default isolation, complete strict concurrency and warnings as errors. It demonstrated 4.950227-second encoded timeout availability with a six-second MainActor block, eight retained timed-out physical workers, ninth busy, release after physical finish, and 120 exactly-once/publication race cases. Exact-boundary timers were late; the design must reserve scheduling/encoding margin. This is not an app-level Hummingbird/SwiftData proof.

Source and output remain outside the production checkout at `/Users/arjen/Documents/Codex/2026-10-03/task-2/design-prototypes/t2382-deadline/`. No Xcode/simulator tests were run. T-63 independently demonstrated history fencing rejecting an injected mixed capture; app-level capture/import and response integration remain required design validation.

## Review mode

Use design-critic followed by the actual peer-review-validator's two independent subagent fallback. External Codex/Kiro review retries remain stopped: automatic approval review rejected the delegated disclosure authorization despite parent user approval. No external-model review or new permission request is claimed.

## Design critic findings

| Finding | Disposition |
| --- | --- |
| Project selection before capture can race with rename/deletion. | Selector resolves inside the same fenced project copy that determines scope. |
| Per-tool publication can precede final batch encoding. | Enclosing T-63 batch permit owns all selected publication and rollback; child results remain private. |
| Concurrent page projections can overrun retention capacity. | Explicit create/append reservations charge pending plus published bytes; stale prepared state selects READ_BUSY and rolls back. |
| UUID cursor namespace undefined after expiry. | Reusable version-8 UUID family is distinct from ordinary version-4 cursors; unknown/expired tokens cannot recapture. |
| Commit-time rejection could expose unpublished IDs in success bytes. | Discard success and select preencoded matching error/whole-batch fallback; validation precedes all nonthrowing commits. |

Critic rereview confirmed the selection, batch, reservation and routing corrections; final completion-path clarification is in the design and verification table. App-level deadline, history/import capture and reservation/lifecycle experiments remain measurable prototype gates.

## Peer validation

Two independent fallback peers completed the full design review. Technical correctness passed; architecture conditionally passed with explicit out-of-lock ARC retirement and scoped capture-completeness clarification. Both corrections are now explicit and agree with T-63’s declared-scope-plus-closure contract. Parent/T-63 identified an additional shared publication correction: combine all selected changes per store before validation, then perform one swap per store. Final delta recheck passed the critic and both independent peers with no remaining must-fix. T-63 confirmed exact `captureScope: ReadCaptureScope` cases `wholePortfolio`, `projects([LocalRecordKey])`, and `selectedQuery` (ordinary narrow reads); reusable views preserve the same wholePortfolio/projects scope value. App-level deadline, coherence and publication experiments remain implementation gates.

## Parent approval gate (completed)

The user approved both designs unchanged in Sentinel_541ceb19e7c8819193d04d23c5263041. Approval covers the new tool/argument/schema plan, scoped retained-view filters, five-minute retention and byte/capacity accounting, committed-store capture/fence, projection/revision rules, and single-writer integration plan. It does not approve tasks, production implementation, push, merge, deployment or the T-2380 CloudKit release prerequisite.
