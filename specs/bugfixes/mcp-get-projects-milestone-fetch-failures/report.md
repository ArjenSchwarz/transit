# Bugfix Report: MCP Get Projects Hides Milestone Fetch Failures

**Date:** 2026-08-05
**Status:** Fixed

## Description of the Issue

`get_projects` fetches projects successfully and then enriches each result with
that project's milestones. `MilestoneService.milestonesForProject` turns a
SwiftData fetch error into `[]`, so the MCP handler returns a successful,
partial project list. Clients cannot distinguish an unreadable milestone store
from a valid project with no milestones.

**Reproduction steps:**
1. Inject a `ModelFetching` implementation that returns a valid empty result
   for the first scoped milestone fetch and throws for the second.
2. Call MCP `get_projects` with two or more projects present.
3. Observe a non-error partial project array with missing `milestones` fields
   instead of a tool error.

**Impact:** MCP clients can treat incomplete project/milestone metadata as
authoritative and make incorrect routing or planning decisions.

## Investigation Summary

- **Symptoms examined:** a deterministic injected scoped-fetch failure produced
a successful `get_projects` response.
- **Code inspected:** `MilestoneService.milestonesForProject`,
  `MCPToolHandler.handleGetProjects`, the three SwiftUI picker/filter callers,
  `MCPGetProjectsTests`, and T-1675's merged `ModelFetching` design.
- **Hypotheses tested:** The regression test proved the failure occurs after a
  successful project fetch; valid empty milestone data and separate project
  scopes remain correct.

## Discovered Root Cause

`MilestoneService.milestonesForProject` uses
`(try? modelContext.fetch(descriptor)) ?? []`. This converts a storage failure
into the same value used for a legitimate empty result and bypasses its
injected `ModelFetching` seam, unlike T-1675's scoped name lookup.

**Defect type:** Error-handling/data-integrity defect.

**Why it occurred:** The original non-throwing picker helper was reused by the
MCP response-enrichment path without making the authoritative MCP consumer
handle a failed store read.

## Resolution for the Issue

**Changes made:**
- `MilestoneService.milestonesForProject` is now throwing and reads through its
  existing injected `ModelFetching` seam, preserving storage failures.
- `MCPToolHandler.handleGetProjects` builds results in a loop and returns the
  exact `Failed to fetch milestones: <error>` tool error before it can emit an
  authoritative partial project list.
- `TaskEditView.availableMilestones` explicitly retains its existing empty
  picker fallback because it is a presentation-only surface with no error UI.
- `MCPGetProjectsTests` adds deterministic failure and valid-empty/multi-project
  coverage; `MilestoneServiceLookupTests` adopts the throwing contract.

**Approach rationale:** This follows T-1675: the service layer distinguishes
"could not read" from "nothing matched", while the MCP adapter turns the exact
underlying error into the established tool error wording. An ordinary `for`
loop avoids allocating or returning an incomplete serialized project array.

**Alternatives considered:**
- Keep the non-throwing service API and add a second MCP-only fetch helper —
  rejected because the original API would still silently collapse storage
  errors and duplicate the scoped query logic.
- Return projects collected before the failure — rejected because clients could
  mistake a partial list for an authoritative response.

## Regression Test

**Test file:** `Transit/TransitTests/MCPGetProjectsTests.swift`
**Test name:** `getProjectsMilestoneFetchFailureReturnsExactToolErrorWithoutPartialProjects`

**What it verifies:** the first scoped milestone fetch succeeds with a valid
empty result and the second fails, proving the exact MCP tool error replaces
(rather than accompanies) a partial successful project list; a separate control
verifies an empty project's omitted `milestones` field and another project's
correctly scoped milestones.

**Run command:** `make test-quick`

Before the fix, the focused `MCPGetProjectsTests` suite fails only the injected
fetch-failure test; the valid-empty/multi-project control passes.

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Services/MilestoneService.swift` | Scoped milestone fetch now throws through injected `ModelFetching`. |
| `Transit/Transit/MCP/MCPToolHandler.swift` | Returns exact fetch error without a partial project response. |
| `Transit/Transit/Views/TaskDetail/TaskEditView+Milestones.swift` | Makes the picker-only empty fallback explicit. |
| `Transit/TransitTests/MCPGetProjectsTests.swift` | Adds deterministic fetch-failure and valid-empty/multi-project coverage. |
| `Transit/TransitTests/MilestoneServiceLookupTests.swift` | Adopts the throwing scoped-fetch contract. |
| `CHANGELOG.md` | Documents the corrected MCP storage-error behavior. |

## Verification

**Automated:**
- [x] Regression fails before the fix.
- [x] Regression passes after the fix (`make test-quick`).
- [x] `make test-quick` passes.
- [x] `make lint` passes.
- [x] `make build` passes for iOS Simulator and macOS.
- [ ] `make test` did not complete within the command runner limit; before
  timeout it reported UI failures in `testClearAll`, `testEditViewPreservesTaskMilestone`,
  and `testDataMaintenanceGoldenPath`, which were not investigated because they
  are outside this ticket's scoped MCP storage-error change.

**Manual verification:** Not needed; deterministic MCP handler tests exercise
the response envelope.

## Prevention

Service methods used by authoritative automation responses must preserve storage
errors. Presentation callers that intentionally degrade to an empty picker must
make that fallback explicit at their call site rather than receiving it from the
service API.

## Related

- T-1711
- T-1675 — scoped milestone-name lookup storage-error semantics
- T-1608 — unscoped MCP milestone fetch storage-error semantics
