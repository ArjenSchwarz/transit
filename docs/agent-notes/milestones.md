# Milestones

## Status Timestamps And Reports

- Milestone status changes are not currently idempotent across all paths.
- `MilestoneService.updateStatus` always rewrites `lastStatusChangeDate` and, for terminal statuses, `completionDate`, even when the new status matches the current one.
- The App Intent path in `Transit/Transit/Intents/UpdateMilestoneIntent.swift` and the MCP path in `Transit/Transit/MCP/MCPToolHandler.swift` duplicate that same logic instead of guarding on an actual status transition.
- `Transit/Transit/Reports/ReportLogic.swift` uses `completionDate ?? lastStatusChangeDate` as the milestone's effective completion date, so a same-status retry can make an old done or abandoned milestone appear newly completed in reports.
- Filed as T-923 so future work on milestone updates or report correctness should check for a no-op status guard first.
