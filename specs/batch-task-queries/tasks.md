---
references:
    - specs/batch-task-queries/requirements.md
    - specs/batch-task-queries/design.md
    - specs/batch-task-queries/decision_log.md
---
# Batch Task Queries — Implementation Tasks

- [x] 1. Red: test request validation and advertised schema <!-- id:whb9rf8 -->
  - Add MCPTaskQueryRequestTests and query-schema assertions. Cover initial/continuation branches, missing/null/wrong-type options, limit and batch boundaries, malformed UUIDs, integral versus fractional numbers, booleans as IDs, unknown fields, mixed selectors, batch filters, and cursor plus other fields.
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [3.4](requirements.md#3.4), [3.5](requirements.md#3.5), [4.3](requirements.md#4.3), [5.1](requirements.md#5.1)

- [x] 2. Green: implement request parsing and query schema <!-- id:whb9rf9 -->
  - Create MCP/MCPTaskQueryRequest.swift. Add optional oneOf/additionalProperties to JSONSchema without changing other schemas, and update queryTasks properties and descriptions. Wire validation into the query entry point; reuse strict integer/boolean helpers and preserve existing filter values and precedence.
  - Blocked-by: whb9rf8 (Red: test request validation and advertised schema)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [3.4](requirements.md#3.4), [3.5](requirements.md#3.5), [4.3](requirements.md#4.3), [5.1](requirements.md#5.1)

- [x] 3. Red: test frozen page storage and pagination invariants <!-- id:whb9rfa -->
  - Add MCPTaskQuerySnapshotStoreTests with injected clocks, cursors, and small capacity limits. Verify replay, exact expiry boundary, no lifetime extension, unknown tokens, no eviction, byte accounting, clear, failed publication, and expired preparation. Generate counts 0/1/99/100/101/182/500 with limits 1/2/50/100; concatenation must equal input positions and page size must stay bounded.
  - Blocked-by: whb9rf9 (Green: implement request parsing and query schema)
  - Stream: 1
  - Requirements: [1.4](requirements.md#1.4), [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [4.4](requirements.md#4.4), [4.5](requirements.md#4.5), [4.6](requirements.md#4.6)

- [x] 4. Green: implement and attach the snapshot store <!-- id:whb9rfb -->
  - Create MCP/MCPTaskQuerySnapshotStore.swift and attach an injectable instance to MCPToolHandler. Publish immutable encoded pages atomically; retain at most eight snapshots/16 MiB, reject capacity exhaustion, use five-minute monotonic deadlines and fixed wall expiry, and expose cursor lookup/clear. Keep models out of the cache and guard preparation byte count and expiry.
  - Blocked-by: whb9rfa (Red: test frozen page storage and pagination invariants)
  - Stream: 1
  - Requirements: [1.4](requirements.md#1.4), [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [4.4](requirements.md#4.4), [4.5](requirements.md#4.5), [4.6](requirements.md#4.6)

- [x] 5. Red: test query pages, detail options, batches, and preserved filters <!-- id:whb9rfc -->
  - Add MCPTaskQueryTests with TestModelContainer and throwing/counting fetchers; add page decoding and explicit options to existing MCP query tests without auto-defaulting production requests. Cover full/summary fields, nullable descriptions, metadata, optional display IDs, comments order/omission, single lookup, existing filters, typed project/milestone errors, one-fetch batches, repeated inputs, per-ID failures, and failure without published pages. Exercise 182 chores and task/comment edits/deletions/creation between pages; preserve App Intent and unrelated array-tool assertions.
  - Blocked-by: whb9rfb (Green: implement and attach the snapshot store)
  - Stream: 1
  - Requirements: [1.2](requirements.md#1.2), [1.3](requirements.md#1.3), [1.4](requirements.md#1.4), [1.5](requirements.md#1.5), [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [2.3](requirements.md#2.3), [2.4](requirements.md#2.4), [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3), [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [5.2](requirements.md#5.2)

- [x] 6. Green: implement paginated task queries and ordered batch outcomes <!-- id:whb9rfd -->
  - Extract MCPToolHandler+TaskQuery.swift, exposing only required dependencies/shared helpers. Preserve filter resolution and classify typed failures before formatting. Index one task fetch for batches, retain duplicate matches, order lists by UUID and batches by input index, serialize each unique task/comments once, and encode all pages with throwing Foundation JSON serialization before publication. Wire cursor-only reads, structured query errors, and exact results/nextCursor/expiresAt payloads; update tool descriptions with final response and error contract. Run the focused query suites through Makefile tooling.
  - Blocked-by: whb9rfc (Red: test query pages, detail options, batches, and preserved filters)
  - Stream: 1
  - Requirements: [1.2](requirements.md#1.2), [1.3](requirements.md#1.3), [1.4](requirements.md#1.4), [1.5](requirements.md#1.5), [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [2.3](requirements.md#2.3), [2.4](requirements.md#2.4), [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3), [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [5.1](requirements.md#5.1), [5.2](requirements.md#5.2)

- [x] 7. Red: test snapshot invalidation across server lifecycle changes <!-- id:whb9rfe -->
  - Extend MCPServer lifecycle tests and handler admission tests. Verify stop/restart and unexpected current-listener exit clear snapshots, bind failure closes admission, queued requests fail while closed, launch starts with empty cache, and stale-generation callbacks do not clear replacement snapshots.
  - Blocked-by: whb9rfd (Green: implement paginated task queries and ordered batch outcomes)
  - Stream: 1
  - Requirements: [4.5](requirements.md#4.5), [4.6](requirements.md#4.6)

- [x] 8. Green: wire lifecycle cache invalidation and query admission <!-- id:whb9rff -->
  - Update MCPServer tearDownCurrentServer before shutdown awaits, generation-checked setNotRunning, and launchServer to close/clear/reset/reopen query admission. Add only the required handler lifecycle interface. Run focused lifecycle and cursor tests; no listener generation redesign.
  - Blocked-by: whb9rfe (Red: test snapshot invalidation across server lifecycle changes)
  - Stream: 1
  - Requirements: [4.5](requirements.md#4.5), [4.6](requirements.md#4.6)

- [x] 9. Run lint and macOS regression gates <!-- id:whb9rfg -->
  - Run run_silent make lint and run_silent make test-quick once after integration. Keep full logs on disk and inspect concise failure excerpts; repair feature regressions with focused reruns. Report inherited failures separately. Full iOS/UI gates remain in pre-push review.
  - Blocked-by: whb9rff (Green: wire lifecycle cache invalidation and query admission)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.3](requirements.md#1.3), [1.4](requirements.md#1.4), [1.5](requirements.md#1.5), [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [2.3](requirements.md#2.3), [2.4](requirements.md#2.4), [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3), [3.4](requirements.md#3.4), [3.5](requirements.md#3.5), [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [4.3](requirements.md#4.3), [4.4](requirements.md#4.4), [4.5](requirements.md#4.5), [4.6](requirements.md#4.6), [5.1](requirements.md#5.1), [5.2](requirements.md#5.2)
