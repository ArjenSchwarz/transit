# Safe task consolidation — requirements

Status: **draft for requirements approval**. Scope/name approved at `2bc58bbd`; the product choices below await this gate. Design, tasks and implementation are not authorised.

## Introduction

Transit users currently reconcile duplicate work by closing tasks and maintaining canonical mappings in prose. Safe task consolidation lets a caller review the preservation and closure of a small explicit group while retaining the originals as understandable history. The feature builds on T-1734's typed duplicate links and canonical resolution.

## Proposed product choices

These are recommendations for this gate, not conclusions implied by scope approval.

| Choice | Proposed initial behaviour |
| --- | --- |
| Group | One survivor and one to five candidates, six total, all in one project. Assignments remain unchanged. |
| Status | Abandon unfinished candidates; leave Done/Abandoned candidates and survivor status unchanged. No optional survivor status edit in this operation. |
| Content | Optional caller-authored survivor description/metadata edits, with explicit preservation accounting for every candidate. Other survivor fields remain unchanged. |
| Undo | Whole operation only; reject while current covered content of an affected task or required relationship evidence differs from the recorded applied state. No force or selective undo. |
| History/retention | Keep operation/reversal history without a separate elapsed-time expiry. Undo is available while its originals and evidence are intact and match. Existing seven-day retry/removal recognition remains separate. |

## Non-Goals

- Automatic semantic matching, generated summaries or automatic survivor selection.
- Permanent deletion, task copying, cross-project consolidation or moving historical comments.
- Native consolidation editing, App Intent parity or new navigation URLs.
- A new relationship store, general persistence redesign or CloudKit-wide transactions.
- Selective/force undo, automatic repair, or automatic redirection of writes to duplicates.

### 1. Explicit group and canonical identity

**User Story:** As a caller, I want to select equivalent tasks and their survivor, so that Transit does not infer my intent from similar titles.

**Acceptance Criteria:**

1. <a name="1.1"></a>WHEN a caller proposes consolidation, Transit SHALL require a survivor UUID, one to five distinct candidate UUIDs, a nonblank reason and preservation accounting for each candidate; malformed, repeated or out-of-range selections SHALL be rejected without domain effects.  
2. <a name="1.2"></a>WHEN selected tasks are missing, physically ambiguous by UUID, from different projects, or the survivor is not a uniquely resolved terminal canonical task, Transit SHALL reject the proposal with the offending identities and reasons.  
3. <a name="1.3"></a>WHEN a candidate has no duplicate target, Transit SHALL propose a duplicate-of link to the survivor; WHEN its existing valid chain resolves to that survivor, Transit SHALL retain that chain; IF it resolves elsewhere or has ambiguous, dangling or cyclic canonical evidence, Transit SHALL reject rather than retarget it.  
4. <a name="1.4"></a>WHEN previewing, applying or reversing a group, Transit SHALL leave unselected tasks and unrelated relationships unchanged, including incoming chains, and SHALL preserve T-1734's graph-validity rules for the complete proposed change.  

### 2. Saved preview and preservation review

**User Story:** As a caller, I want a complete review of saved originals and proposed effects, so that I can account for useful detail before closing duplicates.

**Acceptance Criteria:**

1. <a name="2.1"></a>WHEN preview succeeds, Transit SHALL return the saved originals, complete descriptions/metadata/comments with authors and dates, assignments, statuses, direct/canonical mappings, covered revisions, reason and exact proposed task/link effects; unreadable or incomplete evidence SHALL produce an explicit error instead of an apparently empty history.  
2. <a name="2.2"></a>WHEN unsaved task edits, inserts or deletions exist, preview SHALL report only saved local state; WHEN preview is requested, it SHALL produce no task, link, history, receipt, retry-binding, timestamp or display-ID allocation effect.  
3. <a name="2.3"></a>WHEN preview succeeds, it SHALL show each candidate's caller-authored preservation disposition: detail incorporated into the proposed survivor text/metadata and/or retained on the linked original with an explicit explanation, allowing mixed dispositions within one candidate; every incorporation SHALL identify its source candidate and affected survivor field. Transit SHALL reject missing candidate accounting and SHALL not certify semantic completeness.  
4. <a name="2.4"></a>WHEN preview shows caller-supplied survivor edits, Transit SHALL show before/after description and metadata values alongside candidate accounting and original values, without synthesising text or choosing conflicting values; WHEN apply is requested, Transit SHALL require an explicit acknowledgment of the reviewed preservation plan, including proposals without survivor edits, and reject apply without it. Acknowledgment SHALL not be presented as certification of semantic completeness.  

