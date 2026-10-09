# Full database backups — observed decision history

Recorded retrospectively on 2026-10-09 for T-2431 / PR #258. These are decisions evidenced by code, comments, the backup guide and branch commits. They were not approved through a prospective spec workflow. Retrospective scope approval remains pending in [scope-assessment.md](scope-assessment.md).

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

The initial implementation omitted a repository spec and implementation record. On 2026-10-09 the user required a spec for every substantial feature, routed through `starwave:creating-spec`. That policy is recorded in `CLAUDE.md`. This retrospective corrects repository history without inventing prior phase approvals. New approvals must be recorded when actually received.
