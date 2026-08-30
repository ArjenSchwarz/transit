# T-2103 Implementation Explanation

## Beginner Level

### What Changed / What This Does

Creating a task or milestone pauses while Transit obtains its display ID. Previously, the selected project could be deleted during that pause, but creation would resume using its old in-memory project object and report success.

Transit now checks the project again after display-ID allocation, immediately before creating the dependent record. If the project was deleted, creation stops with the existing project-not-found behavior.

### Why It Matters

Callers no longer receive false success or leave behind a task or milestone after its required project has disappeared.

### Key Concepts

- **Race condition:** two operations overlap so an assumption that was true earlier is no longer true later.
- **Persistence boundary:** the final point before an object is inserted and saved.
- **Stale object:** an in-memory model that still looks valid even though another context deleted its stored row.

## Intermediate Level

### Changes Overview

`CreationProjectValidator` centralizes project-liveness checks for `TaskService.createTask` and `MilestoneService.createMilestone`. Both services call it after allocation and cancellation handling. `MilestoneService.Error` gains `projectNotFound`, with matching App Intent and MCP mappings.

Deterministic Swift Testing regressions suspend allocation, delete the project through a peer `ModelContext`, resume creation, and assert the exact domain error plus absence of pending and committed records.

### Implementation Approach

The validator reconciles two views of SwiftData state. The live context detects pending inserts and deletes, preserving valid unsaved projects and rejecting local pending deletion. A transient context checks committed storage so a stale registered project cannot hide a peer deletion. Fetch failures propagate rather than being converted to not-found.

### Trade-offs

A live-context-only check is cheaper but cannot detect a peer deletion hidden by registered state. A transient-only check rejects valid pending inserts. Combining both adds one bounded fetch per task or milestone creation after allocation, in exchange for correct persistence-boundary validation.

## Expert Level

### Technical Deep Dive

The defect was a TOCTOU window across `DisplayIDAllocator.allocateNextID`. MainActor isolation serializes individual execution segments but permits reentrancy at the allocation `await`. The post-await guard first inspects `deletedModelsArray`, then requires a live fetch, accepts a matching `insertedModelsArray` entry, and otherwise verifies committed existence through `ModelContext(modelContext.container)`. No suspension follows the check before the existing synchronous aggregate validation and `insertOrDelete` save path.

The implementation preserves CloudKit-compatible optional relationships, the shared container main context, pending insert semantics, creation-specific rollback behavior, and fail-closed fetch propagation. It mirrors the established fresh-context pattern used by `TaskCreationMilestoneValidator` without conflating project and milestone domain errors.

### Architecture Impact

Project existence is now an explicit service-layer invariant at both creation boundaries rather than a caller responsibility. Automation adapters preserve their existing public error contracts: App Intents return `PROJECT_NOT_FOUND`, MCP milestone creation returns `No matching project found`, and UI callers receive the localized service error.

### Potential Issues

The transient committed-state fetch is additional creation-path I/O, but it is a single UUID lookup outside rendering and startup paths. SwiftData does not provide a transaction spanning CloudKit counter allocation and local model insertion, so no application-level probe can eliminate deletion occurring after the final check on a truly concurrent executor; the implementation closes the known suspension window and keeps all remaining service work synchronous on MainActor.

## Completeness Assessment

- **Fully implemented:** task and milestone service guards, live/pending and committed-state reconciliation, exact domain errors, App Intent and MCP mappings, deterministic peer-deletion regressions, changelog, and bugfix report.
- **Partially implemented:** none.
- **Missing:** none for T-2103. The full macOS and iOS suites, dedicated UI suite, lint/ownership validators, and iOS/macOS builds all pass.
