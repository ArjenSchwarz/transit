---
references:
  - requirements.md
  - design.md
  - tasks.md
  - decision_log.md
---
# Safe task consolidation implementation

## Beginner level

### What changed

Four MCP tools let a caller preview a consolidation, apply that exact review, preview a whole reversal, and reverse it. A group consists of one surviving task and one to five candidates in the same project. The caller supplies a reason and explains how each original's information is incorporated or retained, then explicitly acknowledges preservation.

Consolidation keeps the original tasks and comments. Unfinished candidates become Abandoned; candidates already Done or Abandoned and the survivor keep their existing status dates. Only explicitly requested survivor description or complete string metadata changes are made. Existing typed task links record the canonical path to the survivor, preserving compatible chains and incoming links.

Task details show saved consolidation history on macOS, iPhone and iPad. The history explains the reason, preservation accounting, recorded changes and canonical paths. Original references open the exact saved task when its UUID identifies one physical task. History viewing adds no native apply or reversal buttons.

### Why it matters

Similar tasks can be consolidated without silently deleting their differing descriptions, metadata, comments or assignments. A preview gives the caller a complete record to inspect. If the relevant saved content changes before application, the write fails and requires a new review.

A whole reversal restores only the changes made by that operation. It is available only when the saved evidence still matches and the operation's newly created link occurrences can be identified exactly. A later edit can make reversal unavailable rather than being overwritten.

### Key concepts

A review is a temporary, server-held plan, not an editable plan supplied by the client. A receipt records the result of a protected write so a lost response can be recovered using the original key. History is a durable record of changed fields and links; it remains available after temporary reviews and receipts expire.

## Intermediate level

### Changes overview

The implementation adds an immutable `TaskConsolidationEvent` to the SwiftData schema and uses value-only planning and saved capture in `Services/TaskConsolidation`. `MCP/Consolidation` supplies strict contracts, retained preview authority, bounded result adapters and app capability construction. `TaskConsolidationHistorySection` consumes the same saved evidence through the app-owned read coordinator.

The tools are `preview_task_consolidation`, `consolidate_tasks`, `preview_task_consolidation_undo` and `undo_task_consolidation`. Their production registration requires the complete preview and write capabilities. They do not extend `mutate_tasks` or add navigation URLs.

### Implementation approach

The preview captures selected originals, raw fields, comments, incident links, canonical dependencies and applicable immutable events inside a stable saved boundary. Supplementary evidence supplies validation and history without enlarging the caller's query selection. Ordinary record values freeze before supplementary refetch so corruption cannot disappear through a context refresh. Fresh full task reads include history and current reversal assessment even when comment output is omitted. Previously retained reads retain their original bytes and coverage.

Pure planners validate selection, same-project physical identity, preservation accounting, canonical chains and the combined graph proposal. The ordinary retained-read index owns the immutable input, evidence and planned deltas. Reviews use the existing eight-root capacity, five-minute expiry and 16 MiB complete representation budget. Preview preparation and response selection must succeed before a review reference becomes visible.

The protected write coordinator owns a fresh clean context. Apply resolves the retained review and revalidates current saved evidence, then stages task changes, actual link occurrences, immutable history and one terminal receipt before one save. The participating writers use the existing coordinator's serialization. Receipt replay precedes review and current-content checks, so the original key can recover a known committed operation after the preview has expired.

Undo reads exact apply history, validates changed raw fields, applied revisions, immutable operation content and physical multiplicity, and removes only attributable created occurrences. It stages inverse history and its receipt with the restored fields before one save. Valid saved inverse history allows a fresh key to report an already reversed operation without inserting another inverse event.

Native and MCP reads share one app-lifetime coordinator: eight unfinished physical workers and a five-second original deadline. Cancellation or timeout does not release capacity until the worker cleans up. Listener stop closes only that listener's admission; native history remains independent. Native state discards stale source generations and coalesces save/import notifications by 100 milliseconds.

### Trade-offs

History stores changed fields rather than complete originals, limiting durable growth while allowing exact raw restoration. Full originals and graph backing remain transient and charged during review. Encoded history has a 256 KiB cap; complete preview/read/write representations are bounded rather than truncated.

The reviewed authority digest covers participating evidence and required dependencies. Unrelated task names or statuses do not invalidate authority; complete graph backing has a separate integrity digest, and the write still replans against a fresh complete graph before effects.

A ninth additive entity keeps the existing persistence model. No independent event expiry, relationships, cascade deletion, uniqueness constraint or mutable reversal flag is introduced. Reversal is derived from validated immutable apply and inverse events.

