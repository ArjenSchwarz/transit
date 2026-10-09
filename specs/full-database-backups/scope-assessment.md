# Full database backups — retrospective scope assessment

Recorded: 2026-10-09. Ticket: T-2431. Draft PR: #258.

This record was created after implementation. No prospective spec or phase approvals existed for this feature. It documents the delivered code and the requested corrective workflow; it does not backdate planning or claim approval of implementation choices.

## Request and current scope

The user requested complete database import/export, a configurable automated export schedule (daily at 02:00 as an example), and an all-data wipe including iCloud that requires a successfully created recoverable backup. Wipe must be available in normal Release.

The user subsequently confirmed, “I think we can limit the scheduled version of the backups to the Mac version.” Mac-only automated scheduling is therefore confirmed scope; manual import/export and backup-required wipe remain cross-platform. This confirmation does not constitute approval of the other retrospective spec phases.

The branch implements versioned archives of all nine SwiftData entities, replacement import, Mac runtime daily scheduling, and a backup-required wipe with conservative cloud coverage checks. Settings exposes manual operations on Mac, iPhone and iPad. Existing code and operational limits are described in [implementation.md](implementation.md) and [../../docs/database-backups.md](../../docs/database-backups.md).

## Routing assessment

| Trigger | Assessment |
|---------|------------|
| User-owned ambiguity | The original request did not settle merge versus replacement import or immediate cloud purge versus ordinary synchronization. Mac-only scheduling was subsequently confirmed by the user. Other delivered choices are observed implementation decisions, not earlier phase approvals. |
| Expensive to reverse | **Fires.** Version 1 creates a persisted recovery file format that future versions must interpret. Backup verification and explicit confirmation also establish the authorization boundary for irreversible deletion. |
| Contested architecture | A runtime scheduler and an external scheduled process have different guarantees. A remote zone reset and ordinary synchronized deletion have different safety and recovery properties. The record must explain the delivered choices rather than silently treating alternatives as equivalent. |

Recommendation: **full retrospective spec**, with concise requirements, design, decision history and implementation/task mapping. The persisted format and destructive-operation boundary justify full depth independently of code size.

## Review boundary

Scope approval is pending. The requested `starwave:creating-spec` workflow says, “Each phase builds on the previous one and requires explicit user approval before proceeding.” Requirements, design and task planning are not marked approved or complete. Independently requested implementation documentation and pre-push review can proceed while this decision is pending.

The existing `feature/full-database-backups` branch and draft PR remain the implementation branch; no second branch or fictional ready-for-implementation handoff is needed. Tracker connectivity currently prevents a verified status update; no uncertain write is repeated.
