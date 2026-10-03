# Decision Log: Batch Task Queries

## Quick Decisions

| ID | Date | Decision | Rationale |
|----|------|----------|-----------|
| Q1 | 2026-10-03 | Use the full spec workflow for T-2379. | User approved the scope assessment; query response compatibility and pagination consistency require explicit API decisions. |
| Q2 | 2026-10-03 | Name the feature `batch-task-queries`. | User approved the proposed name, covering both batch lookup and bounded detail queries. |
| Q3 | 2026-10-03 | Scope changes to the MCP tool only. | User explicitly excluded App Intent changes. |
| Q4 | 2026-10-03 | Specify query-wide storage/comment failure behavior and preserve optional display IDs. | Critic and two independent peer reviews identified implicit error behavior and UUID-resolved tasks without allocated display IDs; the requirements now distinguish these from per-input identifier failures. |
| Q5 | 2026-10-03 | Requirements approved with pages/batches of at most 100 and five-minute frozen results. | User explicitly approved the requirements and authorized the design phase. |
| Q6 | 2026-10-03 | Include unexpected listener exit in snapshot invalidation, and classify filter errors before formatting. | Critic and both peer reviews confirmed the retained handler and existing typed lookup failures require these paths to preserve restart and error semantics. |
| Q7 | 2026-10-03 | Design approved, including capacity rejection and one-fetch batch resolution. | User explicitly approved the design and authorized task planning. |
| Q8 | 2026-10-03 | Implementation task list approved. | User approved the four TDD pairs and final lint/macOS regression gate; implementation requires its separate workflow. |
| Q9 | 2026-10-03 | Use branch `T-2379/batch-task-queries`. | User requested this exact name and switched the worktree; the current branch was verified before handoff. |

## Decision 1: Require Explicit Query Options Without Legacy Compatibility

**Date**: 2026-10-03
**Status**: accepted

### Context

Existing callers omit detail, comments, and pagination options and receive arrays. Preserving that contract would require maintaining separate legacy behavior.

### Decision

Require explicit options for initial queries and fail when required fields are missing. Backwards compatibility with the old query contract is not required.

### Rationale

The user chose the least-effort implementation and explicitly approved breaking existing calls. A single contract avoids maintaining legacy defaults and response paths.

### Alternatives Considered

- Preserve existing calls and opt into new behavior: rejected by the user because compatibility is unnecessary.
- Add a separate query tool: introduces another public surface without a requested need.

### Consequences

**Positive:** One query contract and explicit payload choices.

**Negative:** Existing MCP clients must update their calls and response parsing.

---

## Decision 2: Freeze Results For Short-Lived Pagination

**Date**: 2026-10-03
**Status**: accepted

### Context

Live task changes can shift page boundaries or change returned values during traversal. T-2379 requires no silent duplicates or omissions.

### Decision

Use frozen query results with a five-minute lifetime. Pages and batches contain at most 100 entries, as approved in the requirements.

### Rationale

The user selected frozen results after discussing live mutations. Freezing values provides predictable traversal without detecting every intervening change.

### Alternatives Considered

- Live pages with change detection: rejected in favor of simpler frozen traversal.
- Live pages without invalidation: cannot satisfy the ticket's consistency requirement.

### Consequences

**Positive:** Stable membership and values throughout traversal.

**Negative:** Results become stale during the lifetime; expired or lost snapshots require restarting the query.

---

## Decision 3: Cache Encoded Pages With Opaque Cursors

**Date**: 2026-10-03
**Status**: accepted

### Context

Frozen task and comment values must survive changes and deletion, and replayed cursors must return identical pages. The handler runs synchronously on the MainActor and is retained across listener restarts.

### Decision

Prepare all pages before publication, retain encoded strings in a handler-owned memory cache, and map random tokens directly to subsequent pages. Clear snapshots during listener teardown, unexpected current-listener exit, and listener launch. Limit retention to eight snapshots and 16 MiB of encoded page data; reject new queries rather than evict active snapshots.

### Rationale

Encoded pages avoid retaining SwiftData objects and eliminate continuation serialization or fetch failures. Direct token lookup avoids offset validation and signing. Capacity rejection preserves active pagination.

### Alternatives Considered

- Store copied dictionaries and serialize on continuation: retains more mutable structure and makes replay depend on another encoding step.
- Persist snapshots or encode offsets into signed tokens: adds storage or cryptographic machinery without a durability requirement.
- Evict oldest unexpired snapshots: permits new queries but interrupts active traversals.

### Consequences

**Positive:** Simple replay and fixed lifetime without model references or additional dependencies.

**Negative:** Initial calls prepare all result pages; large queries can exceed capacity, and retained page bytes require explicit accounting.

---

## Decision 4: Resolve Batches From One Task Fetch

**Date**: 2026-10-03
**Status**: accepted

### Context

The task fetch seam already exposes `fetchAllTasks`, while batches need ordered per-input outcomes and detection of duplicate identities.

### Decision

Fetch once and index matches by the batch identifier type. Do not add per-item fetch protocols or database batch predicates.

### Rationale

This is the least-effort path using the existing injectable interface and preserves duplicate detection. Fetch failures remain distinct from per-input not-found outcomes.

### Alternatives Considered

- Resolve each identifier through the service: creates up to 100 storage requests and new injection needs.
- Add predicate-based batch fetch APIs: narrows reads but adds service and predicate work without a measured need.

### Consequences

**Positive:** One fetch, deterministic input matching, and reuse of current test seams.

**Negative:** A small batch reads all tasks; this does not bound storage reads by batch size.

---
