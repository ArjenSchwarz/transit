# Display ID Maintenance

## Overview

- `Transit/Transit/Services/DisplayIDMaintenanceService.swift` scans all tasks and milestones, groups duplicate `permanentDisplayId` values client-side, and picks the winner by oldest `creationDate` with UUID-string tiebreak.
- `reassignDuplicates()` advances each counter to at least `max(existingID) + 1` before rewriting losers, so future allocations should stay above the current fence.
- Reassigned tasks get an agent-authored audit comment through `CommentService`; milestones do not have comment support.
- The feature is exposed through Settings (`DataMaintenanceView`), two App Intents, and two gated MCP tools.

## Current gotchas

- The stale-ID guard is intended to protect against peer devices changing a loser between scan and write, but the current implementation re-fetches by ID without calling `modelContext.refresh(_:mergeChanges:)` first. See Transit bug `T-1061`.
- The result screen combines task and milestone groups into one `ForEach`, but currently keys rows by `displayId` alone. Matching task and milestone IDs (for example `T-5` and `M-5`) can collide in SwiftUI diffing. See Transit bug `T-1062`.
- Existing tests mostly cover task-only duplicate scenarios. The UI test seed in `Transit/Transit/UITestScenario.swift` does not currently exercise mixed task+milestone duplicate IDs.
