# Bugfix Report: Milestone Filter Project Name

**Date:** 2026-02-23
**Status:** Fixed

## Description of the Issue

The milestone filter in the dashboard popover displayed only the milestone name (e.g., "Beta 1") without indicating which project it belonged to. When milestones from multiple projects were visible, users couldn't distinguish between identically named milestones.

**Reproduction steps:**
1. Create milestones in two or more projects
2. Open the dashboard filter popover
3. Observe milestone names lack project context

**Impact:** Low severity — milestones were functional but ambiguous in multi-project contexts.

## Investigation Summary

- **Symptoms examined:** Milestone filter section in FilterPopoverView showed bare milestone names
- **Code inspected:** `FilterPopoverView.swift`, `Milestone.swift` model, MCP serialisation code
- **Hypotheses tested:** The MCP layer already includes `projectName` in JSON output, so the model relationship is correct — only the view layer was missing the prefix

## Discovered Root Cause

`FilterPopoverView` line 155 used `Text(milestone.name)` directly, without incorporating the project name from the `milestone.project` relationship.

**Defect type:** Missing display context

**Why it occurred:** The milestone filter was implemented with just the milestone name, likely because early versions only had milestones within a single-project context.

**Contributing factors:** The `availableMilestones` computed property can span multiple projects when no project filter is active.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/Models/Milestone.swift` — Added `displayName` computed property that returns `"Project - Milestone"` format
- `Transit/Transit/Views/Dashboard/FilterPopoverView.swift:155` — Changed `Text(milestone.name)` to `Text(milestone.displayName)`

**Approach rationale:** A computed property on the model is testable and reusable wherever milestone names need project context.

**Alternatives considered:**
- Inline string formatting in the view — less testable and would need duplication if used elsewhere

## Regression Test

**Test file:** `Transit/TransitTests/MilestoneDisplayNameTests.swift`
**Test names:** `displayNameWithProject`, `displayNameWithoutProject`

**What it verifies:** `displayName` returns `"Project - Name"` when a project exists and falls back to just the name when the project is nil.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Models/Milestone.swift` | Added `displayName` computed property |
| `Transit/Transit/Views/Dashboard/FilterPopoverView.swift` | Use `displayName` instead of `name` |
| `Transit/TransitTests/MilestoneDisplayNameTests.swift` | New regression test suite |

## Verification

**Automated:**
- [x] Regression test passes
- [x] Full test suite passes
- [x] Linters/validators pass

## Prevention

**Recommendations to avoid similar bugs:**
- When displaying entity names in multi-context views (filters, pickers spanning multiple parents), include the parent name for disambiguation

## Related

- Transit ticket T-223
