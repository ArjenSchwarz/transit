# Bugfix Report: Create Task Intent Drops Metadata JSON

**Date:** 2026-03-13
**Status:** Investigating

## Description of the Issue

`CreateTaskIntent` silently drops JSON metadata provided by App Intent callers. Inputs such as
`"metadata":{"git.branch":"main"}` create the task successfully, but the saved task has an empty
`metadata` dictionary.

**Reproduction steps:**
1. Call `CreateTaskIntent.execute` with valid JSON that includes a `metadata` object.
2. Parse the returned `taskId` and fetch the created task from `TaskService`.
3. Observe that the task metadata is empty instead of containing the provided key/value pairs.

**Impact:** App Intent and Shortcut callers cannot attach metadata to created tasks, which breaks
automation flows that rely on `git.*`, `agent.*`, or similar reserved metadata namespaces.

## Investigation Summary

Inspected the Create Task App Intent flow end to end and compared it with the MCP tool path that
already handles metadata correctly.

- **Symptoms examined:** Tasks created through `CreateTaskIntent` ignored metadata from JSON input.
- **Code inspected:** `Transit/Transit/Intents/CreateTaskIntent.swift`,
  `Transit/Transit/Intents/IntentHelpers.swift`, `Transit/Transit/MCP/MCPToolHandler.swift`,
  `Transit/TransitTests/CreateTaskIntentTests.swift`
- **Hypotheses tested:** Confirmed the issue was not in `TaskService` or `TransitTask` persistence;
  the bug occurs before task creation when the JSON metadata dictionary is cast to the wrong type.

## Discovered Root Cause

`JSONSerialization` parses JSON objects as `[String: Any]`, but `CreateTaskIntent` tries to read
`json["metadata"] as? [String: String]`. Even when every metadata value is a string, that cast
fails because the underlying dictionary value type is `Any`, so metadata is discarded before the
task is created.

**Defect type:** Logic error

**Why it occurred:** The intent code assumed Foundation would preserve the concrete dictionary value
type from the JSON payload, but `JSONSerialization` always uses `Any` for nested objects.

**Contributing factors:** Existing tests only asserted successful task creation and did not verify
that metadata survived the Create Task intent path.

## Resolution for the Issue

**Changes made:**
- _Pending implementation_

**Approach rationale:** _Pending implementation_

**Alternatives considered:**
- Reuse MCP-style metadata parsing so App Intent JSON follows the same tolerant input path.

## Regression Test

**Test file:** `Transit/TransitTests/CreateTaskIntentTests.swift`
**Test name:** `mixedTypeMetadataPreservesStringValues`

**What it verifies:** A task created through `CreateTaskIntent` preserves string entries from the
JSON `metadata` object even when the payload also contains non-string values.

**Run command:** `xcodebuild test -project Transit/Transit.xcodeproj -scheme Transit -destination 'platform=macOS' -configuration Debug -derivedDataPath ./DerivedData -only-testing:TransitTests/CreateTaskIntentTests`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Intents/CreateTaskIntent.swift` | Parse JSON metadata dictionary before task creation |
| `Transit/Transit/Intents/IntentHelpers.swift` | Add reusable helper for extracting string metadata |
| `Transit/TransitTests/CreateTaskIntentTests.swift` | Add regression coverage for metadata persistence |

## Verification

**Automated:**
- [ ] Regression test passes
- [ ] Full test suite passes
- [ ] Linters/validators pass

**Manual verification:**
- Not yet performed

## Prevention

**Recommendations to avoid similar bugs:**
- Add shared helpers for JSON-to-model conversions instead of repeating ad hoc casts.
- Assert persisted side effects for intent tests, not just top-level success payloads.
- Reuse metadata parsing helpers across App Intents and MCP entry points.

## Related

- Transit ticket `T-420`
