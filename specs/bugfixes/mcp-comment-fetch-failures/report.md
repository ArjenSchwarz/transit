# Bugfix Report: mcp-comment-fetch-failures

**Date:** 2026-08-04
**Status:** Fixed

## Description of the Issue

`query_tasks` serializes comments with `(try? commentService.fetchComments(for: task.id)) ?? []`. A SwiftData read failure therefore appears to MCP clients as a successful task query with `comments: []`, indistinguishable from a task with no comments.

**Reproduction steps:**
1. Configure the MCP handler with a deterministic `CommentService.fetchComments` failure.
2. Query an existing task through `query_tasks` (both detailed display-ID and list paths).
3. Observe a successful response with an empty `comments` array rather than a tool error.

**Impact:** Agents can miss discussion and audit history and incorrectly treat an unreadable store as a valid empty result.

## Investigation Summary

- **Symptoms examined:** Swallowed comment-fetch errors become an empty comments collection in task responses.
- **Code inspected:** `MCPToolHandler.taskToDict`, both `query_tasks` response paths, `CommentService.fetchComments`, status-comment serialization, and MCP regression conventions.
- **Hypotheses tested:** The historical `update_task_status` fetch-and-append path was checked. T-1823 already replaced it with direct serialization of the `Comment` returned by the atomic mutation, so it has no post-commit fetch failure to mask.

## Discovered Root Cause

**Defect type:** Error handling / data-flow error.

**Why it occurred:** `taskToDict` catches all `fetchComments` errors with `try?` and substitutes `[]`, losing the distinction between a valid empty relationship query and storage failure. Both `query_tasks` response paths call this helper.

**Contributing factors:** The status path had historically shared this weakness, but its later direct-result design correctly avoids response-enrichment reads after persistence.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/Services/CommentService.swift` — Introduced the narrow `CommentFetching` protocol while retaining `CommentService` as its production implementation.
- `Transit/Transit/MCP/MCPToolHandler.swift` — Injects the comment reader and makes task serialization throw. Both detailed display-ID and list responses catch that failure at the MCP boundary and return the established `isError` tool result `Failed to fetch comments: <error>`.
- `Transit/TransitTests/MCPTestHelpers.swift` — Threads an optional comment reader into the handler test environment.
- `Transit/TransitTests/MCPCommentFetchFailureTests.swift` — Adds deterministic error, valid-empty, and status-mutation safety coverage.

**Approach rationale:** A throwing read boundary preserves the semantic difference between an unreadable store and a task that genuinely has no comments, while retaining the existing successful JSON response shapes. The status path intentionally continues to serialize `TaskService.updateStatus`'s returned `Comment` directly. The mutation has already committed before any hypothetical enrichment read; avoiding that read prevents an error response that could encourage callers to repeat a successful status/comment operation.

**Alternatives considered:**
- Reintroduce a post-commit comment fetch for `update_task_status` and return an error when it fails — rejected because T-1823 already removed that stale-result-prone design, and a post-persist error would give clients an ambiguous retry signal.
- Return `comments: []` or omit `comments` after a query failure — rejected because either response is indistinguishable from valid empty data.

## Regression Test

**Test file:** `Transit/TransitTests/MCPCommentFetchFailureTests.swift`

**Test names:**
- `queryDetailedTaskCommentFetchFailureReturnsExactErrorInsteadOfEmptyComments`
- `queryTaskListCommentFetchFailureReturnsExactErrorInsteadOfEmptyComments`
- `queryTaskWithValidEmptyCommentsReturnsSuccessfulEmptyArray`
- `updateStatusWithCommentDoesNotFetchResponseDetailsAfterPersisting`

**What they verify:** A deterministic comment-fetch failure produces the exact MCP tool error on both query response paths; a genuine empty comments result remains successful; status-plus-comment returns the persisted comment without a post-commit fetch or duplicate creation.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/MCP/MCPToolHandler.swift` | Propagate comment-read failures from task serialization. |
| `Transit/Transit/Services/CommentService.swift` | Provide the narrow injectable comment-read protocol. |
| `Transit/TransitTests/MCPTestHelpers.swift` | Allow deterministic comment-fetch seam injection. |
| `Transit/TransitTests/MCPCommentFetchFailureTests.swift` | Cover error, valid-empty, and mutation-safety behavior. |
| `CHANGELOG.md` | Record the MCP error-propagation behavior. |

## Verification

**Automated:**
- [x] Regression tests pass — `make test-quick` (macOS result bundle: 1,720 passed, 0 failed)
- [x] Full macOS unit suite passes — `make test-quick`
- [x] Linters/validators pass — `make lint`

**Manual verification:** The deterministic failing reader returns the exact MCP tool error on both query response paths; a real empty comment relationship returns successful `comments: []`; a failing reader is never called by a status-plus-comment response, which still persists and returns exactly one comment.

## Prevention

- Do not use `try?` with a value fallback where storage failure is semantically different from a valid empty result.
- Prefer serializing the object returned by an atomic mutation over refetching it for response enrichment.

## Related

- Transit ticket: T-1613
- T-1823: direct status-comment serialization removed the historical post-mutation fetch path.
