# Portfolio summaries

Approved in full, including review decisions, in parent conversation: Sentinel_fa39017e21a08191abdcd0b7ae6c9e8e. Design, tasks, and implementation have separate approval gates.

## Introduction

Portfolio summaries expose recorded project workload without requiring an agent to download every task. Explicit status buckets, completion windows, activity evidence, and local freshness let callers describe the portfolio without mistaking backlog counts for work underway or release completion.

## Non-Goals

- Inferring product readiness, release completion, or milestone completion from task counts.
- Historical completion-event reporting or general modification tracking beyond existing recorded timestamps.
- UI dashboards, App Intent summaries, identity repair, or persisted schema migrations.
- Proving CloudKit-wide completeness or remote freshness from a local read.

### 1. Portfolio and scoped project summaries

**User Story:** As an agent, I want compact project summaries, so that I can inspect workload without transferring every task.

**Acceptance Criteria:**

1. <a name="1.1"></a>WHEN a portfolio summary is requested, the system SHALL return one summary for each captured project, including projects with zero tasks and zero milestones, with its project UUID and name.
2. <a name="1.2"></a>WHEN a project summary is requested by UUID or name, the system SHALL return only that project's summary; unknown, ambiguous, malformed, or conflicting selectors SHALL produce an explicit error rather than a successful empty portfolio or arbitrary selection.
3. <a name="1.3"></a>The summary SHALL contain aggregate counts, project/milestone identities, activity evidence, and consistency diagnostics without individual task descriptions, metadata, or comment bodies.

### 2. Status definitions and compatibility

**User Story:** As an agent, I want explicit status counts, so that I can distinguish ideas from workflow stages.

**Acceptance Criteria:**

1. <a name="2.1"></a>Each project and milestone summary SHALL include a count for each effective task status (`idea`, `planning`, `spec`, `ready-for-implementation`, `in-progress`, `ready-for-review`, `done`, `abandoned`), including zeros, and a total equal to the sum of those buckets.
2. <a name="2.2"></a>The summary SHALL expose idea count equal to the `idea` bucket, in-progress count equal to the `in-progress` bucket, workflow count equal to the sum of planning/spec/ready-for-implementation/in-progress/ready-for-review, and nonterminal count equal to idea plus workflow count; it SHALL describe these as recorded stage membership, without claiming that every workflow task is currently being worked on.
3. <a name="2.3"></a>The existing `get_projects.activeTaskCount` SHALL retain its meaning of all nonterminal tasks, including ideas, and the documentation SHALL state that meaning alongside the explicit new counts.
4. <a name="2.4"></a>WHEN stored status values are unrecognized, summaries and snapshot-bound task queries SHALL interpret those records as `idea`, matching the task model's effective status, and the summary SHALL explicitly report their count; snapshot-bound status filters and returned effective statuses SHALL apply this same rule.
5. <a name="2.5"></a>WHEN a task query does not request a reusable captured view, its existing stored-status filtering, result fields, ordering, and frozen cursor behavior SHALL remain compatible; documentation SHALL distinguish its stored-status semantics from snapshot-bound effective-status queries.

### 3. Explicit completion windows

**User Story:** As an agent, I want a defined recent-completion window, so that I can compare recorded completions over a stated interval.

**Acceptance Criteria:**

1. <a name="3.1"></a>WHEN requesting summaries, the caller SHALL provide start and end instants with explicit timezone offsets; malformed timestamps, missing endpoints, or start greater than or equal to end SHALL produce an explicit validation error, and successful responses SHALL echo the normalized UTC interval.
2. <a name="3.2"></a>The summary SHALL report separate counts of currently done and currently abandoned tasks whose recorded `completionDate` is greater than or equal to start and less than end, at project and milestone level.
3. <a name="3.3"></a>WHEN a terminal task has no recorded completion date, the summary SHALL include it in its status bucket and an explicit missing-date count but SHALL exclude it from window counts; restored nonterminal tasks SHALL be excluded from terminal window counts even if a date remains.
4. <a name="3.4"></a>The documentation SHALL identify window counts as current-record counts rather than counts of historical completion transitions, and SHALL state the start-inclusive/end-exclusive rule and timestamp formats.

### 4. Last recorded activity

**User Story:** As an agent, I want dated activity evidence, so that I can report the most recent recorded activity without inventing modification history.

**Acceptance Criteria:**

1. <a name="4.1"></a>Each project summary SHALL return the maximum timestamp from its tasks' creation/status-change dates, their comments' creation dates, and its milestones' creation/status-change dates, together with the contributing evidence kind and identity; WHEN no such evidence exists it SHALL return null.
2. <a name="4.2"></a>WHEN activity evidence timestamps tie, the system SHALL select evidence deterministically, and the documentation SHALL specify the tie-break rule and excluded evidence, including arbitrary task/project edits without recorded modification timestamps.

### 5. Milestones and identity diagnostics

**User Story:** As an agent, I want faithful milestone and identity reporting, so that inconsistent records cannot silently change portfolio conclusions.

**Acceptance Criteria:**

