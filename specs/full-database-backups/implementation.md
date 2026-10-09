# Full database backups — implementation record

Recorded retrospectively on 2026-10-09. T-2431, [draft PR #258](https://github.com/ArjenSchwarz/transit/pull/258). Implemented source baseline: `18858071e56ca615f6bc4719f24e4a8ec4b8c594`, based on merged environment-isolation PR #257 (`58f2cd20`). This document records existing behavior; it is not evidence of prospective spec approval. See [scope-assessment.md](scope-assessment.md) and [decision_log.md](decision_log.md).

## Beginner level

### What changed

Settings → Backups exports everything stored in Transit to a `.transitbackup` file. Import checks a selected file by restoring it in a disposable database, saves a checked recovery copy of the current database, then replaces current data. The flow requires restart afterward.

Mac users can choose a folder and daily time, initially 02:00. The user explicitly confirmed the Mac-only scheduled scope. Transit exports while running and catches up once after a missed time when it next runs. No iOS schedule or exact execution while the app is closed is promised.

Wipe is available in normal Release on all supported platforms. It first saves and verifies a new backup, checks that saved data has not changed, and requires typing `WIPE`. With iCloud enabled, it also checks cloud coverage. Deletion propagates through ordinary synchronization, rather than immediately purging a remote zone.

### Why it matters and key concepts

A backup is only accepted after its contents reproduce the original data in a separate database. This check protects recoverability before import or deletion. Backups are plaintext, including comments and MCP payloads; users must keep their destination private. Published files are retained until the user removes them.

## Intermediate level

### Components and flow

`Services/Backups/DatabaseArchive.swift` and `DatabaseArchive+Restore.swift` cover Project, TransitTask, Milestone, Comment, SyncHeartbeat, MCPWriteReceipt, TaskLinkOccurrence, TaskLinkRemovalEvidence and TaskConsolidationEvent. Every stored scalar and physical relationship is represented; inverses are rebuilt by SwiftData. There are no attachment entities or external-storage attributes in the current schema. The explicit registry and all-entity fixture must change together when the schema grows.

`DatabaseBackupService` captures through a fresh owned saved context. `DatabaseBackupWriter` receives immutable data and performs encoding, bounded file I/O and full CloudKit-free scratch restoration on a serial actor. Manual controls display progress and retain security-scoped access across awaits. No installed model/context crosses executors.

Import validates incoming data, creates a durable verified recovery file, and runs one owned-context delete/insert/save. The final mutation has no suspension point. It rechecks cancellation, availability, saved data, unsaved drafts and maintenance admission after worker awaits. Wipe binds its final file check to the exact archive used for cloud preflight. Failure before the save leaves the original dataset intact; the failed context is rolled back and discarded.

`BackupScheduler` retains folder access through publication, renews stale bookmarks, records success only after verification, shows failures and retries at most hourly. Calendar policy chooses the first repeated DST time and the next valid time for a gap. There is no launch agent or external scheduler.

### Trade-offs

Replacement preserves the archive exactly instead of inventing a merge policy. Historical duplicate UUIDs, unknown enum raw values and cross-project links remain recoverable through physical indexes. Normal synchronized deletion preserves CloudKit infrastructure but cannot prevent later offline edits on another device. Restart avoids stale registered models writing into a replacement. Main-actor saved capture remains synchronous; background work removes the larger encoding/I/O/restore cost, but unusually large captures can still cause a visible hitch.

## Expert level

### Consistency, durability and recovery

Saved capture compares history watermarks before/after and uses precomputed scalar ordering plus persistent-ID ties. Scratch verification keeps insertion order, preserving distinct physical rows whose logical IDs collide. Equality includes raw history and relationship coverage rather than normalized business objects. Actual disk round-trip verification is exercised by the async fixtures.

`DurableBackupFile` bounds reads to 128 MB, uses full file synchronization and parent-directory synchronization, and refuses unsupported durability. Service exports write an exclusively created, advisory-locked `.Transit-<UUID>.pending` file, verify it, then atomically rename it. Destination verification failure cannot publish an archive. Manual picker files are verified before presentation and read back after saving; failed picker output may need removal, but cannot authorize wipe.

`BackupStagingFiles` sweeps only unlocked regular exact-named files older than 24 hours in the selected destination. It checks identity before removal, skips symlinks, active/recent writers and unknown files, and treats directory/per-file cleanup failure as auxiliary. Published backup retention is independent and manual.

`CloudBackupCoverage` paginates the app-private Core Data zone and checks stored fields and relationships. Unknown mappings, cloud-only rows, differences and ambiguous duplicates fail closed. Cloud metadata/default-zone infrastructure and global ID counters are not remotely reset. This preflight is not a cross-device atomic guarantee.

`DatabaseMaintenanceGate` hooks apply only to the installed container. Replacement closes native/MCP mutation admission, pauses listener/connectivity/heartbeat callbacks and requires restart. MCP reservations are archived as history, not reinstalled as executable operations. A durable pre-save journal and hashed retired keys fence retry replay and allow startup to resume namespace rotation. Cleanup failure after a committed save is reported as a committed operation requiring restart; uncertain rollback cleanup also seals edits.

### Architecture impact and limits

The feature uses the container selected by the merged Debug/Release policy. It does not alter store identities, bundle IDs, cloud configuration, defaults domains or MCP ports. Exact file schema/version handling becomes a future compatibility obligation. JSON plus scratch models needs memory beyond the 128 MB file bound, particularly on iOS. Conservative cloud checks may refuse unexpected mappings rather than guessing recovery coverage.

## Completeness assessment

Implemented: complete current-schema round-trip, replacement import, configurable Mac daily exports/catch-up, durable verified backups, normal Release wipe with cloud coverage and explicit confirmation, asynchronous manual/automated verification, stale-stage cleanup, restart/retry guards and visible failure states.

Platform limits: no iOS automated schedule, no closed-app exact 02:00 execution, no immediate remote cloud purge, no global all-device transaction, and no automatic published-backup retention. These limits are explicit in the product guide. Offline device changes can reappear.

Verification limits: destructive checks use synthetic stores only. Actual private cloud wipe/import, deployment, production launch and account/signing changes were not exercised. Native Mac test-host execution previously stalled before main in OS sandbox startup; final Mac validation was compilation only. The retrospective spec workflow is not yet approved/completed.

## Verification and review evidence

- At source commit `18858071`: 24 focused backup/scheduler/manual/staging tests passed, zero failures/skips; strict lint reported zero violations across 740 files. Mac Debug build-for-testing and unsigned Release compilation passed without launch.
- The focused fixtures cover every current entity, duplicate IDs, raw history, physical relationships, disk restore equality, historical cross-project links, failed save/rollback, cancellation and changes across awaits, changed wipe files, malformed/truncated input, scheduler retry/bookmark renewal/DST, locked stage preservation and best-effort cleanup failures.
- Supporting earlier evidence: 24 post-rebase backup/environment/sync/Settings checks passed. The earlier full simulator run reached 1,391 unique passing tests after one targeted retry of an unrelated consolidation UI failure. These are prior runs, not newly rerun evidence.
- Exact source-head automated [review run](https://github.com/ArjenSchwarz/transit/actions/runs/37936160612) succeeded. Its [review content](https://github.com/ArjenSchwarz/transit/pull/258#issuecomment-6081749030) was inspected; no material blocker remained. Optional suggestions concern capture timing, diagnostics and future hardening. Retention and memory limits are documented.
- Documentation-only retrospective changes reuse this evidence because application/test/build sources remain unchanged. No extra heavy suite is run merely to record history.
- The requested retrospective pre-push review checked reuse, quality, efficiency and spec/documentation accuracy. No material source issue was found. The record was corrected to credit the user's explicit Mac-only scheduling decision. Relative documentation links and whitespace were checked; the source/test/build tree was compared with the tested baseline.

## Implementation history

| Commit | Result |
|--------|--------|
| `75ab7101` | Initial archive/import/schedule/Release wipe implementation and synthetic coverage. |
| `59591aea` | Backup/replacement durability, mutation admission and retry recovery hardening. |
| `7da989d2` / `df1f8576` | Listener drain and standalone probe integration. |
| `35a79294` | Background scheduled verification, bookmark lifetime and failed-cleanup protection. |
| `71586cbc` | Async manual verification/progress, final mutation guards and locked crash-stage cleanup. |
| `18858071` | Best-effort listing cleanup, errno diagnostics, exact-restoration explanations and additional regressions. |

Only generic source and result summaries are recorded here. Private records, raw backup contents, logs and local recovery evidence are excluded.
