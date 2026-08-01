# Milestones

## Status Timestamps And Reports

- Milestone status changes are idempotent across all three update paths (T-923).
- `MilestoneService.updateStatus` returns early when `newStatus.rawValue == milestone.statusRawValue` so `lastStatusChangeDate` and `completionDate` are only rewritten on a real transition.
- The App Intent path in `Transit/Transit/Intents/UpdateMilestoneIntent.swift` (`applyUpdate`) and the MCP path in `Transit/Transit/MCP/MCPToolHandler.swift` (`applyMilestoneUpdate`) apply the same guard inline because they bypass `MilestoneService.updateStatus` to apply multi-field updates atomically. Keep these three sites in sync.
- `Transit/Transit/Reports/ReportLogic.swift` uses `completionDate ?? lastStatusChangeDate` as the milestone's effective completion date, so the no-op guard is what prevents an old done or abandoned milestone from re-entering the current report window on retries.
- Mirrors the task-side pattern: `TaskService.updateStatus` already short-circuits when `task.status == newStatus`. No equivalent `MilestoneStatusEngine` exists yet — extract one if the milestone status logic grows beyond the single guard.

## Cross-Device Name Conflicts

- CloudKit milestone records are UUID-keyed, so service-layer creation checks cannot strictly prevent two disconnected devices from creating the same normalized name in one project (T-1938).
- `MilestoneService.findByName` is throwing and must never be changed back to `.first`; `.ambiguousName` maps to `AMBIGUOUS_MILESTONE` for App Intents and an explicit MCP tool error.
- `MilestoneNameReconciler` keeps the oldest record's name (UUID tie-break) and gives other records deterministic full-UUID suffixes. It preserves records and task assignments and is idempotent across devices.
- Reconciliation runs through launch/foreground/connectivity promotion hooks and `ScenePhaseModifier` also observes milestone name changes so CloudKit imports that finish later trigger a true post-sync pass. It defers while the shared context has unsaved changes so it cannot commit an unrelated edit.