### 3. Preservation and closure effects

**User Story:** As a user, I want consolidation to retain original records and meaningful history, so that I can understand how work was combined.

**Acceptance Criteria:**

1. <a name="3.1"></a>WHEN consolidation commits, Transit SHALL retain every selected original UUID, display ID, description, metadata, comment membership/authorship/date and project/milestone assignment, except for the explicitly reviewed survivor description/metadata edits; the survivor's prior edited values SHALL remain inspectable in operation history.  
2. <a name="3.2"></a>WHEN consolidation commits, unfinished candidates SHALL become Abandoned with the existing status-transition date semantics; Done/Abandoned candidates and the survivor SHALL retain their status and status dates. Only reviewed survivor description/metadata edits and necessary candidate duplicate links SHALL accompany those closures.  
3. <a name="3.3"></a>WHEN a consolidation or reversal is recorded, its reason, selected originals, preservation dispositions, before/after changes and operation identity SHALL remain inspectable alongside the original histories; original comments SHALL stay on their original tasks and SHALL not be re-authored as survivor comments.  

### 4. Reviewed apply and local conflict boundary

**User Story:** As a caller, I want apply to honour the proposal I reviewed, so that a changed task or link cannot silently change the consolidation.

**Acceptance Criteria:**

1. <a name="4.1"></a>WHEN apply is requested, Transit SHALL require the exact reviewed proposal and its saved task/canonical/link evidence; IF required evidence no longer matches or cannot be uniquely read, it SHALL reject the whole group without domain effects and identify the conflict or unavailable evidence. A preview alone SHALL not reserve or authorise later effects.  
2. <a name="4.2"></a>WHEN consolidation commits, its selected task/link effects, operation history and authoritative terminal result SHALL commit together in the originating local store; a failed save SHALL not leave a partly applied group. Consolidation SHALL not inherit the ordered per-item partial-success semantics of mutate_tasks.  
3. <a name="4.3"></a>WHEN apply or undo is prepared, participating Transit writes SHALL not interleave its final saved validation and commitment; pending UI drafts SHALL neither be returned, saved nor rolled back incidentally, and new execution with unsafe pending edits SHALL return a no-effect pending-edit outcome.  
4. <a name="4.4"></a>WHERE independent writers or sync/imports race with the local operation, Transit SHALL retain its actual committed result and expose available saved identity/canonical/graph conflicts on subsequent reads; it SHALL not claim all-writer validation atomicity, remote convergence or automatically repair/reverse those effects.  

### 5. Retry, recovery and historical compatibility

**User Story:** As a caller, I want retry and recovery to report the saved operation, so that a lost response does not cause another consolidation.

**Acceptance Criteria:**

1. <a name="5.1"></a>WHEN apply or undo is requested, Transit SHALL preserve the existing protected-write key/payload/local-store contract, including rejection of a retained key with different arguments, byte-identical retained terminal replay after later edits, and read-only replay while drafts are dirty. Preview SHALL not accept a write key.  
2. <a name="5.2"></a>WHEN commitment cannot be established, the result SHALL distinguish rejected/no effect, matching active work and uncertainty using the existing acceptance/retry semantics; uncertain effects SHALL require original-request reconciliation rather than a fresh-key automatic retry. Cancellation or encoding/storage failure SHALL not be reported as no effect without proof.  
3. <a name="5.3"></a>WHEN receipts expire under the existing seven-day policy, Transit SHALL not infer that an operation was absent, erase its history or make it safely repeatable; unexpired/unknown acceptance and originating-store restrictions SHALL remain explicit.  
4. <a name="5.4"></a>WHEN consolidation evidence is added, retained query pages and earlier receipt bytes/tokens SHALL retain their original meaning; fresh reads SHALL expose current saved statuses/mappings and revisions covering the evidence needed to guard the new operation.  

