# T-2455: Scope selected-read comment fetches

## Problem and evidence

Full selected task reads currently fetch every store comment before filtering to selected logical task IDs. A live read timed out on 2026-10-14 after a healthy one-hour baseline; captured stacks later showed the MainActor capture inside this whole-store SwiftData/CoreData comment materialization. This identifies a concrete unnecessary-work path, not proof of an uptime leak, CloudKit causation, or a complete explanation of every historical timeout.

The user explicitly approved implementing this scoped fetch after the read-only investigation. The installed app is not changed by this branch. Existing ticket T-2455 remains the tracking item; no duplicate ticket is needed.

## Scope and invariants

- Move the existing selected-read logical-owner-ID filter into the comment store fetch. Preserve every physical comment owned by any task with a selected logical ID, including duplicate task UUIDs and duplicate comment UUIDs.
- Complete-portfolio reads retain the broad comment domain, including orphan diagnostics and scoped portfolio identity closure.
- includeComments controls output bodies only. Full revisions still require complete selected-task comment state.
- Preserve saved-only reads, persistent history fences, fresh captures after edits/reparenting, revision computation, snapshot identity, frozen replay, typed storage failures, physical worker cleanup and existing deadlines.
- Do not change stores/schema, sync settings, timeouts, permit counts or installed app lifecycle. No live store copies or cloud experiments.

## Investigation checkpoint

The comment-fetch injection now receives its FetchDescriptor so isolated tests can observe actual materialized rows. Before optimization it still receives the original unrestricted descriptor. Existing failure-injection tests are mechanically adapted to the descriptor seam.

Regression fixtures use temporary on-disk stores with all nine entities, CloudKit disabled and production history fencing. The primary regression requires exactly two selected comment rows despite 1,000 unrelated comments. Additional parity checks cover batches, duplicate logical owners/comment IDs, edited/reparented/orphan/pending comments, portfolio coverage, empty/summary reads and concurrent saved changes.

## Resolution and validation

Red checkpoint: six initial regression tests executed; five passed and the selected-row assertion failed as expected (1,002 fetched versus two required). The expanded duplicate-owner, bulk/summary and performance fixtures then passed against the scoped predicate. No long-uptime resolution is claimed from synthetic tests.


### Final implementation

Selected reads construct a store predicate over unique selected logical task IDs through `MCPReadCommentFetch`. Complete portfolios retain the unrestricted descriptor. Both use saved-only fetching. Existing logical scope filtering, canonical/physical comment indexing, selected record/revision construction and history boundary checks are unchanged. The descriptor seam supports observing real fetched rows; existing injected failure/serialization tests ignore the new descriptor argument intentionally.

### Validation

- Red: one expected materialization assertion failed among six initial tests (1,002 rows fetched instead of two); the other five passed.
- Green: all nine new tests and 69 surrounding targeted macOS tests passed, zero failures/skips (78 total). Includes capture, selected/portfolio scope, ownership, projection, history fences, consolidation, snapshot/replay and coordinator cleanup.
- Lint: zero violations across 751 Swift files and host validation guards. No broad UI rerun or full-suite claim. The product path and new tests are macOS-only; no iOS behavior changes are introduced.
- Four targeted source review areas found no blockers. A review-requested test selects one physical duplicate owner across projects and preserves both owners' logical canonical evidence.
- Exact Swift source bytes in the isolated test mirror were compared with the feature worktree after final verification.

### Isolated performance comparison

Three synthetic tasks, 5,002 saved comments, one selected task with two comments; temporary on-disk nine-entity store, CloudKit disabled, production history fences. One unmeasured warm-up per path followed by four rotated scoped/unrestricted captures. Debug build; setup excluded. Every capture produced identical task record bytes/revisions and retained comment evidence. Materialized rows were exactly two versus 5,002 on every iteration.

Median total capture: unrestricted134.845ms, scoped31.208ms (approximately76.9% reduction in this fixture). Timings are supporting measurements, not assertions or live performance guarantees. This does not explain all prior timeout causes, prove an uptime leak, or prove sufficient performance after deployment under live CloudKit load.

### Remaining validation and tracking

User-controlled deployment and observation with the existing content-free diagnostics remain necessary. No restart, deployment, live store/settings changes, live probes or ticket mutations were performed during implementation. T-2455 remains the sole tracking ticket; live updates are excluded by this turn's scope. The separate empty-originals task-refetch optimization is not included.
