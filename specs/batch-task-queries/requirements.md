# Batch Task Queries — Requirements

## Introduction

T-2379 extends the MCP `query_tasks` tool so agents can retrieve task descriptions in bounded pages and look up several known tasks in one request. Callers explicitly choose detail level, comments, and page size. Short-lived frozen results keep multi-page reads consistent while tasks change.

## Non-Goals

- Changes to App Intents, the UI, or persisted task models.
- Compatibility with callers that omit the new required query options or expect the old array response.
- Configurable ordering or new activity/completion date filters.
- Cursors that survive MCP server restart or expiry.

### 1. Explicit Query Options and Detail

**User Story:** As an agent, I want explicit query options, so that I control result size and content.

**Acceptance Criteria:**

1. <a name="1.1"></a>WHEN starting a query, the tool SHALL require `detailLevel` (`summary` or `full`), `includeComments` (boolean), and `limit` (integer from 1 through 100); missing or invalid values SHALL return a tool error without query results.  
2. <a name="1.2"></a>WHEN `detailLevel` is `summary`, each task SHALL contain `taskId`, `name`, `status`, `type`, `priority`, and `lastStatusChangeDate`, with `displayId`, `projectId`, `projectName`, `completionDate`, and `milestone` included only when present using their existing shapes; WHEN it is `full`, each task SHALL additionally contain `description` (string or null) and `metadata` (object when non-empty, omitted otherwise).  
3. <a name="1.3"></a>WHEN `includeComments` is false, task results SHALL omit comments and SHALL succeed even if comment retrieval is unavailable; WHEN true, each task SHALL include a comments array (empty when there are none), with `id`, `authorName`, `content`, `isAgent`, and `creationDate` for each comment, ordered by creation date ascending with comment UUID ascending as the tie-breaker.  
4. <a name="1.4"></a>WHEN a query succeeds, the tool SHALL return an object containing the bounded results, a next-page cursor or null, and the snapshot expiry time; it SHALL NOT return an unbounded array.  
5. <a name="1.5"></a>WHEN any initial query encounters a storage or requested-comment retrieval failure, the tool SHALL return a tool error without partial results or a continuation cursor.  

### 2. Filtered Lists and Single-ID Lookup

**User Story:** As an agent, I want existing task selection behavior, so that I can retrieve the tasks relevant to my work.

**Acceptance Criteria:**

1. <a name="2.1"></a>WHEN querying a list, the tool SHALL preserve the existing project/projectId, status, not_status, unfinished, type, priority, milestone/milestoneDisplayId, and substring-search selection and validation behavior.  
2. <a name="2.2"></a>WHEN `displayId` is supplied, the tool SHALL apply the existing filters conjunctively to that task, return an empty result for a missing or nonmatching task, and return a tool error for an ambiguous display ID or storage failure; explicit detail and comments options SHALL control its content.  
3. <a name="2.3"></a>WHEN a filtered list is paginated, its task order SHALL be task UUID ascending, independent of task edits or display-ID allocation.  
4. <a name="2.4"></a>WHEN a list has no matching tasks, the tool SHALL return an empty result and null next-page cursor.  

### 3. Batch Lookup

**User Story:** As an agent, I want to look up multiple task identities at once, so that I avoid one request per task.

**Acceptance Criteria:**

1. <a name="3.1"></a>WHEN a caller supplies `taskIds` (UUID strings) or `displayIds` (integers), the tool SHALL accept 1 through 100 identifiers and return one outcome per input position in input order, including repeated inputs.  
2. <a name="3.2"></a>WHEN a batch item resolves uniquely, its outcome SHALL contain the requested identifier, input position, task UUID, and task data using the requested detail and comments options; its task display ID SHALL be included only when allocated.  
3. <a name="3.3"></a>WHEN a batch identifier is missing or ambiguous, its outcome SHALL identify that input and distinguish not-found from ambiguous-ID failure; other resolvable items SHALL still be returned.  
4. <a name="3.4"></a>WHEN identifier arrays are empty, oversized, or contain malformed identifiers, or a request combines multiple selectors (`displayId`, `taskIds`, `displayIds`), the tool SHALL reject the entire request with a tool error.  
5. <a name="3.5"></a>WHEN batch selectors are combined with list filters, the tool SHALL reject the request with a tool error rather than silently omit requested identities.  

### 4. Frozen Pagination

**User Story:** As an agent, I want consistent pages, so that changes during retrieval do not silently skip or repeat results.

**Acceptance Criteria:**

1. <a name="4.1"></a>WHEN a query starts, its result membership, order, task values, batch outcomes, and requested comments SHALL be frozen for five minutes from creation; subsequent task or comment creation, edits, deletion, or sync SHALL NOT change its pages.  
2. <a name="4.2"></a>WHEN a caller follows every next-page cursor before expiry, each page SHALL contain at most the original `limit` outcomes, and traversal SHALL return the complete frozen result exactly once per result position.  
3. <a name="4.3"></a>WHEN continuing a query, the caller SHALL supply only the cursor; supplying filters, selectors, or query options alongside it SHALL return a tool error.  
4. <a name="4.4"></a>WHEN a valid cursor is reused before expiry, it SHALL return the same page and next-page cursor without extending the snapshot lifetime.  
5. <a name="4.5"></a>WHEN a cursor is malformed, unknown, expired, or invalidated by server restart, the tool SHALL return an explicit error instructing the caller to start a new query; it SHALL NOT silently query current data.  
6. <a name="4.6"></a>IF resource limits prevent starting or retaining a snapshot, the tool SHALL reject a new query or explicitly invalidate affected cursors; it SHALL NOT truncate successful results or silently replace a snapshot.  

### 5. Discoverable Contract

**User Story:** As an agent, I want a discoverable query contract, so that I can call the tool correctly without trial and error.

**Acceptance Criteria:**

1. <a name="5.1"></a>The MCP tool schema and documentation SHALL describe required initial-query options, cursor-only continuation, selector/filter restrictions, response fields, ordering, identifier failures, page and batch limits, and the five-minute expiry.  
2. <a name="5.2"></a>WHEN querying 182 matching chores with `detailLevel: full`, `includeComments: false`, and `limit: 100`, the tool SHALL return their identities and descriptions in two pages when continued before expiry, without individual detail requests.  
