# Full database backups — design

Recorded retrospectively on 2026-10-09 for T-2431 / PR #258, under the user's authorization to write requirements/design and audit the implementation. Final document review is not represented as a prior approval. Requirement IDs refer to [requirements.md](requirements.md); rationale and approval history live in [decision_log.md](decision_log.md).

## Architecture and integration

| Area | Integration and invariant |
|------|---------------------------|
| Recovery subsystem | `Services/Backups/` owns versioned archive, isolated verification, publication, replacement gates, cloud coverage and runtime scheduling. |
| Settings | `SettingsCategory.backups`, `SettingsView` and `DatabaseBackupView` expose normal Release controls. Reuse grouped Settings forms, native pickers and destructive confirmations. iOS hides the schedule section. |
| App lifecycle | `TransitApp` constructs a scheduler from its selected container and starts it only where persistence policy permits background services. `TransitApp+BackupLifecycle.installBackupMaintenance` installs hooks only for that container; scratch stores never trigger installed-app shutdown. |
| Mutation surfaces | `DatabaseMaintenanceGate`, `PersistenceAvailability`, save helpers, task/project/milestone/consolidation/link services, App Intents and MCP admission reject writes after replacement. Root and Settings scenes disable stale controls. |
| MCP recovery | The app-owned coordinator checks active/unresolved writes, stages namespace replacement before database mutation, and finishes durable rotation afterward. Startup resumes interrupted rotation; old hashed keys remain retired. |
| Environment | Consume merged #257 container/defaults selection. Do not change identities, cloud containers, ports, signing or live store configuration. |

## Archive and executor contracts (1.1–1.4, 5.1)

Version 1 JSON records all nine current entity types in explicit row arrays. Scalar values remain raw, including malformed historical JSON, unknown enum strings, optional values, duplicate UUIDs and consolidation slot gaps. To-one relationships use optional physical row indexes; inverses are rebuilt by SwiftData. No current model has an attachment or external-storage attribute. Reject unsupported format/application identifiers or out-of-range relationship indexes; do not apply new-record business-rule validation to historical recovery.

Saved capture owns a fresh context on the UI actor and fences persistent history before/after fetching. Precompute scalar sort keys and persistent-ID tie-breakers; map relationships once. For restore verification, retain the CloudKit-free in-memory container, save inserted rows, and recapture using insertion-order persistent IDs before exact equality. This catches unintended extra rows as well as missing fields. Reservation JSON remains evidence, not executable restored state.

Only Sendable archive DTOs, bytes and URLs cross to `DatabaseBackupWriter`. Encoding, reads, durable writes and full scratch restore execute on its serial actor. Installed contexts/models remain executor-owned and non-Sendable. Saved capture and the final unchanged-data check remain synchronous; there is no timing guarantee for very large stores.

## Durable publication (1.2–1.3, 5.2–5.3)

Bound encoded files and incremental reads to 128 MB. Service exports create an exclusive non-followed stage in the destination directory, hold its advisory lock, write and fully synchronize it, read/restore/compare, then rename atomically and synchronize the directory. Verification failure leaves the destination untouched. A post-rename directory failure reports failure conservatively even if a valid file is already visible.

Manual exports prevalidate before the system document picker and read back and test-restore its saved document before success. Picker output is outside the service's staged-publication guarantee; a failed output may require removal but cannot authorize mutation. Security-scoped access stays open through asynchronous work. A separate app-owned durable copy is required for wipe; selected-document access neither permits parent-directory synchronization nor guarantees provider upload.

Sweep only exact `.Transit-<UUID>.pending` regular files older than 24 hours. Acquire a nonblocking lock, recheck device/inode before removal, and skip symlinks, active/recent writers and unknown entries. Directory and per-file cleanup failures are best effort. Never prune published backups.

## Import and wipe transaction (2.1–2.4, 4.1–4.4)

Import validates incoming bytes before creating a new current-data recovery file. Wipe begins with a newly saved actual-file-verified export and typed `WIPE`. For iCloud-capable environments, require active sync and page the selected container's private Core Data zone to certify each cloud user record's scalar and relationship coverage; reject unknown zones/mappings, unbacked records, differences and duplicate identities. Exclude mirror records, heartbeat traffic and ID counter infrastructure from cloud user-data coverage; never perform a remote zone/counter reset.

