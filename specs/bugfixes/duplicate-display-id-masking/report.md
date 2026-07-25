# Bugfix Report: Mutation APIs Hide Duplicate Task Display IDs

**Date:** 2026-07-26
**Status:** Fixed

## Description of the Issue

`TaskService.findByDisplayID` detects when more than one task carries the same
`permanentDisplayId` — a state CloudKit can produce because it cannot enforce
unique constraints — and throws `TaskService.Error.duplicateDisplayID`. Every
task *mutation* entry point then discarded that distinction: the resolver call
sites matched only `invalidIdentifier(field:)` and let a catch-all `catch`
absorb everything else, reporting the failure as "task not found" / "provide
either displayId or taskId".

**Reproduction steps:**
1. Get two tasks with the same `permanentDisplayId` into the store (CloudKit sync
   conflict; reproducible in tests by inserting two `TransitTask` rows with
   `displayID: .permanent(42)`).
2. Call MCP `update_task_status`, `update_task`, or `add_comment`, or the
   `UpdateStatusIntent` / `UpdateTaskIntent` / `AddCommentIntent` App Intents,
   with `displayId: 42`.
3. The response is `TASK_NOT_FOUND` ("Provide either displayId (integer) or
   taskId (UUID)") even though two tasks with that ID exist.

**Impact:** Medium. No data is corrupted by the call — resolution fails before
any mutation — but the operator is told the task does not exist. That is
actively misleading: the correct remedy is display-ID maintenance
(`scan_duplicate_display_ids` / `reassign_duplicate_display_ids`), and nothing in
the response pointed there. The behaviour was also inconsistent inside the app:
`QueryTasksIntent` already reported this correctly (T-1097) and every milestone
path already reported it correctly.

## Investigation Summary

- **Symptoms examined:** identical error payloads for "missing task" and
  "duplicate task identifier" on all task mutation surfaces.
- **Code inspected:**
  - `Transit/Transit/Services/TaskService.swift` — `findByDisplayID`, both
    `resolveTask` overloads
  - `Transit/Transit/MCP/MCPToolHandler.swift` — `handleUpdateStatus`,
    `handleUpdateTask`, `handleAddComment`, `handleDisplayIdLookup`, plus the
    milestone resolvers that already handle duplicates
  - `Transit/Transit/Intents/IntentHelpers.swift` — `resolveTask`,
    `mapMilestoneError`, `resolveMilestoneByDisplayId`
  - `Transit/Transit/Intents/UpdateStatusIntent.swift`,
    `Transit/Transit/Intents/AddCommentIntent.swift`,
    `Transit/Transit/Intents/QueryTasksIntent.swift` (T-1097 precedent)
- **Hypotheses tested and ruled out:**
  - *The service loses the distinction* — no: `findByDisplayID` throws
    `.duplicateDisplayID` and `resolveTask` propagates it unchanged.
  - *The mutation happens anyway* — no: resolution fails before any mutation, so
    the store is untouched. The defect is purely in error reporting.

## Discovered Root Cause

Each task-resolver call site pattern-matched only
`TaskService.Error.invalidIdentifier(field:)` and let a bare `catch` absorb
everything else, mapping it to a not-found/bad-identifier message.
`.duplicateDisplayID` therefore hit the catch-all at five sites.

**Defect type:** Lost error classification (error-mapping defect).

**Why it occurred:** The catch-all branches predate `.duplicateDisplayID`. When
the duplicate case was added to the services, only the read paths were updated —
`QueryTasksIntent` (T-1097) and the milestone resolvers. The mutation paths kept
their original two-branch shape, and a catch-all absorbs a newly added error case
without any compiler warning.

**Contributing factors:** The same resolve-and-map block was copy-pasted at five
call sites, so nothing forced them to stay in sync.

## Resolution for the Issue

**Error code:** `INTERNAL_ERROR` — no new code was introduced. This matches
`IntentHelpers.mapMilestoneError(.duplicateDisplayID)`,
`IntentHelpers.resolveMilestoneByDisplayId`, and the T-1097 `QueryTasksIntent`
fix. MCP has no error codes, so duplicates there return an `isError` tool result
whose wording mirrors the milestone tools' "Duplicate milestone identifier
detected for displayId N".

**Changes made:**
- `Transit/Transit/Intents/IntentHelpers.swift` — `resolveTask` gained a
  `catch TaskService.Error.duplicateDisplayID` branch returning
  `INTERNAL_ERROR`; new `duplicateTaskIdentifierHint(from:)` builds the hint
  ("Duplicate task identifier for displayId N"). This covers `UpdateTaskIntent`
  and `UpdateStatusIntent`, both of which route through it.
- `Transit/Transit/Intents/UpdateStatusIntent.swift` — replaced its inlined copy
  of the resolver mapping with `IntentHelpers.resolveTask`. The inlined copy was
  what let this surface drift; the shared helper removes the third variant. The
  "no identifier at all" INVALID_INPUT preflight is unchanged.
- `Transit/Transit/Intents/AddCommentIntent.swift` — duplicates now throw
  `VisualIntentError.duplicateIdentifier` instead of `.taskNotFound`.
- `Transit/Transit/Intents/Visual/VisualIntentError.swift` — added
  `duplicateIdentifier(String)` with code `INTERNAL_ERROR` and a recovery
  suggestion pointing at display-ID maintenance.
- `Transit/Transit/MCP/MCPToolHandler.swift` — added
  `resolveTaskArgument(_:)`, one shared resolver used by `update_task_status`,
  `update_task`, and `add_comment` (replacing three copies of the mapping), plus
  `duplicateTaskIdentifierMessage(displayId:)`. `handleDisplayIdLookup`
  (`query_tasks`) now names the duplicate instead of emitting
  "Lookup failed: duplicateDisplayID".

`TaskService.swift` needed no change — it already threw the right error.

**Approach rationale:** Preserve the existing contract rather than invent a new
error code. Both precedents (milestones, T-1097) use `INTERNAL_ERROR`, so the app
now has one rule: a display ID matching several records is an internal/store
error, not a client error. Routing each surface through a single shared resolver
means the next error case added to `TaskService.Error` has to be handled in one
place per surface, not five.

**Alternatives considered:**
- **A dedicated `DUPLICATE_DISPLAY_ID` error code** — rejected: it would create a
  third variant, contradict the milestone paths, and require updating the
  documented error-code list in CLAUDE.md for no caller benefit.
- **Mapping duplicates to `INVALID_INPUT`** — rejected: the request is
  well-formed; the store is at fault, which is exactly what `INTERNAL_ERROR`
  means in this codebase.
- **Adding the catch branch at each call site without extracting a helper** —
  rejected: it preserves the copy-paste that caused the drift.

## Regression Test

**Test files:**
- `Transit/TransitTests/DuplicateTaskDisplayIDIntentTests.swift`
- `Transit/TransitTests/MCPDuplicateTaskDisplayIDTests.swift` (macOS-only)

**What they verify:** with two tasks sharing display ID 42, every task mutation
surface reports a duplicate-identifier error naming the display ID
(`INTERNAL_ERROR` for the JSON intents and `AddCommentIntent`, an `isError` tool
result for MCP), leaves both tasks unmutated (status, name, comment count), and
still reports a genuinely missing task as `TASK_NOT_FOUND`. `query_tasks` is
covered too, so all four MCP task-by-displayId paths report duplicates alike.

**Run command:** `make test-quick`

Before the fix, 9 of the 13 tests failed and the 4 "still reports not found"
control tests passed.

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Intents/IntentHelpers.swift` | duplicate branch in `resolveTask` + `duplicateTaskIdentifierHint(from:)` |
| `Transit/Transit/Intents/UpdateStatusIntent.swift` | route resolution through `IntentHelpers.resolveTask` |
| `Transit/Transit/Intents/AddCommentIntent.swift` | throw `.duplicateIdentifier` on duplicates |
| `Transit/Transit/Intents/Visual/VisualIntentError.swift` | new `duplicateIdentifier` case (INTERNAL_ERROR) |
| `Transit/Transit/MCP/MCPToolHandler.swift` | shared `resolveTaskArgument` + duplicate message; `query_tasks` lookup |
| `Transit/TransitTests/DuplicateTaskDisplayIDIntentTests.swift` | new regression tests (App Intents) |
| `Transit/TransitTests/MCPDuplicateTaskDisplayIDTests.swift` | new regression tests (MCP) |

## Verification

**Automated:**
- [x] Regression tests fail before the fix (9 failures) and pass after
- [x] `make test-quick` (macOS unit suite) passes with no new failures
- [x] `make lint` (SwiftLint --strict) passes with 0 violations

iOS Simulator suites (`make test`, `make test-ui`) were skipped for this run by
explicit instruction; the change is platform-independent apart from the
macOS-only MCP handler.

## Prevention

- When a service error enum gains a case, grep for every `catch` on that enum —
  catch-all branches absorb new cases with no compiler warning. A `catch let
  error as TaskService.Error { switch error { ... } }` shape would be exhaustive
  and fail to compile when a case is added; worth considering if this recurs.
- Keep one shared resolver per surface (`IntentHelpers.resolveTask`,
  `MCPToolHandler.resolveTaskArgument`) rather than inlined copies.

## Related

- T-1097 — same fix for `QueryTasksIntent` (read path)
- T-687 — introduced duplicate display ID detection in the services
- T-808 — `invalidIdentifier(field:)` mapping at the same call sites
