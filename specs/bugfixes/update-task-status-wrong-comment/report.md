# Bugfix Report: update_task_status can return the wrong comment

**Date:** 2026-08-02
**Status:** In Progress

## Description of the Issue

When MCP `update_task_status` atomically changes a status and creates a comment, its response can serialize a different comment already associated with the task. A pre-existing future-dated comment caused by peer-device clock skew, or a concurrently imported remote comment, can be returned instead of the comment created by the request.

**Reproduction steps:**
1. Create a task with an existing comment whose `creationDate` is in the future.
2. Call `update_task_status` with a new status, comment, and author.
3. Observe that the status and new comment persist, but the response's `comment` object identifies the future-dated comment.

**Impact:** MCP clients receive a false confirmation payload and may attribute the wrong comment ID, content, author, and timestamp to their mutation.

## Investigation Summary

- **Symptoms examined:** The mutation succeeds and persists the requested comment, but response identity depends on global comment ordering.
- **Code inspected:** `MCPToolHandler.handleUpdateStatus`, `MCPToolHandler.appendCommentDetails`, `TaskService.updateStatus`, `CommentService.addComment`, and MCP comment tests.
- **Hypotheses tested:** Comment creation itself is correct and atomic. The defect occurs only during response assembly, where the handler refetches every task comment and selects the latest by `creationDate`.

## Discovered Root Cause

`TaskService.updateStatus` calls `CommentService.addComment` but discards the returned `Comment`. `MCPToolHandler.appendCommentDetails` therefore tries to rediscover the created record by fetching all comments sorted by `creationDate` and taking `.last`. Creation time is not a mutation identity: clock skew or concurrent sync can place another record last.

**Defect type:** Data-flow and identity-selection logic error.

**Five Whys:**
1. Why is the wrong comment returned? The handler serializes the last sorted comment.
2. Why does it select the last comment? It does not receive the comment created by the mutation.
3. Why is that identity unavailable? `TaskService.updateStatus` discards `CommentService.addComment`'s return value.
4. Why was refetching considered sufficient? The implementation assumed the newest timestamp uniquely identifies the local mutation.
5. Why is that assumption invalid? Comment timestamps originate on devices with potentially skewed clocks and remote comments can arrive concurrently.

**Contributing factors:** `creationDate` is useful for presentation order but is neither unique nor causally tied to the current request.

## Resolution for the Issue

_To be completed after the regression is proven and the fix is implemented._

## Regression Test

**Test file:** `Transit/TransitTests/MCPToolHandlerCommentTests.swift`
**Test name:** `updateStatusWithCommentReturnsExactCreatedCommentWhenExistingCommentIsFutureDated`

**What it verifies:** A future-dated existing comment cannot replace the exact comment created by `update_task_status` in the response payload.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/TransitTests/MCPToolHandlerCommentTests.swift` | Future-dated regression test |
| `specs/bugfixes/update-task-status-wrong-comment/report.md` | Investigation and resolution record |

## Verification

**Automated:**
- [x] Regression test fails before the fix (returned future-dated comment UUID differed from the created comment UUID)
- [ ] Regression test passes after the fix
- [ ] Full quick test suite passes
- [ ] Linters/validators pass

**Manual verification:**
- Inspect the response comment ID and confirm it equals the newly persisted comment's ID rather than the future-dated record's ID.

## Prevention

**Recommendations to avoid similar bugs:**
- Propagate mutation results directly across service boundaries instead of rediscovering them with ordering heuristics.
- Use timestamps for sorting only, not for record identity.

## Related

- Transit ticket: T-1823