1. <a name="5.1"></a>Each project summary SHALL include all its captured milestones, including empty, open, done, and abandoned milestones, with raw recorded status, effective status, UUID, optional display ID, and task buckets; unrecognized raw status SHALL be flagged and interpreted as effective `open`, and terminal tasks SHALL NOT alter the milestone's reported status.
2. <a name="5.2"></a>Project totals SHALL count each captured task record assigned to that project exactly once; tasks with no milestone and tasks with invalid milestone relationships SHALL have separate breakdowns so valid milestone totals plus those breakdowns reconcile to the project totals.
3. <a name="5.3"></a>WHEN tasks have missing/unresolved project references, a portfolio response SHALL report their status counts separately from project totals; WHEN milestone links refer outside a task's project or to unresolved milestones, the summary SHALL report those task counts as invalid associations rather than crediting the referenced milestone.
4. <a name="5.4"></a>WHEN project names or task/milestone display IDs collide, the summary SHALL report exact affected-record counts and at most ten deterministic identity samples per diagnostic category with an explicit sample-completeness indicator; it SHALL NOT merge records by name or display ID, and missing permanent display IDs SHALL remain explicitly absent.
5. <a name="5.5"></a>IF duplicate UUID records make identity-based attribution ambiguous within the requested scope or into it, the system SHALL return an explicit identity-ambiguity error rather than arbitrarily choosing or merging records; ambiguity unrelated to a scoped project's attribution SHALL NOT fail that project's summary.

### 6. Snapshot reconciliation and freshness

**User Story:** As an agent, I want counts and freshness tied to one captured view, so that comparisons remain valid while records change.

**Acceptance Criteria:**

1. <a name="6.1"></a>A successful summary SHALL aggregate one immutable internally consistent captured view of saved project/task/milestone/activity evidence, excluding unsaved UI edits, identified by `snapshotId`, `asOf`, and shared T-63 freshness evidence; these fields SHALL describe the original local capture and SHALL NOT imply that all remote changes have arrived.
2. <a name="6.2"></a>WHEN task queries are requested against the summary's captured view using the same project UUID and effective-status filters before expiry, their result counts SHALL equal the corresponding summary buckets across all pages; intervening task/project/milestone/comment changes SHALL NOT alter that comparison, and documentation SHALL distinguish this from completion-window and invalid-association breakdowns.
3. <a name="6.3"></a>WHEN continuing or replaying a summary result, the system SHALL preserve original counts, identities, activity evidence, completion-window endpoints, `asOf`, and freshness metadata without extending snapshot lifetime; an expired or lost view SHALL produce an explicit restart-required error rather than current-data substitution.
4. <a name="6.4"></a>A portfolio with no projects and an existing scoped project with zero tasks/milestones SHALL carry the same capture/freshness metadata as populated results, and documentation SHALL distinguish capture time, freshness evidence time, completion interval, and expiry.
5. <a name="6.5"></a>The captured view SHALL remain reusable for five minutes from creation unless the server lifecycle invalidates it; its expiry SHALL be explicit, and a retained view SHALL NOT be evicted silently to admit another request.
6. <a name="6.6"></a>WHEN a caller requests a captured view with incompatible scope or unsupported filters/options, the system SHALL return an explicit typed compatibility error rather than recapturing live data, silently broadening scope, or ignoring options; the schema SHALL list supported snapshot-bound options.
7. <a name="6.7"></a>Snapshot-bound task queries SHALL support summary and full task detail, including captured task descriptions and metadata for full detail, with comment bodies excluded; requests for comment bodies SHALL return an explicit unsupported-option error rather than reading live comments.

### 7. Bounded outcomes and discoverability

**User Story:** As an agent, I want explicit bounded-read outcomes, so that failures and incomplete data cannot be mistaken for a valid empty portfolio.

**Acceptance Criteria:**

1. <a name="7.1"></a>The system SHALL produce and make the encoded response available to the transport within five seconds from request admission for an individual summary submitted as one JSON-RPC object per POST, including queueing, freshness evaluation, capture, aggregation, and serialization; WHEN work cannot finish within that deadline it SHALL make a typed timeout available within the same deadline without publishing a late snapshot. IF response/snapshot capacity is exceeded, the system SHALL return a typed capacity error; neither case SHALL return truncated or partial counts as a complete success.
2. <a name="7.2"></a>WHEN required project/task/milestone/activity evidence cannot be read, the system SHALL return a typed read failure distinguishable from validation, timeout, capacity, and valid zero-result outcomes.
3. <a name="7.3"></a>The MCP tool schema and documentation SHALL describe selectors, all count definitions, completion-window rules, activity evidence, diagnostics, snapshot use/expiry, freshness limitations, and bounded failure outcomes.
4. <a name="7.4"></a>WHEN requesting a new summary, the caller SHALL be able to select cached local data or refresh-if-needed behavior; the default SHALL be refresh-if-needed, with at most two seconds waiting for import evidence, and freshness SHALL use the shared T-63 thirty-second recent-import threshold with an explicit refresh outcome rather than treating waiting as proof of completeness.
5. <a name="7.5"></a>The production transport SHALL reject JSON-RPC arrays under the user-approved latest-only, single-object POST contract. Application-level `mutate_tasks` batching remains one `tools/call`; summary read handling SHALL preserve its write receipts and SHALL NOT claim a read-only five-second guarantee for a mutating call.
