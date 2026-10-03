# Bounded read freshness — requirements

Transit agents need to know when a read describes only the endpoint's local view and when that view was captured. Headless CloudKit imports may lag, and read latency has exceeded client deadlines without an established cause. This feature makes those limits visible and gives callers a bounded success or failure response.

Review status: approved in full by the user in the parent conversation on 2026-10-03, including the 30,000 ms threshold, eight unfinished-read admission limit, diagnostics, and all decisions in the requirements review. Design, tasks, and production implementation remain gated separately.

## Proposed observable contract

- Covered tools: `query_tasks` (single, batch, list, and cursor), `query_milestones`, and `get_projects`, including related comments/milestones required by their selected output.
- Default policy: `refresh_if_needed`; optional `cached` policy skips import waiting. No separate refresh tool is required.
- Total read budget: 5,000 ms, measured from decoded read admission before executor queueing to an encoded success/error available to transport. Read-only JSON-RPC batches share their admission timestamp and must have a combined encoded response within this budget. For mixed read/write batches each read result's production is bounded while existing writes are preserved; combined HTTP delivery can wait on writes. The user approved this mixed-batch exception. Network upload/download and whole-process suspension are outside the server response guarantee.
- Freshness wait limit: 2,000 ms within the total budget. A relevant successful import is recent when its age at capture is at most 30,000 ms.
- Compatibility: keep existing data payload shapes, selection semantics, and query cursor expiry/capacity behavior; add read metadata to the MCP result. Success data are the selected local view, not a claim of remote convergence.
- Admission bound: at most eight unfinished covered read operations, including timed-out work still running; return `READ_BUSY` when that capacity is unavailable. This is an operation-count limit, not a total transient-memory limit.
- Recommended latency evidence: server diagnostics distinguish queueing, refresh wait, capture/fetch, transformation, serialization, and batch aggregation, including correlated late completion/discard after a caller timeout. This diagnostics detail remains pending final requirements approval.

The import recency threshold, admission bound, and latency diagnostics are recommendations for the requirements approval gate. Exact metadata placement and supported import observation/refresh mechanisms are design decisions, constrained by compatibility and the behavior below. “JSON-RPC batch” means several protocol request elements; `query_tasks` batch mode is one read operation selecting multiple identifiers. Each covered request element is admitted separately in received order against the global available slots; excess elements receive `READ_BUSY`, while all elements keep the common decoded-batch admission timestamp.

## Non-Goals

- Guaranteed force-pull, global CloudKit convergence, or proof that every remote edit has arrived.
- Changes to writes, persisted model schemas, UI sync behavior, or unrelated App Intent reads.
- A separate refresh tool or optional maintenance-tool reads.
- T2382 portfolio aggregation, completion-window definitions, and its externally reusable summary/task-query snapshot API/lifecycle; T-63 supplies compatible shared capture/freshness semantics.

### 1. Bounded read completion

**User Story:** As an agent, I want every read to finish within a known server budget, so that I can recover from a slow endpoint.

**Acceptance Criteria:**

1. <a name="1.1"></a>WHEN a covered read is admitted, the server SHALL produce its encoded success or defined error within 5,000 ms, including queueing, freshness waiting, local fetches, related-data capture, transformation, and serialization; for individual reads and read-only batches this includes making the response available to transport, while mixed-batch delivery follows the approved exception in 1.5.  
2. <a name="1.2"></a>IF a complete selected result cannot be returned within that budget, the server SHALL return `READ_TIMEOUT` with the exhausted phase when known and SHALL NOT later emit a second result for that request.  
3. <a name="1.3"></a>WHEN eight unfinished covered reads already exist, the server SHALL reject additional covered reads with `READ_BUSY` within their total budget; timed-out work SHALL continue to count against capacity until it finishes.  
4. <a name="1.4"></a>WHEN a response deadline expires while a local fetch is slow or blocked, the server SHALL still return the timeout within the total budget; a late result SHALL NOT create or replace a caller-visible snapshot.  
5. <a name="1.5"></a>WHEN a batch contains only covered reads, the server SHALL make its complete encoded batch response available within 5,000 ms of batch admission, including aggregate serialization; IF successful-result encoding cannot finish within that deadline, the affected reads SHALL receive defined timeout results within the same deadline. WHEN a batch also contains writes, the server SHALL produce each covered read result within that deadline and disclose that combined delivery may wait for writes.  
6. <a name="1.6"></a>WHEN timed-out work finishes or the read service stops, the server SHALL release its admission slot and discard unneeded capture/page data without publishing a late response or snapshot; retained valid pages SHALL keep existing byte and expiry limits.  