### 6. Guarded whole-operation undo

**User Story:** As a user, I want to review and reverse a mistaken consolidation, so that I can recover its attributable effects without losing later work.

**Acceptance Criteria:**

1. <a name="6.1"></a>WHEN undo preview is requested by operation identity, Transit SHALL return the recorded before/after effects, proposed exact reversal, current saved evidence and availability/rejection reasons, without changing domain state, operation history or retry bindings.  
2. <a name="6.2"></a>WHEN undo is requested, Transit SHALL require the exact reviewed reversal and its current saved evidence; IF that review is stale/unreadable, an affected original is missing/ambiguous, required operation/link evidence is unavailable, any affected task's covered revision differs from the recorded applied state, or the proposed reversal would violate current graph rules, undo SHALL reject the whole reversal without changing tasks or links. New comments and incident links SHALL count as covered changes; later unimported remote edits SHALL remain outside the locally observed guarantee.  
3. <a name="6.3"></a>WHEN undo commits, Transit SHALL restore exactly the task fields/status dates changed by that consolidation, remove only its newly created duplicate occurrences, retain pre-existing links/comments/assignments, and record reversal history and its terminal result together; it SHALL not use the abandoned-to-Idea shortcut.  
4. <a name="6.4"></a>WHEN the original operation has already been reversed, Transit SHALL report that reversal without new domain effects; an exact retained undo-key replay SHALL still return its original result. Operation/reversal history SHALL have no separate elapsed-time expiry, and undo SHALL be unavailable when required originals/evidence no longer exist or match.  

### 7. Readback and native understanding

**User Story:** As a user, I want clear mappings and history, so that I can understand a consolidated task from either original or survivor.

**Acceptance Criteria:**

1. <a name="7.1"></a>WHEN apply/undo commits, its MCP result SHALL identify the operation, reason, actual saved changes, original-to-survivor mappings and undo/reversal state; structured and text forms SHALL describe the same logical result and preserve the existing protocol/result contract.  
2. <a name="7.2"></a>WHEN a new full task read addresses a participant with recorded consolidation history, it SHALL expose that history, distinguish historical operation evidence from current direct/canonical assessments and report undo availability against current saved state; requests addressed to an original UUID SHALL continue to address that original.  
3. <a name="7.3"></a>WHEN native task detail opens a participant with recorded consolidation history, it SHALL expose that history, including the reason, survivor/original references and reversal state alongside existing relationship navigation; unavailable or ambiguous references SHALL use the existing link diagnostic pattern and SHALL not navigate to an arbitrary physical match; unavailable or over-limit history SHALL be identified explicitly instead of silently omitted.  

### 8. Bounded review and motivating scenario

**User Story:** As a caller, I want bounded complete review results, so that I can consolidate the six-ticket cleanup without hidden truncation.

**Acceptance Criteria:**

1. <a name="8.1"></a>WHEN serving consolidation preview, undo preview or new history reads, Transit SHALL apply the existing five-second original-admission-to-response-completion budget and eight unfinished physical-read admission limit; IF complete evidence exceeds applicable byte/capacity/deadline limits, it SHALL return an explicit over-limit/unavailable outcome rather than truncate evidence or enable apply from an incomplete preview. WHERE captured evidence is retained, existing five-minute/eight-snapshot/16-MiB retention and full-envelope accounting SHALL apply; durable operation history SHALL retain its separate history policy.  
2. <a name="8.2"></a>WHEN reviewing one survivor and five same-project candidates with conflicting descriptions/metadata, preserved comments, mixed unfinished/terminal statuses and valid links, the caller SHALL be able to inspect complete preservation accounting before apply, read canonical mappings afterward, and preview an exact undo; stale apply, later covered edits, invalid identities/graphs and failure before commitment SHALL produce the defined safe outcomes.  

## Requirements gate

Approve these requirements, including the proposed group/status/content/whole-undo/retention choices above, or specify changes. Scope approval does not settle those choices. Approval authorises design work only; live bookkeeping remains paused.
