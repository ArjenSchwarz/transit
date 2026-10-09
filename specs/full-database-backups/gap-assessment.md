# Full database backups — requirements/design gap assessment

Recorded retrospectively on 2026-10-09 for T-2431 / PR #258. Self-audit against [requirements.md](requirements.md) and [design.md](design.md); peer reviews were explicitly waived by the user. Source baseline remains `18858071`. This assessment does not claim a live-cloud destructive test or new execution of prior evidence.

## Traceability

| Criteria | Implementation checked | Evidence and qualification |
|----------|------------------------|----------------------------|
| 1.1 | Explicit nine-model schema, row DTO fields, physical relationship indexes and restore assignments match all stored model properties. No attachment/external-storage attribute exists. | Full fixture equality, duplicate-ID targets, historical cross-project links, unknown raw values and consolidation slot gaps. |
| 1.2, 5.2 | `DatabaseBackupIO.verify/export`, durable stage/rename, manual prevalidation and saved-file readback. | Full disk/async round-trip, failed verification preserving destination, malformed/truncated input. Manual platform picker failures refuse success; staging guarantees apply to service exports. |
| 1.3 | Format/application/index validation, incremental bounded read and isolated restore equality precede mutation. | Invalid version/relationship and malformed input tests. 128 MB guard inspected; exact-limit/one-byte-over fixture is not in the focused suite. |
| 1.4 | Fresh saved capture, native export draft check, plaintext warning and reservation history. | Saved-history fixture and explicit MCP archive/rotation code. Unsaved drafts are excluded, not a recovery source. |
| 2.1 | Incoming scratch restore precedes current-dataset recovery export; one owned-context replace/save with unchanged IDs. | Complete replacement and invalid-incoming/no-recovery fixtures. |
| 2.2, 4.2 | Final no-await cancellation/availability/maintenance/saved-data/draft guards; wipe file bound to exact preflight archive. | Paused-writer interruption variants, cancelled wipe and changed-file tests; MCP quiescence and reservation snapshot code inspected. |
| 2.3 | Owned failed context rollback/discard; uncertain journal cleanup seals writes and preserves both errors. | Save-failure preservation and rollback-cleanup fixtures. |
| 2.4 | App hooks disable autosave/native/automation writes, stop/drain services and rotate retry namespace; success reports recovery path/restart. | Service/lifecycle/coordinator source, reservation rotation tests from earlier verification; not a new production launch. |
| 3.1 | Mac-only Settings toggle/time/folder controls default to 02:00. | Existing Settings UI fixture proves iOS lacks schedule controls; Mac build compiles controls. |
| 3.2–3.3 | Minute runtime check, one in-flight guard, enable timestamp, latest-due/last-success policy and DST choices. | Catch-up/local-calendar spring-gap/autumn-repeat fixture. Closed apps are not scheduled processes. |
| 3.4–3.5 | Security-scope lifetime, renewable bookmark, persistent visible error, one-hour deadline, unique retained files. | Missing-folder/backoff and failed-export/recovery/bookmark/access-close fixtures. |
| 4.1 | Normal Settings route, newly saved actual-file-verified wipe preparation, typed confirmation. | Release compilation, existing Settings UI availability and service confirmation refusal. No live wipe button was exercised. |
| 4.3 | Actual configured cloud identifier, active-sync check and paginated private-zone coverage with fail-closed mappings/duplicates. | Synthetic cloud-only/difference/duplicate/zone coverage fixtures plus source inspection; deployed cloud mapping remains unverified. |
| 4.4 | Explicit deletion of nine entity types; normal SwiftData save, preserved counter/mirror infrastructure and restart. | Synthetic wipe/save-failure checks; actual iCloud deletion propagation is unexercised. |
| 5.1 | Serial writer owns encoding/I/O/full scratch restore; progress and overlap guards in Settings. | Background-executor and paused-worker fixtures; main saved capture remains synchronous. |
| 5.3 | Exact-named old regular stage cleanup, nonblocking lock and inode recheck, best-effort failures. | Active/recent/symlink/published preservation and directory-list failure regressions. |
| 5.4 | Existing selected container/defaults consumed; no environment service, bundle/store/signing/port changes. | Comparison with merged #257 plus earlier post-rebase environment/sync/Settings checks. |

## Findings

No important implementation omission was found against this scoped requirement set. No application/test/build source change is needed for this audit. The missing requirements/design and canonical instruction file were repository-history gaps; this change supplies them and transfers all unique guidance into `AGENTS.md`, updating its readers and removing the duplicate `CLAUDE.md`.

Remaining verification gaps are explicit rather than treated as passes:

- Live CloudKit mapping/propagation and cross-device concurrency were not exercised. Unexpected mappings fail closed, and offline edits can reappear. A future authorized non-destructive mapping check can establish compatibility; this task does not authorize live deletion.
- Exact 128 MB boundary, nil-task comment restoration and near-limit memory/capture timing lack dedicated measurements/fixtures. Nil-project tasks already round-trip; complete restore equality rejects extra/missing rows. These are targeted coverage improvements, not observed source defects.
- Mac app-host tests remain blocked by the earlier pre-main OS sandbox stall; Mac compilation passed. No global security settings were changed.

## Product scope decisions

The user confirmed Mac-only automated scheduling. Runtime catch-up, replacement import, manual retention and ordinary synchronized cloud deletion are delivered choices explained in the decision log. Exact closed-app 02:00 execution, merge import, encrypted files and immediate account-wide cloud purge would change this scope; no such expansion is silently added. No new material product decision is required to finish the requested documentation/audit.

## Evidence reused

The unchanged source passed 24 focused backup/scheduler/manual/staging tests, strict lint (0/740), Mac Debug build-for-testing and unsigned Release compilation. Supporting prior environment/Settings and full simulator evidence remains qualified in [implementation.md](implementation.md). The requirements/design self-review checked EARS outcomes, field/relationship coverage, failure gates, executor boundaries and these traceability rows. No peer review or additional heavy suite ran for this documentation audit.

## Design explanation self-check

Beginner: a file must prove it can recreate the saved data before Transit accepts it as recovery evidence; a confirmed import or wipe changes data only after that proof. Platform and cloud limits are visible rather than promised away.

Intermediate: saved contexts produce immutable archives; the serial writer validates durable files in a separate store; final unsuspended mutation gates reject changes across asynchronous work. Runtime scheduling and restart admission share the selected environment.

Expert: physical-index equality, saved-history fencing, atomic publication, cloud coverage and durable retry-namespace rotation address different consistency boundaries. They do not create a global cloud transaction or a memory-capacity guarantee. Explaining the design at these three levels exposed no additional core omission; qualified verification gaps above remain.
