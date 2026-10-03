# Requirements: MCP Write Safety

Ticket: T-2380

## Introduction

MCP callers need to retry interrupted writes without duplicating tasks or comments, and update records without overwriting intervening edits. This feature adds retry keys, revision preconditions, and structured write outcomes within one local Transit store. CloudKit sync remains asynchronous, so these protections do not promise global ordering across devices.

## Non-Goals

- Cross-device deduplication or globally atomic compare-and-swap through CloudKit.
- Batch mutation submission or dry-run previews (T-2384).
- UI conflict rebasing (T-2002), duplicate consolidation, or maintenance-tool retry protection.
- Extending the safety inputs to App Intents in this feature.
- Preserving compatibility for MCP callers that omit required safety inputs.

## Requirements

### 1. Protected Write Inputs

**User Story:** As an MCP caller, I want explicit safety inputs, so that every supported write declares its retry and conflict protection.

**Acceptance Criteria:**

1. <a name="1.1"></a>WHEN calling `create_task`, `create_project`, `create_milestone`, `add_comment`, `update_task`, `update_task_status`, `update_milestone`, or `delete_milestone`, the system SHALL require a non-empty `idempotencyKey`; missing or invalid keys SHALL return `INVALID_INPUT` without mutation.  
2. <a name="1.2"></a>WHEN updating a task, changing its status, updating a milestone, or deleting a milestone, the system SHALL also require the target's `expectedRevision`; missing or invalid revisions SHALL return `INVALID_INPUT` without mutation.  
3. <a name="1.3"></a>The published MCP schemas SHALL identify the required safety fields, their accepted formats, protected operations, local-store scope, and retention limits.  

### 2. Retry Identity and Replay

**User Story:** As an MCP caller, I want to retry the same logical request, so that a lost response cannot duplicate its effects.

**Acceptance Criteria:**

1. <a name="2.1"></a>The system SHALL scope each accepted key to one local store and tool name, independently of connection, MCP session, and JSON-RPC request ID; the accepted tool arguments, including preconditions but excluding the key, SHALL determine its request identity.  
2. <a name="2.2"></a>WHEN a retained key is retried with the same arguments, the system SHALL return its recorded completed outcome without another logical effect, even after app restart, subsequent record edits, or deletion of the created record.  
3. <a name="2.3"></a>WHEN a retained key is reused with different arguments, the system SHALL return `IDEMPOTENCY_KEY_REUSED` without mutation; JSON object key ordering SHALL NOT count as an argument difference.  
4. <a name="2.4"></a>WHEN simultaneous matching requests use the same key, the system SHALL permit at most one logical effect and SHALL return either the completed outcome or `OPERATION_IN_PROGRESS` to the other callers.  
5. <a name="2.5"></a>WHEN a completed outcome is replayed, the system SHALL preserve the original saved record, revision, and outcome metadata; replay SHALL precede reevaluation of the original revision precondition or target existence.  

### 3. Retention and Interrupted Outcomes

**User Story:** As an MCP caller, I want a defined retry window and recovery outcome, so that I can safely continue after a timeout or interruption.

**Acceptance Criteria:**

1. <a name="3.1"></a>The system SHALL retain completed outcomes for at least seven days from completion and SHALL return their guaranteed replay expiry as an absolute timestamp; replay SHALL NOT extend that expiry.  
2. <a name="3.2"></a>WHEN a key's retained outcome has expired and been removed, the system MAY accept it as a new request; the published contract SHALL instruct callers to stop treating retries after the returned expiry as protected.  
3. <a name="3.3"></a>WHEN interruption occurs before, during, or after saving an accepted request, retry with its key SHALL resolve to the original completed outcome, a proven no-effect rejection, `OPERATION_IN_PROGRESS`, or `OUTCOME_UNCERTAIN`; the system SHALL NOT repeat a write whose commitment is uncertain.  
4. <a name="3.4"></a>WHILE an accepted key has an unresolved outcome, the system SHALL retain its payload binding across restart and SHALL NOT discard it under the completed-outcome retention policy.  
5. <a name="3.5"></a>WHEN an accepted request is conclusively rejected without effect, the system SHALL retain and replay that rejection; a corrected request SHALL require a new key. Invalid requests rejected before key acceptance SHALL NOT reserve the key.  