After worker/cloud awaits, bind wipe to the exact preflight archive and reread the file. Immediately before deletion, check cancellation, availability, maintenance admission, exact saved archive/reservation equality and shared-context unsaved changes. Stage the MCP replacement journal, then delete/insert/save through one owned context with no suspension point. A failed context is rolled back and discarded. Failed journal cancellation blocks edits and reports both errors. A committed save cannot be reported as rolled back merely because finishing cleanup fails.

After commit, disable main-context autosave and stale editing, stop heartbeat/connectivity, drain the Mac listener and retire prior retry keys. Require restart. Ordinary SwiftData deletions propagate to iCloud; do not reset zones/schema/counters or claim an atomic cross-device purge.

## Mac calendar and folder contract (3.1–3.5)

Persist the toggle, local hour/minute, enable timestamp, bookmark, last success and retry deadline in the selected bundle's defaults. Resolve and retain directory access across worker publication, renewing stale bookmarks. Check every minute with one in-flight export. Compute the latest eligible daily occurrence using next-valid/first-repeated DST policy; skip occurrences before enable time and coalesce missed days. Only verified publication advances success; failures persist visible state and a one-hour delay. Folder reselection clears that delay. No extra process is installed.

## Errors and user-visible outcomes

| Failure | Result |
|---------|--------|
| Invalid/oversized/unrestorable input | Show failure; installed data untouched. |
| Capture changed, drafts present, cancellation or unavailable storage | Refuse mutation; retain any completed recovery file. |
| Unsupported full synchronization for service/app-owned recovery | Refuse publication and wipe; selected provider copies are only readback verified. |
| Offline/uncovered/differing cloud records | Refuse wipe; user can allow sync to finish and retry. |
| Database save failure | Original saved dataset retained; discard failed context. |
| Cleanup uncertainty | Block writes until restart; distinguish pre-commit failure from committed replacement. |

## Testing strategy and remaining measurement

Use retained synthetic, CloudKit-disabled stores. Map criteria and qualified evidence in [gap-assessment.md](gap-assessment.md). Round-trip equality is the central invariant: generate parameterized fixtures with duplicates, unknown values, optional/dangling relationships and scalar history through Swift Testing; preserve exact rows and never normalize inputs. Current example fixtures cover these families; broad randomized generation is not required for this release.

Inject writer pauses, save failures, directory-access renewal and cleanup failures to verify interruption, rollback, hourly retry and publication behavior. Use synthetic CKRecords for coverage refusals; use explicit local calendars for spring gaps/autumn repetition. Release availability and environment binding use existing build/Settings evidence. Never exercise live deletion merely to increase coverage.

Risk: near-limit JSON plus scratch models may exceed iOS memory headroom | Verify: synthetic volume measurement before making a capacity guarantee | If wrong: refuse unsupported sizes or use Mac recovery; do not authorize mutation from incomplete verification.

Risk: Core Data cloud field mapping may differ on deployed schemas | Verify: compare authorized non-destructive mapping evidence before claiming live compatibility | If wrong: preserve fail-closed refusal and adapt explicit mapping without remote reset.

## Research constraints

Apple's [SwiftData synchronization documentation](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices) establishes CloudKit-backed automatic synchronization; [TN3163](https://developer.apple.com/documentation/technotes/tn3163-understanding-the-synchronization-of-nspersistentcloudkitcontainer) describes scheduled setup/import/export events. This supports treating remote completion as asynchronous. Apple's [BGTaskRequest.earliestBeginDate](https://developer.apple.com/documentation/backgroundtasks/bgtaskrequest/earliestbegindate) is a scheduling request, not an exact execution promise; the confirmed Mac-only runtime scope avoids adding an iOS background contract.

## Completion and picker boundary correction — 2026-10-10

The editing admission lock remains sealed until restart. A pure recovery screen replaces editing views at each window root and can export verified original recovery bytes without querying or changing the installed database. Feature-owned BeforeImport/BeforeWipe UUID files remain discoverable after restart; arbitrary private files and symlinks are excluded. Import reports stages and yields before the final revalidated synchronous transaction, without introducing suspension into mutation.

A document-picker URL authorizes the selected document, not its directory. Manual copies receive bounded readback/full restore verification without parent-directory flushes. Wipe additionally publishes the same exact archive in app-owned storage using existing full file sync, verified staging, rename and directory sync. Final wipe rereads this durable private copy and rechecks saved-state equality. The selected provider copy is extra recovery access; its upload/remote durability is not guaranteed. No broader folder permission is requested and durability failures still refuse wipe.
