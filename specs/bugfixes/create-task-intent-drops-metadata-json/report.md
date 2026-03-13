# Bugfix Report: Create Task Intent Drops Metadata JSON

**Date:** 2026-03-13
**Status:** Fixed

## Description of the Issue

`CreateTaskIntent` could silently drop JSON metadata provided by App Intent callers. The intent
relied on a direct cast from `Any` to `[String: String]`, which is brittle for nested JSON objects
and causes the entire metadata payload to be discarded when non-string values are present.

**Reproduction steps:**
1. Call `CreateTaskIntent.execute` with valid JSON that includes a `metadata` object.
2. Parse the returned `taskId` and fetch the created task from `TaskService`.
3. Observe that string entries are missing from the saved task when the metadata object also
   contains non-string values.

**Impact:** App Intent and Shortcut callers cannot attach metadata to created tasks, which breaks
automation flows that rely on `git.*`, `agent.*`, or similar reserved metadata namespaces.

## Investigation Summary

Inspected the Create Task App Intent flow end to end and compared it with the MCP tool path that
already handles metadata correctly.

- **Symptoms examined:** Tasks created through `CreateTaskIntent` dropped string metadata when the
  JSON metadata object contained mixed value types.
- **Code inspected:** `Transit/Transit/Intents/CreateTaskIntent.swift`,
  `Transit/Transit/Intents/IntentHelpers.swift`, `Transit/Transit/MCP/MCPToolHandler.swift`,
  `Transit/TransitTests/CreateTaskIntentTests.swift`
- **Hypotheses tested:** Confirmed the issue was not in `TaskService` or `TransitTask` persistence;
  the bug occurs before task creation when the JSON metadata dictionary is cast to the wrong type.

## Discovered Root Cause

`JSONSerialization` parses nested JSON objects as `[String: Any]`, but `CreateTaskIntent` tried to
read `json["metadata"] as? [String: String]`. That cast depends on Foundation bridging and fails as
soon as the payload is not already an exact string dictionary, so the entire metadata payload could
be discarded before the task was created.

**Defect type:** Logic error

**Why it occurred:** The intent code assumed Foundation would preserve the concrete dictionary value
type from the JSON payload, but `JSONSerialization` always uses `Any` for nested objects.

**Contributing factors:** Existing tests only asserted successful task creation and did not verify
that metadata survived the Create Task intent path.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/Intents/IntentHelpers.swift` - added a shared helper that extracts string
  metadata entries from JSON-like dictionaries, ignores unsupported value types, and now documents
  the native `[String: String]` fast path for non-JSON callers.
- `Transit/Transit/Intents/CreateTaskIntent.swift` - switched task creation to use the shared
  metadata helper instead of a brittle direct cast and clarified the input contract for metadata
  values in the intent description.
- `Transit/TransitTests/CreateTaskIntentTests.swift` - added a regression test covering mixed-type
  metadata payloads plus helper edge-case coverage for empty and all-non-string metadata objects.

**Approach rationale:** Parsing the metadata dictionary explicitly makes the App Intent path match
the task model's `[String: String]` contract without relying on Foundation's dynamic bridging
behavior. Ignoring non-string values keeps the fix surgical and preserves valid string metadata
instead of dropping the whole payload.

**Alternatives considered:**
- Reuse MCP-style metadata parsing so App Intent JSON follows the same tolerant input path.
- Stringify every non-string metadata value, which was rejected because task metadata is explicitly
  modeled as `[String: String]` and silent coercion would broaden the API unexpectedly.

## Regression Test

**Test file:** `Transit/TransitTests/CreateTaskIntentTests.swift`
**Test name:** `mixedTypeMetadataPreservesStringValues`

**What it verifies:** A task created through `CreateTaskIntent` preserves string entries from the
JSON `metadata` object even when the payload also contains non-string values.

**Run command:** `xcodebuild test -project Transit/Transit.xcodeproj -scheme Transit -destination 'platform=macOS' -configuration Debug -derivedDataPath ./DerivedData -only-testing:TransitTests/CreateTaskIntentTests`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Intents/CreateTaskIntent.swift` | Parse JSON metadata explicitly and document string-only metadata values |
| `Transit/Transit/Intents/IntentHelpers.swift` | Add reusable helper for extracting string metadata and document the native fast path |
| `Transit/TransitTests/CreateTaskIntentTests.swift` | Add regression and helper edge-case coverage for metadata parsing |

## Verification

**Automated:**
- [x] Regression test passes
- [ ] Full test suite passes *(blocked by pre-existing rollback/save-error failures in macOS and
  iOS suites, plus an unrelated `TransitUITests.testClearAll` failure on iOS)*
- [ ] Linters/validators pass *(blocked by a pre-existing `type_body_length` violation in
  `Transit/TransitTests/TaskEditSaveErrorTests.swift`)*

**Manual verification:**
- Verified the focused `CreateTaskIntentTests` suite before and after the change to confirm the new
  regression test failed before the fix and passed after it.

## Prevention

**Recommendations to avoid similar bugs:**
- Add shared helpers for JSON-to-model conversions instead of repeating ad hoc casts.
- Assert persisted side effects for intent tests, not just top-level success payloads.
- Reuse metadata parsing helpers across App Intents and MCP entry points.

## Related

- Transit ticket `T-420`
- Investigation checkpoint commit: `a811789`
