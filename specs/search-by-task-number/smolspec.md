# Search by Task Number

## Overview

Extend the dashboard search filter to match against task display IDs (e.g., "T-334" or "334") in addition to name and description. This lets users find a specific task when they know its number, without scrolling through the board.

## Requirements

- The dashboard search MUST match against the task's formatted display ID (e.g., "T-42") using the same case-insensitive substring matching as name/description
- The search MUST also match against the bare numeric portion (e.g., searching "42" matches T-42)
- The existing name and description matching MUST remain unchanged
- The search MUST continue to combine with project, type, and milestone filters (conjunctive AND)

**Accepted trade-off:** Substring matching means searching "4" will match T-4, T-14, T-40, T-41, etc. This is consistent with how name/description search works and acceptable given the small dataset size. Exact-number matching is not required.

## Implementation Approach

**Single change in the filter predicate:**

| File | Change |
|------|--------|
| `Transit/Views/Dashboard/DashboardView.swift` (lines 250-253) | Add a `displayIdMatch` check alongside `nameMatch` and `descMatch` in `matchesFilters()`. Match against `task.displayID.formatted` using the same `localizedCaseInsensitiveContains`. |
| `Transit/TransitTests/DashboardSearchTests.swift` | Add tests for: searching by full display ID ("T-42"), searching by number only ("42"), display ID search combining with other filters. |

**Pattern to follow:** The existing `nameMatch` / `descMatch` pattern at `DashboardView.swift:251-253`. Add one more `let displayIdMatch = ...` line and include it in the `guard` OR chain.

**Matching approach:** Use `task.displayID.formatted` which returns `"T-42"` for permanent IDs and `"T-•"` for provisional. Matching with `localizedCaseInsensitiveContains` means:
- "T-42" matches (full formatted ID)
- "42" matches (substring of "T-42")
- "t-42" matches (case-insensitive)

No special parsing of the search text is needed — substring matching handles all cases naturally.

**Test setup:** The existing `makeTask` helper creates tasks with `.provisional` display ID. Tests for display ID search need permanent IDs, so they'll set `task.permanentDisplayId` directly after creation (it's a stored `Int?` property on the model).

**Dependencies:** None beyond what's already used.

**Out of scope:**
- MCP/App Intent display ID search (already supported via separate `displayId` parameter)
- Highlighting matched text in task cards
- Search suggestions or autocomplete for task numbers

## Risks and Assumptions

- **Assumption:** `DisplayID.formatted` is cheap to call per task per keystroke. It's a simple string interpolation with no allocation beyond the string itself. For the expected task count (hundreds at most), this is negligible.
- **Assumption:** Matching the provisional formatted string `"T-•"` against user search text is acceptable — a user typing "T-" would match provisional tasks, which is reasonable since they'd also match any permanent ID starting with "T-".
- **Accepted trade-off:** Numeric substring matching produces broad results (searching "4" matches T-4, T-14, T-40-49, etc.). This is consistent with how name/description search already works and is acceptable for a single-user app with hundreds of tasks at most.
