# Bugfix Report: Generate Report Intent Fetch Failures

**Date:** 2026-08-04
**Status:** Investigating

## Description of the Issue

`GenerateReportIntent` caught a terminal-task or terminal-milestone storage fetch failure, logged it, and formatted empty report data as though no records matched the requested date range.

**Reproduction steps:**
1. Run report generation with a terminal-task fetcher that throws.
2. Run report generation with a terminal-milestone fetcher that throws after a successful task fetch.
3. Observe normal empty-state Markdown rather than the automation error envelope.

**Impact:** Shortcuts and CLI callers cannot distinguish retryable SwiftData/storage failures from a legitimate empty report, so they can treat an incomplete result as successful automation output.

## Investigation Summary

- **Symptoms examined:** A broad source search found the catch block in `Transit/Transit/Intents/GenerateReportIntent.swift` constructing empty `ReportData` for either fetch failure.
- **Code inspected:** `GenerateReportIntent`, `TaskService.fetchTerminalTasks`, `MilestoneService.fetchTerminalMilestones`, `IntentError`, existing query-fetch-failure regressions, report logic, formatter, and date-range helpers.
- **Hypotheses tested:** Focused tests with deterministic terminal-fetch seams prove task and milestone failures return empty Markdown under the original behavior, while successful empty fetches retain their expected Markdown.

## Discovered Root Cause

The intent used one combined `do`/`catch` for both terminal fetches. Its catch branch mapped every error to a valid empty `ReportData` instance, conflating an unavailable store with a successful empty result.

**Defect type:** Error-handling logic error.

**Why it occurred:**
1. Fetch errors were caught to prevent the App Intent from throwing.
2. The fallback was implemented as an empty report rather than the established JSON error envelope.
3. The public result type is `String`, so both conditions became indistinguishable successful-looking Markdown.
4. No deterministic failing fetch seam existed to pin the distinction in tests.

**Contributing factors:** The UI report uses `@Query`, whereas this background App Intent fetches directly through services; it therefore needs its own storage-failure contract tests.

## Resolution for the Issue

Pending implementation after the red regression checkpoint.

**Planned approach:** Add narrow terminal-fetch protocols for deterministic tests; map task and milestone failures independently to stable `INTERNAL_ERROR` JSON responses; preserve the normal successful report pipeline and date-range formatting.

## Regression Test

**Test file:** `Transit/TransitTests/GenerateReportIntentTests.swift`
**Test names:** `taskFetchFailureReturnsInternalError`, `milestoneFetchFailureReturnsInternalError`, `validEmptyReportPreservesMarkdownAndDateRange`

**What it verifies:** Task and milestone fetch failures must emit their exact structured error envelopes, while successful empty sources still return the exact formatter output for the supplied date range.

**Red command:** `xcodebuild test -project Transit/Transit.xcodeproj -scheme Transit -destination 'platform=macOS' -configuration Debug -derivedDataPath ./DerivedData -only-testing:TransitTests/GenerateReportIntentTests`

**Red result:** The two failure regressions failed; matching-task output, valid-empty output, and all date-range coverage passed.

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Intents/GenerateReportIntent.swift` | Adds injectable fetch/time seams before behavioral correction. |
| `Transit/Transit/Intents/Shared/TerminalReportFetching.swift` | Adds narrow terminal task/milestone fetch protocols. |
| `Transit/TransitTests/GenerateReportIntentTests.swift` | Adds isolated failure and valid-empty regressions. |

## Verification

**Automated:**
- [x] Focused regression suite is red before the fix.
- [ ] Focused regression suite passes after the fix.
- [ ] Full macOS unit suite passes.
- [ ] Linter passes.

## Prevention

Read-only automation intents must map storage failures to the project’s structured error contract rather than synthesizing domain-success output. Keep independently injectable task and milestone sources so this boundary remains deterministic.

## Related

- Transit T-1620
- Existing query fetch-failure handling (T-1566)
