# Bugfix Report: MCP Notifications Acknowledged Without Executing

**Date:** 2026-08-05
**Status:** Fixed

## Description of the Issue

A JSON-RPC notification omits the `id` member. It must still execute its method, but it must not produce a JSON-RPC response. The historical handler returned `nil` before dispatching notification-shaped requests, so mutating `tools/call` notifications could receive HTTP 202 without creating their intended task or comment.

**Reproduction steps:**
1. Send a `tools/call` notification with no `id` for a mutating tool.
2. Observe the HTTP 202/no-body transport acknowledgement.
3. Verify that the requested mutation is persisted.

**Impact:** Agent clients can silently lose task-management mutations while receiving the expected notification acknowledgement.

## Investigation Summary

- **Symptoms examined:** Missing side effects despite correct notification response suppression.
- **Code inspected:** `MCPToolHandler.handle(_:)`, `MCPServer` single and batch routes, JSON-RPC ID decoding, and MCP lifecycle/batch tests.
- **Hypotheses tested:** Whether the route skipped dispatch, batch response filtering skipped dispatch, or the handler returned before its method switch.

The current branch already contains the production correction from `8b98e1f` (T-1834): `MCPToolHandler.handle(_:)` computes the method response after normal dispatch and only then returns `nil` for a notification. Targeted baseline tests passed before this ticket's test additions.

## Discovered Root Cause

The original defect was a **logic error**: notification response suppression was applied before method dispatch rather than after it. That conflated “do not send a response” with “do not execute the method.”

The current implementation corrects the causation chain by dispatching all valid requests through the normal method/tool path, then discarding only notification responses. Explicit `id: null` remains a non-notification invalid request; batched `initialize` retains its lifecycle rejection; HTTP transports return 202 only when no response objects remain.

## Resolution for the Issue

**Changes made:**
- `Transit/TransitTests/MCPNotificationDispatchTests.swift` — added T-1820 regression coverage for direct handler dispatch, a single HTTP mutation notification, and an ordered mixed batch with a notification failure.

**Approach rationale:** The production dispatcher already applies response suppression at the correct boundary. The new tests pin its required behavior across the direct handler and HTTP transport paths without making an unnecessary source change.

**Alternatives considered:**
- Rework the existing handler — rejected because the current branch already dispatches before suppressing notification responses.
- Cover only all-notification batches — rejected because it would not prove direct handler behavior, single-request HTTP mutation behavior, or ordering against a following valid request.

## Regression Test

**Test file:** `Transit/TransitTests/MCPNotificationDispatchTests.swift`

**Test names:**
- `directToolCallNotificationExecutesMutationButSuppressesResponse`
- `singleToolCallNotificationOverHTTPExecutesMutationWithAcceptedNoBody`
- `mixedBatchExecutesNotificationBeforeRequestAndSuppressesNotificationFailures`

**What they verify:** A no-ID mutation executes through the handler and returns no response; a single HTTP notification persists an `add_comment` mutation while returning HTTP 202/no body; a mixed batch applies its notification status mutation before a valid request observes it and suppresses both successful and failed notification responses.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/TransitTests/MCPNotificationDispatchTests.swift` | Direct, HTTP, and ordered mixed-batch mutation notification regressions. |
| `specs/bugfixes/mcp-notifications-acknowledged-without-executing/report.md` | Investigation and resolution record. |
| `CHANGELOG.md` | Unreleased T-1820 regression-coverage entry. |

## Verification

**Automated:**
- [x] Focused `MCPNotificationDispatchTests` pass.
- [x] Full macOS unit suite passes (`make test-quick`).
- [x] Linters and the SwiftData ownership guard pass (`make lint`).
- [ ] `make test` did not complete cleanly: its unit portion ran, then the UI portion reported existing-looking failures in `TransitUITests.testClearAll`, `TransitUITests.testEditViewPreservesTaskMilestone`, and `DataMaintenanceUITests.testDataMaintenanceGoldenPath` before the runner timed out.

**Manual verification:** Inspected `MCPToolHandler.handle(_:)` and `MCPServer.batchResponse`; valid dispatch occurs before notification response suppression, batch dispatch remains sequential, and all-notification batches return HTTP 202 with no body.

## Prevention

- Keep notification side-effect assertions alongside response-suppression assertions.
- Test handler and HTTP transport independently, including ordered mixed batches and notification errors.
- Preserve the `isNotification` presence distinction so explicit JSON `null` IDs remain invalid requests rather than notifications.

## Related

- T-1820
- T-1834 / commit `8b98e1f` — JSON-RPC batch support that contains the production dispatch-before-suppression fix.
- T-1863 — explicit-null request-ID validation.
