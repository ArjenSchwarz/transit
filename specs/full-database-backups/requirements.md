# Full database backups — requirements

Recorded retrospectively on 2026-10-09 for T-2431 / PR #258. The user authorized requirements/design work and an implementation gap audit; this does not imply pre-implementation or final artifact approval.

## Introduction

Transit needs recoverable copies of all stored application data before a user replaces or deletes it. The feature provides manual recovery controls on supported platforms and daily backups on Mac, with explicit limits when the app cannot run or cloud state cannot be certified.

## Non-goals

- Merging or deduplicating imported records, changing IDs, or normalizing historical content.
- Automated iOS backups, exact closed-app execution, launch agents or external schedulers.
- Cloud zone/schema reset, counter reset, or an atomic all-device purge.
- Encryption, attachment management where no attachment schema exists, or automatic published-backup pruning.
- Backing up account settings, transient UI state, unsaved drafts or CloudKit mirror infrastructure.

### 1. Complete recoverable archive

**User story:** As a user, I want to export all saved application data, so that I can restore it without losing history or relationships.

**Acceptance criteria:**

1. <a name="1.1"></a>WHEN a saved database is exported, Transit SHALL preserve every stored field and physical relationship in Project, TransitTask, Milestone, Comment, SyncHeartbeat, MCPWriteReceipt, TaskLinkOccurrence, TaskLinkRemovalEvidence and TaskConsolidationEvent, including optional values, duplicate logical IDs and unknown historical raw values.  
2. <a name="1.2"></a>WHEN a file is accepted as a successful backup, Transit SHALL have read the saved bytes, restored them independently and verified equality with the exported saved dataset.  
3. <a name="1.3"></a>IF input is malformed, has unsupported version/relationship targets, exceeds 128 MB, or cannot complete restoration, Transit SHALL report failure without changing the installed database.  
4. <a name="1.4"></a>WHEN exporting, Transit SHALL exclude unsaved drafts and warn that plaintext backups contain private application content; Mac retry reservations SHALL remain historical recovery evidence rather than executable restored requests.  

### 2. Replacement import

**User story:** As a user, I want to import a complete backup, so that I can recover its exact saved data.

**Acceptance criteria:**

1. <a name="2.1"></a>WHEN the user confirms replacement of a validated backup, Transit SHALL first create and verify a recoverable backup of the current saved dataset, then replace all stored application entities without merging or reallocating IDs.  
2. <a name="2.2"></a>IF backup creation fails, cancellation occurs, storage becomes unavailable, an editor has unsaved changes, saved data changes, or an active/unresolved automation write prevents replacement, Transit SHALL refuse replacement and preserve current saved data.  
3. <a name="2.3"></a>IF the database save fails, Transit SHALL preserve the original saved dataset and report failure; IF cleanup remains uncertain, Transit SHALL block further edits until restart rather than claim normal operation.  
4. <a name="2.4"></a>WHEN replacement commits, Transit SHALL report the recovery file location, require restart and block stale native/automation writes; IF subsequent cleanup fails, Transit SHALL disclose that replacement already committed.  

### 3. Configurable Mac schedule

**User story:** As a Mac user, I want a daily backup at a chosen local time and folder, so that I have recovery copies without starting each export manually.

**Acceptance criteria:**

1. <a name="3.1"></a>WHERE Transit runs on Mac, Settings SHALL provide an enable toggle, folder selection and hour/minute configuration with an initial 02:00 time; WHERE it runs on iOS, these automated scheduling controls SHALL be absent.  
2. <a name="3.2"></a>WHILE the Mac app is running, Transit SHALL check daily eligibility once per minute and publish at most one successful export for each due local day; WHEN a due run is missed during sleep/closure, it SHALL perform one catch-up export on next eligible execution.  
3. <a name="3.3"></a>WHEN enabling after today's chosen time, Transit SHALL begin with the next due day; WHEN local time skips or repeats, Transit SHALL use the next valid time or first repeated occurrence respectively.  
4. <a name="3.4"></a>IF folder access or export fails, Settings SHALL show the failure without advancing success and automatic attempts SHALL occur no more often than hourly; WHEN a folder is selected again, the delay SHALL clear.  
5. <a name="3.5"></a>WHEN a schedule succeeds, Transit SHALL show its latest success and retain the uniquely named published backup until the user removes it; stale access credentials SHALL be renewed when resolvable.  

### 4. Backup-required wipe including synchronized data

**User story:** As a user, I want to remove all stored Transit application data, so that I can start again while keeping a verified recovery copy.

**Acceptance criteria:**

1. <a name="4.1"></a>WHERE normal Release or development runs on a supported platform, Settings SHALL offer wipe only after a newly saved backup passes complete verification and the user types `WIPE` and confirms the destructive action.  
2. <a name="4.2"></a>IF cancellation, unreadable/changed backup bytes, changed saved data, unsaved edits, unavailable storage or uncertain recovery coverage occurs, Transit SHALL refuse deletion.  
3. <a name="4.3"></a>WHERE the selected environment permits iCloud, wipe SHALL require active sync and successful online coverage of all cloud application records; unknown mappings, cloud-only/differing records, uncovered relationships or ambiguous duplicate identities SHALL refuse wipe.  
4. <a name="4.4"></a>WHEN wipe commits, Transit SHALL delete all nine saved application entity types and propagate ordinary synchronized deletions with iCloud active, retain counter/mirror infrastructure, require restart and explain that offline/concurrent edits may reappear.  

### 5. Recovery controls and file failures

**User story:** As a user, I want clear progress and failures, so that I know whether a backup or destructive operation actually succeeded.

**Acceptance criteria:**

1. <a name="5.1"></a>WHILE manual backup work is underway, Settings SHALL show progress and prevent overlapping actions; encoding, file I/O and full restore verification SHALL not occupy the UI executor.  
2. <a name="5.2"></a>IF service-export verification fails before publication, Transit SHALL preserve any existing destination; IF the system picker is cancelled or saved-file verification fails, it SHALL not report successful backup or authorize wipe.  
3. <a name="5.3"></a>WHEN exporting to a destination containing orphan stages, cleanup SHALL preserve published backups, symlinks, unknown files and active/recent writers; cleanup failure SHALL not block a new otherwise successful backup.  
4. <a name="5.4"></a>WHEN controls operate, they SHALL use the container and preferences selected by current Debug/Release isolation without accessing another environment's data.  

### 6. Completion and document-provider recovery (2026-10-10 correction)

1. AFTER replacement or uncertain rollback seals editing, Transit SHALL provide an interactive completion screen with restart guidance and Save Recovery Copy controls outside the editing lock.
2. Settings SHALL expose existing feature-owned recovery files; cancelling or failing a copy SHALL preserve the original and allow another copy attempt.
3. Import SHALL report verification, recovery creation and application stages honestly; final atomic saved-data replacement MAY temporarily occupy the UI executor.
4. Wipe SHALL require a newly created, fully verified, durably published app-owned recovery file and a verified user-selected copy. Document-provider readback SHALL not require parent-folder permission or imply remote upload durability.
