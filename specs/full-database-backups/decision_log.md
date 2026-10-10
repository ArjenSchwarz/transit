# Full database backups — observed decision history

Recorded retrospectively on 2026-10-09 for T-2431 / PR #258. These are decisions evidenced by code, comments, the backup guide and branch commits. They were not approved through a prospective spec workflow. The user subsequently authorized requirements/design and gap-audit work; exact workflow authorization is recorded below and in [scope-assessment.md](scope-assessment.md).

| Observed choice | Reason and consequence | Evidence |
|-----------------|------------------------|----------|
| Exact nine-entity archive using physical row indexes | Complete recovery must preserve duplicate logical IDs, raw historical values and relationships; business-rule normalization would lose stored data. No attachment/external-storage attributes exist in the current schema. | `DatabaseArchive`, `DatabaseArchive+Restore`; all-entity, duplicate-ID and cross-project-link fixtures |
| Replace on import | The archive restores a whole database, with no merge conflict policy or fresh ID allocation. Existing data first receives its own verified recovery file. | `DatabaseBackupService.replace`, exact restore tests |
| Daily scheduling on Mac while the app runs | The user explicitly confirmed limiting scheduled backups to Mac. Runtime calendar checks provide a proportionate personal-app flow without a helper. Sleeping/closed apps catch up on next run; iOS cannot promise arbitrary exact-time background execution. | User scope refinement: “I think we can limit the scheduled version of the backups to the Mac version”; `BackupSchedule`, `BackupScheduler`, backup guide |
| Release availability | The user's request explicitly required normal Release wipe rather than a development-only control. | `SettingsCategory`, `SettingsView`, `DatabaseBackupView` |
| New durable backup, full isolated restore and typed `WIPE` | Deletion requires evidence that the exact unchanged dataset can recover, followed by explicit destructive confirmation. Failed/cancelled verification cannot authorize mutation. | `DatabaseBackupView`, `DatabaseBackupService`, `DatabaseBackupIO` |
| Conservative cloud coverage; ordinary synchronized deletion | A local file cannot authorize deleting unseen cloud data. Unknown, differing, cloud-only or ambiguous duplicate rows refuse wipe. Normal SwiftData deletion preserves mirror infrastructure; no global transaction or immediate remote purge is claimed. | `CloudBackupCoverage`, backup guide |
| Retain counters and cloud infrastructure | Counter reuse can collide with stale devices. Offline edits can reappear; zones/schema are never reset. | Cloud coverage exclusions and backup guide |
| Background encoding, I/O and scratch restore | Manual and scheduled verification otherwise block UI execution. Only Sendable archives/bytes/URLs cross to the writer; installed contexts/models stay owned by their executor. | `35a79294`, `71586cbc`; writer and async interruption tests |
| Locked staging, verify before rename, conservative best-effort sweep | Failed verification must preserve destinations. Crashed stages must not accumulate indefinitely or prevent a new backup; active/recent/unknown files and published backups are preserved. | `71586cbc`, `18858071`; staging regression tests |
| Restart and retry-namespace rotation after replacement | Cached editors and executable old MCP reservations must not repopulate replaced data. A staged journal permits interruption recovery; uncertain cleanup blocks edits. | `DatabaseMaintenanceGate`, app backup lifecycle, MCP reservation/coordinator changes |
| Manual retention and 128 MB bounded file reads | Published backups are retained for the user to manage. The bound refuses oversized archives; decoded models can require additional memory. This does not promise near-limit iOS performance. | `DurableBackupFile`, backup guide |

## Process correction

The initial implementation omitted a repository spec and implementation record. On 2026-10-09 the user required a spec for every substantial feature, routed through `starwave:creating-spec`. That policy was initially recorded in `CLAUDE.md` and is now preserved in canonical `AGENTS.md`; the duplicate instruction file is removed. This retrospective corrects repository history without inventing prior phase approvals. New approvals must be recorded when actually received.

## Quick decisions

