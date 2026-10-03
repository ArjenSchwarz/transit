# Batch Task Queries — Implementation

## Beginner Level

### What Changed

The MCP task query now asks callers to choose summary or full detail, whether to include comments, and a page size from 1 to 100. It returns a results object with a next-page cursor and expiry instead of an array. Known task UUIDs or display IDs can be looked up in batches of up to 100.

### Why It Matters

An agent can retrieve 182 chore descriptions in two requests. Later pages preserve the values captured by the first request, even when tasks or comments change.

### Key Concepts

A snapshot is a temporary copy of the query results. A cursor is a random token that retrieves the next saved page; it expires five minutes after the initial query starts.

## Intermediate Level

### Architecture

`MCPTaskQueryRequest` separates strict initial options from cursor-only continuation. The handler reuses existing filters and `IntentHelpers.taskToDict`, indexes one fetch for batches, and serializes each unique task and its requested comments once. Batch outcomes retain input indexes, including repeats and explicit missing/ambiguous-ID failures.

### Implementation Approach

`encodeQueryPages` encodes every page before publication. `MCPTaskQuerySnapshotStore` retains immutable JSON text behind opaque tokens, with monotonic expiry and an eight-snapshot/16 MiB limit. No live SwiftData models are cached; cursor replay reads the same saved text without a fetch. One formatter is shared across task serialization within a query.

### Trade-offs

Compatibility with the old request defaults and array payload was explicitly waived. Batch lookup reads all tasks once rather than adding another service API. Snapshot capacity rejects new multi-page queries rather than evicting active traversals. These choices are recorded in Decisions 1–4.

## Expert Level

### Contracts and Failure Boundaries

Initial preparation is synchronous on MainActor, preventing app mutations from interleaving with selection and serialization. Requested-comment or storage failures abort publication; identifier failures stay local to batch outcomes. Lists sort by UUID, batches by input position, and comments by creation date then UUID. Continuation rejects extra options and never replaces an expired snapshot with current data.

### Lifecycle and Memory

The server closes query admission and clears snapshots before shutdown awaits, on generation-checked listener completion, and at replacement launch. Stale callbacks cannot clear a replacement listener's pages. Encoded byte accounting is conservative because it counts all prepared pages even though only continuation pages are retained; limits do not promise a bound on transient SwiftData fetch or dictionary preparation memory.

### Edge Cases

UUID-resolved tasks without allocated display IDs omit that field. Nil descriptions are JSON null; empty metadata is omitted. Repeated batch identities reuse serialization but preserve distinct result positions. Malformed, unknown, cleared, and expired cursors return explicit restart guidance.

## Completeness Assessment

All approved requirements and nine tasks are implemented. Tests cover strict parsing, fields and filters, ordered batch failures, frozen task/comment values, replay, expiry/capacity, and server lifecycle invalidation. No partial or missing feature behavior was identified in the review. App Intents, persisted models, custom ordering/date filters, and durable cursors remain outside scope.

The pre-push test registry has no matching Xcode/JUnit runner, so the review page reports native project-gate outcomes without JUnit totals or coverage. Refer to the review page for the current verification verdict.
