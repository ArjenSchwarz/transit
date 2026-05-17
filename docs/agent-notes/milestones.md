# Milestones

## Status Timestamps And Reports

- Milestone status changes are idempotent across all three update paths (T-923).
- `MilestoneService.updateStatus` returns early when `newStatus.rawValue == milestone.statusRawValue` so `lastStatusChangeDate` and `completionDate` are only rewritten on a real transition.
- The App Intent path in `Transit/Transit/Intents/UpdateMilestoneIntent.swift` (`applyUpdate`) and the MCP path in `Transit/Transit/MCP/MCPToolHandler.swift` (`applyMilestoneUpdate`) apply the same guard inline because they bypass `MilestoneService.updateStatus` to apply multi-field updates atomically. Keep these three sites in sync.
- `Transit/Transit/Reports/ReportLogic.swift` uses `completionDate ?? lastStatusChangeDate` as the milestone's effective completion date, so the no-op guard is what prevents an old done or abandoned milestone from re-entering the current report window on retries.
- Mirrors the task-side pattern: `TaskService.updateStatus` already short-circuits when `task.status == newStatus`. No equivalent `MilestoneStatusEngine` exists yet — extract one if the milestone status logic grows beyond the single guard.