### 4. Record Revisions and Preconditions

**User Story:** As an MCP caller, I want to compare the record I read with the record being changed, so that intervening edits are preserved.

**Acceptance Criteria:**

1. <a name="4.1"></a>WHEN returning a full task, project, milestone, or comment through MCP, the system SHALL return an opaque revision that can be compared for equality; applicable task and milestone read responses SHALL supply revisions usable in write preconditions.  
2. <a name="4.2"></a>WHEN revision-covered state changes locally, the next full response SHALL have a different revision, regardless of whether the change originated in MCP, the UI, App Intents, maintenance, or imported sync. Covered state SHALL be each entity's own persisted scalar fields; task project/milestone UUIDs and comment membership plus comment fields; milestone project UUID; and comment task UUID. Related project/milestone descriptive fields, project task/milestone membership, milestone task membership, and derived summaries SHALL NOT affect the parent's revision.  
3. <a name="4.3"></a>WHEN the target's locally observable revision differs from `expectedRevision`, the system SHALL reject the update or deletion with `REVISION_CONFLICT`, return the current record and revision, preserve the intervening edit, and create no accompanying comment.  
4. <a name="4.4"></a>WHEN a precondition matches, the system SHALL apply it to the state used for the local write, rather than an earlier read before intervening asynchronous work; success SHALL return the resulting saved revision.  
5. <a name="4.5"></a>The contract SHALL define revisions as comparisons against locally observed state, SHALL state that edits not yet imported from CloudKit cannot be detected, and SHALL NOT claim global serialization or prevention of later sync conflicts.  
6. <a name="4.6"></a>WHEN an update leaves the revision-covered state unchanged, the system SHALL preserve its revision; callers SHALL NOT be required to interpret revisions as timestamps or monotonic counters.  

### 5. Saved Records and Structured Outcomes

**User Story:** As an MCP caller, I want structured saved outcomes, so that I can verify writes and decide how to recover without parsing prose.

**Acceptance Criteria:**

1. <a name="5.1"></a>WHEN a protected write succeeds, the system SHALL return a machine-readable committed outcome containing the tool name, key, saved entity UUID, saved normalized record and revision, and replay expiry; task status changes with a comment SHALL also identify and return the saved comment.  
2. <a name="5.2"></a>WHEN deleting a milestone succeeds, the system SHALL return its UUID, pre-deletion record and revision, and a committed deletion outcome; it SHALL NOT invent a surviving milestone revision.  
3. <a name="5.3"></a>WHEN a protected write fails, the system SHALL return a machine-readable error code and distinguish rejected-with-no-effect, in-progress, and uncertain outcomes; accepted-key outcomes SHALL include the key and tool name, retained conclusive rejections SHALL include replay expiry, and conflict responses SHALL include the current record and revision.  
4. <a name="5.4"></a>WHEN task status and an accompanying comment are submitted together, the system SHALL persist both or neither, including across interruption and restart, and treat them as one logical effect for replay and precondition checking; `OUTCOME_UNCERTAIN` SHALL describe uncertainty about that whole effect rather than permit partial persistence.  
5. <a name="5.5"></a>WHEN an unresolved key is retried, the system SHALL state whether to retry the same request, stop for reconciliation, or use a new key after a conclusive rejection; it SHALL NOT advise a new-key retry for an uncertain commitment.  

### 6. Shared Contract and Verification

**User Story:** As a developer, I want tested write semantics reusable by batch mutations, so that callers receive consistent protection.

**Acceptance Criteria:**

1. <a name="6.1"></a>The published write contract SHALL define key identity, expiry, revisions, conflict responses, and outcome classifications for reuse by T-2384 without introducing batch application behavior in this feature.  
2. <a name="6.2"></a>Automated verification SHALL cover matching retries, mismatched payloads, concurrent matching requests, restart recovery, seven-day expiry, comment creation, status-with-comment writes, stale edits from supported local write paths, imported sync changes, and interruptions around commit.  

## Review Status

Approved on 2026-10-03 after critic and independent peer review.
