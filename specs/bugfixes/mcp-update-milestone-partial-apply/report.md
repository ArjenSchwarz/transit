# Bugfix Report: MCP update_milestone partial apply on failure

**Date:** 2026-03-09
**Status:** Fixed

## Description of the Issue

The MCP `update_milestone` tool handler applied status changes via `milestoneService.updateStatus()` before processing name/description updates via `milestoneService.updateMilestone()`. Each service method saves independently. If the name update failed (e.g., duplicate name), the status change was already persisted, but the tool returned an error — leaving the milestone in an inconsistent state.

**Reproduction steps:**
1. Create two milestones in the same project: "Existing" and "v1.0"
2. Call `update_milestone` with displayId for "v1.0", status: "done", name: "Existing"
3. The tool returns an error (duplicate name), but the status is already changed to "done"

**Impact:** Data integrity issue. MCP clients receive an error response but the milestone is partially modified. The caller has no way to know which parts succeeded.

## Investigation Summary

- **Symptoms examined:** `handleUpdateMilestone` in `MCPToolHandler.swift` calls two separate service methods sequentially, each with its own `save()`.
- **Code inspected:** `MCPToolHandler.handleUpdateMilestone`, `MilestoneService.updateStatus`, `MilestoneService.updateMilestone`
- **Hypotheses tested:** Confirmed that `updateStatus` saves immediately (line 121 of MilestoneService.swift), so by the time `updateMilestone` is called and fails, the status is already persisted.

## Discovered Root Cause

**Defect type:** Non-atomic multi-step mutation

**Why it occurred:** The handler delegated to two separate service methods that each call `modelContext.save()` independently. The handler had no transaction boundary around the combined operation.

**Contributing factors:** The service methods were designed for independent use (single-field updates), but the handler combined them without ensuring atomicity.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/MCP/MCPToolHandler.swift` — Rewrote `handleUpdateMilestone` to use a validate-then-apply pattern:
  1. All inputs (status, name) are validated upfront before any mutations
  2. Changes are applied to the model in memory only after validation passes
  3. A single `save()` call persists all changes atomically
  4. On save failure, `rollback()` reverts all in-memory changes

**Approach rationale:** Validate-then-apply is simpler and safer than trying to roll back individual service calls. It avoids calling service methods that have their own save semantics.

**Alternatives considered:**
- Adding a `MilestoneService.update(status:name:description:)` combined method — rejected because it would add API surface for a single caller's needs
- Wrapping in a SwiftData transaction — SwiftData doesn't expose explicit transaction boundaries, so validate-then-save is the idiomatic approach

## Regression Test

**Test file:** `Transit/TransitTests/MCPMilestoneToolTests.swift`
**Test name:** `updateMilestoneStatusAndDuplicateNameIsAtomic`

**What it verifies:** When `update_milestone` is called with both a status change and a duplicate name, the tool returns an error and the milestone's status, name, and completionDate remain unchanged.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/MCP/MCPToolHandler.swift` | Rewrote `handleUpdateMilestone` with validate-then-apply pattern |
| `Transit/TransitTests/MCPMilestoneToolTests.swift` | Added atomicity regression test |
| `Transit/TransitTests/DashboardShortcutTests.swift` | Fixed pre-existing build error (nil for non-optional String) |

## Verification

**Automated:**
- [x] Regression test passes
- [x] Full MCP test suite passes (19/19)
- [x] Linters pass (0 violations)

## Prevention

**Recommendations to avoid similar bugs:**
- When an MCP handler needs to update multiple fields, validate all inputs before mutating any model state
- Avoid calling multiple service methods that each save independently when the operations should be atomic
- Consider adding integration tests that combine multiple field updates in a single call

## Related

- T-391: MCP update_milestone can partially apply changes on failure