## Expert level

### Technical deep dive

`p1` binds normalized immutable input and semantic authority evidence, including raw participating originals, covered `r1` revisions, relevant event content, planned deltas and exact incident occurrence multiplicity. Opaque persistent identifiers compare by decoded identity, and unordered fetch enumeration is normalized. Complete retained graph backing is separately verified and charged; neither opaque JSON order nor unrelated graph names become accidental authority.

`o1` validates immutable event payload and scalar participants, event kind and physical multiplicity. Transient SwiftData persistent identifiers are diagnostic evidence rather than content hash input because they can change across a save. Existing generic `r1` behavior is preserved. Raw status, date and metadata evidence fails closed when corrupt; description null and omission retain distinct meanings. Imported apply history permits survivor description/metadata deltas and candidate unfinished-to-Abandoned status/date deltas only. It rejects standalone dates, completion-date removal and inconsistent closure instants, while preserving omitted unchanged dates and transient preview placeholders.

Saved capture uses an observed boundary, an explicit empty event-store proof and complete participant/history closure. Participant discovery queries bounded 128-ID chunks, including optional scalar slots without matching nil; one grouped operation index is reused for validation and projection. The aggregate capture charge includes graph, events, originals, history projections and retained owners. Encodes checkpoint the original operation deadline and cancellation, and publication applies the exact outer wrapper limit. No hidden truncation or secondary history budget weakens the complete-representation contract. Selection failures report bounded offending UUIDs and reasons. Review and history unavailability have distinct codes, registered in modern recovery classification; imported decode/validation failures are normalized as malformed history rather than storage failure.

The final synchronous owned write phase performs the saved recapture and graph validation before allocating operation/link identities or mutating domain values. Staged revisions and history describe actual inserted occurrences and dates from that phase. Outcome recovery uses existing protected write receipt and durability-probe semantics, including truthful uncertainty when commitment cannot be established.

Whole reversal compares current saved content against the applied operation and restores only recorded changed fields. It preserves pre-existing tuples and duplicates, and rejects missing, modified or ambiguous attributable created occurrences. Already-reversed recognition requires exact valid inverse history; imported events relabeled as the wrong known kind cannot qualify as apply evidence. These checks describe current matching content, not a monotonic detector of an edit-and-restore sequence.

### Architecture impact

Foundation read lifecycle contracts are shared across platforms, while transport and MCP provider adapters remain macOS-gated. TransitApp supplies one shared native reader and constructs production consolidation capabilities from the existing container, snapshot store, allocators and write coordinator. Native UI receives value observations; `@Model` objects are resolved only for unique saved navigation in the UI context.

### Potential issues and limits

The commitment guarantee is local to one owned save and participating writers. Outside imports or independent contexts can race; there is no distributed atomicity, global writer fence, cross-device transaction or compensating persistence redesign.

A matching current content state permits reversal; the feature does not detect temporal ABA. Ambiguous UUIDs, malformed imported history, missing participants, conflicting graph paths and complete evidence over the budget produce explicit unavailable results. These diagnostics are preferable to guessing a survivor or discarding history.

Closed old-store migration and all verification use owned synthetic fixtures and development hosts. They do not activate or verify production CloudKit schemas, mutate live Transit tickets, deploy an app or establish distributed guarantees.

## Completeness assessment

Source implements the approved selection and preservation policy, four strict tools, bounded retained previews, current saved revalidation, one-save apply/history/receipt, exact whole reversal and recovery, shared read lifecycle, additive history schema and read-only native history in all existing detail layouts.

The four internal source review roles accepted the corrected implementation and documentation. Full macOS verification at `484dd2c` passed 2,630 declarations / 3,431 expanded cases, with six exact intentional opt-in skips. The subsequent cross-platform startup correction at `ffbf62cf` passed macOS and iOS builds, 12 focused macOS cases, and strict lint across 719 files with zero violations. These focused checks supplement the earlier full-suite proof; they do not relabel it as a full final-head run.

Rendered macOS verification remains blocked before any feature declaration executes: XCTest times out while enabling automation mode. Developer mode is disabled according to a harmless read-only check; no machine-wide setting was changed. The fresh full iPhone unit suite at `ffbf62cf` passed 1,351 declarations / 1,455 expanded cases, zero failures/skips, with exact discovery and owned host drainage. Full iPhone UI and focused iPad verification remain in progress. Tasks 17–20 remain incomplete until their required native gates pass. See the decision log for exact results, diagnostic failures, skips and host-drain evidence.