### 2. Explicit local capture and freshness evidence

**User Story:** As an agent, I want capture time and import evidence, so that I can judge whether local data are adequate for my decision.

**Acceptance Criteria:**

1. <a name="2.1"></a>WHEN a covered read succeeds, including an empty or scoped result, the outer MCP tool result SHALL carry an opaque `snapshotId`, UTC ISO 8601 `asOf` with millisecond precision identifying completed local capture, and one freshness assessment for all task/project/milestone/comment evidence used by that result, while preserving the existing data value and shape inside its text content.  
2. <a name="2.2"></a>The freshness metadata SHALL disclose the running store's `syncState` (`active` or `inactive`), nullable `lastImportedAt`, `assessedAt` fixed to the capture's `asOf`, and the 30,000 ms recent-import threshold; it SHALL classify evidence at capture as `recent_import`, `stale`, `unknown`, or `not_applicable`.  
3. <a name="2.3"></a>WHEN cloud sync is active, the server SHALL classify a known relevant successful import of age 0–30,000 ms as `recent_import`, an older known import as `stale`, and absent, unreliable, or temporally inconsistent evidence as `unknown`; import recency SHALL NOT imply all remote edits are visible in the local view.  
4. <a name="2.4"></a>IF successful import evidence cannot be tied to the running store and captured local view, the server SHALL report `unknown` rather than confirmed recency; heartbeat writes, failed/incomplete imports, and response timestamps SHALL NOT substitute for successful import evidence.  
5. <a name="2.5"></a>WHEN a later import fails, the server SHALL preserve any valid last successful import timestamp and disclose the failed refresh outcome separately from local fetch success.  
6. <a name="2.6"></a>WHEN a result includes task, project, milestone, or comment evidence, all selected records and relationships SHALL correspond to one immutable local observation boundary containing saved data only, with each completed saved change wholly represented or wholly absent from that selected view; unsaved UI/context changes SHALL NOT be returned. IF that boundary cannot be established, the server SHALL return an `incoherent_capture` failure category. Import evidence SHALL NOT label data captured before that import became visible to the selected view as recent.

### 3. Cached and bounded refresh policy

**User Story:** As an agent, I want to choose whether to wait briefly for import evidence, so that I can balance latency against freshness needs.

**Acceptance Criteria:**

1. <a name="3.1"></a>WHEN a new read omits policy, the server SHALL apply `refresh_if_needed`; WHEN it specifies `cached`, the server SHALL capture the local view without import waiting and report `not_requested` as its refresh outcome.  
2. <a name="3.2"></a>WHEN `refresh_if_needed` is selected and cloud sync is active, the server SHALL skip import waiting if evidence is recent; otherwise it SHALL attempt a supported refresh if available and wait for relevant completed import evidence for at most 2,000 ms within the remaining total budget.  
3. <a name="3.3"></a>WHEN refresh finishes, times out, is unsupported, or fails, the server SHALL distinguish `import_observed`, `timeout`, `unavailable`, or `failed` respectively from a skipped `recent_import` outcome, and SHALL return complete selected local data with freshness metadata if these remain obtainable within the total budget.  
4. <a name="3.4"></a>WHEN the running store's cloud sync is inactive, the server SHALL skip import waiting under either policy, report `syncState: inactive`, `assessment: not_applicable`, `lastImportedAt: null`, and `refreshOutcome: not_requested`, and preserve the existing local read selection and saved-write visibility semantics.  
5. <a name="3.5"></a>WHEN a caller supplies an unsupported or incorrectly typed policy, the server SHALL return the existing invalid-input category within the total budget without changing stored data.  
6. <a name="3.6"></a>WHEN refresh outcomes compete, a relevant successful import visible to capture SHALL yield `import_observed`; otherwise an observed failed import SHALL yield `failed`, an available trigger or relevant in-flight import that does not complete within the wait SHALL yield `timeout`, and absence of both a supported trigger and relevant in-flight import SHALL yield `unavailable`. Observation SHALL cover the refresh decision through the end of the bounded wait, including a relevant import already in flight at that decision; relevance SHALL require the running store and applicability to the selected capture. The wait SHALL be shortened to the remaining total budget, and zero remaining wait SHALL yield `timeout` if a trigger or relevant in-flight import exists, otherwise `unavailable`; IF no complete local result can then be returned within the total deadline, `READ_TIMEOUT` SHALL take precedence.  

