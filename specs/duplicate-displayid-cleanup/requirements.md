# Requirements: Duplicate Display ID Cleanup

## Introduction

Transit tasks and milestones have been observed sharing the same `permanentDisplayId` (e.g. two distinct tasks both labelled T-5). Duplicates trigger `duplicateDisplayID` errors at lookup time but there is no repair path in the app. This feature adds a maintenance tool that scans for duplicates, reassigns fresh IDs to all but one record per group, and advances the CloudKit counter past the highest observed ID so future allocations cannot re-hit an existing value. It is accessible from the in-app Settings screen, from the MCP server, and from App Intents.

## Non-Goals

- Automatic detection or cleanup at app launch — the tool only runs when triggered explicitly.
- Changing the single-flight promotion guards or the counter storage schema.
- Deduplicating records (merging two real tasks into one) — only display IDs are rewritten.
- Cross-type collisions between tasks and milestones (T-5 and M-5 is not a duplicate; they use separate counters).
- Re-applying old IDs or restoring previous assignments — losers receive freshly allocated IDs only.
- Notifying external consumers (commits, agent notes) that an ID has moved.
- Cross-device races where a peer device allocates a colliding ID from a stale local counter between runs — covered only by the end-of-run counter advance on the device running the tool.
- iCloud account switches mid-run — behaviour follows whatever the underlying allocator and save paths do.
- Spotlight and App Intent entity cache invalidation after an ID change.
- Mid-run cancellation on any surface.
- Writing any audit information to the task's `metadata` dictionary.

## Requirements

### 1. Scan for Duplicate Display IDs

**User Story:** As a Transit user, I want to scan for tasks and milestones that share a display ID, so that I can see the damage before deciding to repair it.

**Acceptance Criteria:**