| Date | Decision | Authority and rationale |
|------|----------|-------------------------|
| 2026-10-09 | Author retrospective requirements/design and audit the implemented feature. | User: “do the requirements and design and use that to see if you missed any important parts.” This authorizes current work, not fictional earlier approvals. |
| 2026-10-09 | Skip peer reviews for this documentation/audit pass. | User: “You can skip the peer reviews though.” Self-review and source/evidence traceability remain required. |
| 2026-10-09 | Keep the existing `full-database-backups` spec path and PR branch. | The user continued this exact feature/spec task; a new name or branch would fragment history. |
| 2026-10-09 | Use `AGENTS.md` as the sole repository instruction source. | Explicit user standard relayed by the coordinator; preserve all unique guidance and redirect existing readers. |

## ADR 1: Exact physical-row versioned recovery

Status: observed delivered design, recorded retrospectively; not a claimed prospective approval.

A UUID-upsert archive would collapse existing duplicate identities; business-rule cleanup would alter raw history. Version 1 therefore stores scalar row arrays and physical relationship indexes, validating full isolated restoration before acceptance. The consequence is a compatibility obligation for exported files and an explicit schema registry, rather than automatic arbitrary-schema recovery.

## ADR 2: Replacement import with recovery and restart

Status: observed delivered design, recorded retrospectively.

Merge import would require conflict and history policies beyond whole-database recovery. Replacement preserves the file exactly, first saves the current dataset recoverably, then performs one owned-context save. Registered editor models and old executable MCP keys cannot safely remain active afterward, so mutation admission closes and restart/namespace rotation protects recovery. This costs a restart and retains a separate recovery file.

## ADR 3: Covered cloud deletion through normal synchronization

Status: observed delivered design, recorded retrospectively.

A remote zone reset could delete unseen records and break mirror/counter infrastructure without proving the local backup covers them. Wipe instead requires online coverage and deletes saved application entities through ordinary synchronization. It deliberately refuses unknown or differing cloud data; other devices must be quiescent and offline edits can reappear. This provides recoverable deletion without claiming immediate globally atomic cloud purge.

## Audit outcome

[gap-assessment.md](gap-assessment.md) maps current requirements to implementation and qualified evidence. No important source omission was observed; documentation and canonical instruction gaps are corrected. Live-cloud compatibility, near-limit measurements and a few targeted boundary fixtures remain verification limits rather than claimed passes.

## 2026-10-10 user-tested corrections

User confirmed development build 4 imports work after restart; the frozen-looking locked UI and inaccessible private recovery path are usability defects. User then reported wipe preparation failing with “The backup folder could not be opened for durable save.” Source traces this to parent-directory fsync after document-picker save. Retain strict app-owned durable recovery as wipe authority and verify selected-document contents independently. Remote provider upload is outside this guarantee. The authorized fix updates PR #258; no new phone deployment or live destructive operation is authorized.

Testing correction: the first picker UI test incorrectly assumed a Cancel button on the initial On My iPhone screen. Screenshot inspection showed the actual native sheet. The simulator did not expose the remote Files controls in Transit’s accessibility tree, so app-owned UI coverage is separated from unverified native save/cancellation instead of relying on brittle coordinate assertions. No native-copy outcome is claimed from presentation alone.

## Mac scheduled-folder permission correction — 2026-10-10

User testing found `Operation not permitted` when creating the scheduled staging file. The app configurations granted selected files read-only access and omitted app-scoped bookmark capability. Mac signing now grants read/write access only to user-selected resources plus persistent app-scoped bookmarks, for local Development, opt-in Development cloud, and Release. Phone entitlement inputs remain separate. No Full Disk Access, global folder entitlement, or security-policy change is required. Existing read-only folder grants may require reselection.

Folder selection holds the system security scope while creating a bookmark and checking an exclusive disposable staging file on the background executor (write, full file flush, directory flush, removal). Only success replaces the previous folder/bookmark. Scheduler resolution retains the scope until its background verified publication finishes, renews stale bookmarks while scoped, and closes access on every completion/error path. Existing schedule/defaults values and catch-up/retry semantics remain unchanged. A native time-only field with stepper replaces the hour/minute menus, supports keyboard entry and the system locale’s 12/24-hour format. A neutral date anchor represents only wall-clock fields; schedule execution still uses the Mac’s local calendar including its existing DST policy.

Focused unit fixtures and configuration guards are distinct from native selection/relaunch acceptance; validation results are recorded in the implementation record.