### 4. Complete results and distinguishable failure

**User Story:** As an agent, I want storage errors distinguished from freshness limits, so that I do not interpret a failed read as an empty project or task list.

**Acceptance Criteria:**

1. <a name="4.1"></a>IF any local fetch or serialization required by the selected result fails, the server SHALL return the stable machine-readable category `storage_failure` or `serialization_failure` respectively, distinguishable from `incoherent_capture`, `READ_TIMEOUT`, `READ_BUSY`, input/cursor/capacity errors, and a successful read with stale or unknown freshness; caller documentation SHALL map these categories to the retained or extended tool error codes.  
2. <a name="4.2"></a>IF the selected result is incomplete, the server SHALL NOT present omitted related data, empty fallback data, or partial totals as a complete success; existing per-identifier not-found/ambiguous outcomes in batch task queries SHALL remain valid complete results.  
3. <a name="4.3"></a>WHEN no capture completes, the response SHALL NOT fabricate an `asOf`, import timestamp, or successful snapshot identity; a legitimate empty success SHALL retain the same metadata contract as a populated result.  
4. <a name="4.4"></a>WHEN covered reads use these policies, the server SHALL preserve existing write tool inputs, outputs, side effects, and error behavior.  

### 5. Frozen pages and shared contract semantics

**User Story:** As an agent, I want later pages to describe the original view, so that pagination does not make old data appear newly captured.

**Acceptance Criteria:**

1. <a name="5.1"></a>WHEN a cursor continues a captured task query, every page SHALL retain the original `snapshotId`, `asOf`, freshness assessment, import evidence, and capture policy/outcome even if imports or local edits occur between page requests.  
2. <a name="5.2"></a>WHEN a valid cursor is retried, the server SHALL return the same retained page and captured metadata without a new import wait or local data capture; cursor validity and snapshot expiry SHALL preserve existing behavior.  
3. <a name="5.3"></a>The shared capture metadata contract SHALL define the same meanings for covered read results and T2382 summary results; timestamps alone SHALL NOT establish that independently captured results share a view, and `asOf` SHALL remain distinct from completion-window endpoints. WHERE T2382 exposes the same reusable captured view, its query/summary results SHALL preserve that view's identical snapshot identity, capture time, and import evidence; T-63 SHALL NOT substitute unrelated capture identities for that view.  
4. <a name="5.4"></a>WHEN a cursor continuation omits policy, it SHALL preserve the retained capture policy; WHEN it explicitly supplies that same policy, it SHALL return the same page; WHEN it supplies a different policy, it SHALL return invalid input without relabeling the view. Existing selector/argument validation SHALL retain its precedence; malformed policy SHALL be rejected before cursor lookup, and a well-typed conflicting policy SHALL be rejected only after resolving a valid cursor.  

### 6. Caller guidance and validation

**User Story:** As an agent, I want documented limits and retry rules, so that I can recover without turning a freshness caveat into a retry loop.

**Acceptance Criteria:**

1. <a name="6.1"></a>The caller documentation SHALL define metadata meanings, error categories, policy defaults, the server deadline boundary, import-evidence limitations, and retry rules: a new query creates a new capture; a cursor retry retains its capture; timeout/busy retries use backoff; no read performs an unbounded automatic retry.  
2. <a name="6.2"></a>Validation SHALL demonstrate normal and empty reads, single/batch/list/cursor task reads, scoped milestone/project reads, inactive sync, unknown/delayed/failed imports, unavailable refresh, slow/failing local reads including a blocked MainActor, late completion, retained admission slots after timeout, and read-only/mixed batch behavior returning the required data/error and metadata within the defined budgets.  
3. <a name="6.3"></a>WHEN read latency is inspected, server diagnostics SHALL identify the request, outcome, and measured elapsed times for queueing, refresh waiting, capture/fetch, transformation, serialization, and batch aggregation; WHEN work completes after its caller timeout, its completion/discard SHALL be correlatable with the original request. The validation evidence SHALL use those measurements to distinguish slow stages without attributing unexplained delay to CloudKit.  