1. <a name="1.1"></a>The system SHALL produce a report listing every `permanentDisplayId` value shared by two or more tasks, grouped by that display ID.
2. <a name="1.2"></a>The system SHALL produce a report listing every `permanentDisplayId` value shared by two or more milestones, grouped by that display ID.
3. <a name="1.3"></a>Records with `permanentDisplayId == nil` (provisional) SHALL be excluded from the scan.
4. <a name="1.4"></a>A task and a milestone sharing the same integer (e.g. T-5 and M-5) SHALL NOT be reported as a duplicate.
5. <a name="1.5"></a>For each duplicate group, the report SHALL identify the winner (oldest `creationDate`, lexicographically smallest UUID string as tiebreaker) and the losers.
6. <a name="1.6"></a>Each record in the report SHALL include its UUID, name, `creationDate`, and project name; when the project relationship is nil the project name SHALL be the literal string `"(no project)"`.
7. <a name="1.7"></a>When no duplicates exist, the scan SHALL return an empty groups list without error.
8. <a name="1.8"></a>Groups within the report SHALL be ordered by ascending display ID; records within a group SHALL be ordered with the winner first followed by losers in the winner-selection order from [1.5](#1.5).

### 2. Reassign Duplicates

**User Story:** As a Transit user, I want losers in each duplicate group to receive fresh display IDs, so that every record is uniquely addressable again.

**Acceptance Criteria:**

1. <a name="2.1"></a>For each duplicate group, the system SHALL preserve the winner's `permanentDisplayId` unchanged.
2. <a name="2.2"></a>For each loser, the system SHALL assign a new `permanentDisplayId` that is greater than every existing `permanentDisplayId` of the same record type at allocation time and SHALL persist across relaunch.
3. <a name="2.3"></a>Immediately before writing a loser's new ID, the system SHALL re-fetch that record and SHALL skip the group with a `stale-id` outcome if the stored `permanentDisplayId` no longer matches the value observed during scanning.
4. <a name="2.4"></a>Before allocating any replacement IDs for losers, the system SHALL advance the CloudKit counter for the record type to `max(highestObservedId, currentCounterValue) + 1` using a compare-and-swap write; a blind overwrite that could move the counter backwards SHALL NOT be used. Advancing before allocation prevents a concurrent provisional-ID promotion from minting an ID that collides with an existing duplicate group.
5. <a name="2.5"></a>Counter advancement SHALL be attempted on every run regardless of per-group outcomes, including runs where the scan found zero duplicates and runs where every group subsequently fails.
6. <a name="2.6"></a>Reassignment SHALL be best-effort per group: a failure on one group SHALL NOT abort the run; remaining groups SHALL continue to be processed.
7. <a name="2.7"></a>The run result SHALL report, per group, either the new ID assigned per loser or a failure whose cause is one of a discrete set of codes (`allocation-failed`, `save-failed`, `stale-id`, `comment-failed`) accompanied by a human-readable message.

### 3. Audit Trail on Reassigned Tasks

**User Story:** As a Transit user, I want reassigned tasks to carry a permanent record that their display ID changed, so that I can trace stale external references back to the current task.

**Acceptance Criteria:**

1. <a name="3.1"></a>When a task's `permanentDisplayId` is reassigned, the system SHALL append a new `Comment` to that task; any existing comments on the task SHALL be unchanged.
2. <a name="3.2"></a>The appended comment SHALL have `isAgent=true`, `authorName` equal to the literal string `"Transit Maintenance"`, and a body containing the substrings `T-{oldId}`, `T-{newId}`, and the ISO-8601 date (YYYY-MM-DD) of the reassignment.
3. <a name="3.3"></a>Milestones SHALL NOT receive a comment (the `Milestone` model has no `Comment` relationship).
4. <a name="3.4"></a>The ID change and the audit comment SHALL be persisted in two separate saves: the ID save first, then the comment save. If the ID save succeeds but the comment save fails, the ID SHALL remain reassigned and the group's result SHALL include a `comment-failed` warning.

### 4. In-App Settings UI

**User Story:** As a Transit user, I want to run the cleanup from the Settings screen with a preview before committing, so that I can see what will change before authorising it.

**Acceptance Criteria:**

1. <a name="4.1"></a>A new "Data Maintenance" entry SHALL be reachable from the Settings screen on both iOS/iPadOS and macOS.
2. <a name="4.2"></a>The Data Maintenance view SHALL offer a "Scan for duplicate display IDs" action that presents the scan report in-app.
3. <a name="4.3"></a>While a scan or reassignment is running, the view SHALL show a progress indicator and SHALL disable the scan and reassign buttons for the duration of that run.
4. <a name="4.4"></a>The scan report SHALL list each duplicate group with its display ID, each record's name and project, and a visual marker distinguishing the winner from the losers.
5. <a name="4.5"></a>When the report contains at least one group, a "Reassign Losers" action SHALL be enabled; otherwise it SHALL be disabled or hidden.
6. <a name="4.6"></a>The "Reassign Losers" action SHALL require confirmation via a system alert with a destructive-style confirm button.
7. <a name="4.7"></a>After reassignment completes, the view SHALL display a result summary listing each group's outcome (new IDs assigned or failure code and message).

### 5. MCP Tools

**User Story:** As an agent using the Transit MCP server, I want `scan_duplicate_display_ids` and `reassign_duplicate_display_ids` tools, so that I can run the cleanup without opening the app.

**Acceptance Criteria:**

1. <a name="5.1"></a>The MCP server SHALL expose `scan_duplicate_display_ids` that takes no required parameters and returns the scan report as JSON.
2. <a name="5.2"></a>The MCP server SHALL expose `reassign_duplicate_display_ids` that takes no required parameters and returns the run result as JSON.
3. <a name="5.3"></a>Both tools SHALL operate on the shared `mainContext` so that results are immediately visible to the UI.
4. <a name="5.4"></a>Tool responses SHALL follow the existing Transit MCP convention: a `content` array with a single `type: "text"` item whose `text` is the JSON-encoded payload, and errors SHALL be surfaced via `isError: true` with the same text-item shape.
5. <a name="5.5"></a>Both maintenance MCP tools SHALL be gated behind a persistent setting that defaults to off; when the setting is off, the tools SHALL NOT appear in the `tools/list` response and a `tools/call` for either name SHALL return a tool-not-found error.
6. <a name="5.6"></a>A toggle for the gating setting in [5.5](#5.5) SHALL be reachable from the macOS MCP Server settings pane and SHALL take effect without requiring an app restart.

### 6. App Intents

**User Story:** As a user scripting Transit from Shortcuts or the CLI, I want scan and reassign App Intents, so that I have parity with the MCP surface.

**Acceptance Criteria:**

1. <a name="6.1"></a>The app SHALL expose a `ScanDuplicateDisplayIDsIntent` that returns the scan report as a JSON string.
2. <a name="6.2"></a>The app SHALL expose a `ReassignDuplicateDisplayIDsIntent` that returns the run result as a JSON string.
3. <a name="6.3"></a>The Intent output and the MCP tool output for the same operation SHALL use the same top-level JSON keys and value types.
4. <a name="6.4"></a>On internal error, the intents SHALL return a JSON error payload rather than throwing, matching the existing Transit intent convention.

### 7. Concurrency Safety

**User Story:** As a Transit user, I want the cleanup to coexist safely with the existing provisional-ID promotion passes, so that running maintenance never corrupts IDs that are mid-promotion.

**Acceptance Criteria:**

1. <a name="7.1"></a>A second invocation of reassignment while one is already running SHALL return a `busy` result immediately without side effects.
2. <a name="7.2"></a>After any interleaving of reassignment and provisional-ID promotion, no two records of the same type SHALL share a `permanentDisplayId`, and no record SHALL have lost a previously-assigned permanent ID.
3. <a name="7.3"></a>Maintenance operations SHALL coordinate state on the main actor, consistent with the existing service layer; async CloudKit I/O MAY suspend to background queues.

### 8. Failure Reporting and Idempotence

**User Story:** As a Transit user, I want clear failure reporting and safe reruns, so that I can recover from partial runs without making things worse.

**Acceptance Criteria:**

1. <a name="8.1"></a>When ID allocation fails for a specific loser (offline, retries exhausted), the run result SHALL record the group with cause `allocation-failed` and SHALL continue with the next group.
2. <a name="8.2"></a>When the final counter-advance step fails, the run result SHALL include a `counter-advance-failed` warning at the run level without marking individual groups as failed.
3. <a name="8.3"></a>When the ID save fails for a reassignment, the record's `permanentDisplayId` SHALL remain at its pre-run value on next read, and the group SHALL be recorded with cause `save-failed`.
4. <a name="8.4"></a>A reassignment run SHALL be idempotent over data that contains no duplicates: the per-group result list SHALL be empty and the only possible side effect SHALL be the counter advance specified in [2.4](#2.4).
