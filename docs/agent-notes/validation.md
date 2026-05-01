# Input Validation

## UUID Fields

When validating JSON or MCP UUID fields, check key presence separately from
type conversion and `UUID(uuidString:)` parsing. A malformed or non-string UUID
must return an input validation error for that field instead of being treated as
absent.

Use `IntentHelpers.validateUUIDField(_:in:)` for App Intent JSON dictionaries
when possible. For MCP argument dictionaries, keep the same behavior: if a key
such as `projectId`, `taskId`, or `milestoneId` exists but is not a valid UUID
string, reject it before any fallback lookup by name or display ID.

Known gaps filed by the code-issue automation:
- T-789: `DeleteMilestoneIntent` treats malformed `milestoneId` as missing.
- T-808: task identifier resolution can ignore malformed `displayId` / `taskId`
  values before falling back to another identifier or a generic not-found error.
- T-809: MCP enum filters ignore non-string `status`, `not_status`, and `type`
  values instead of rejecting malformed filter shapes.
- T-810: MCP milestone resolution treats non-string `milestoneId` values as
  missing for `update_milestone` and `delete_milestone`.
- T-813: `make lint` can fail after 0 SwiftLint violations because SwiftLint
  writes its default cache plist outside the workspace and may hit filesystem
  permission errors. Use a workspace-local SwiftLint cache path when fixing this.
- T-830: milestone status fields in App Intent and MCP milestone paths can ignore
  non-string `status` values instead of rejecting malformed input.
- T-898: `QueryMilestonesIntent` and MCP `query_milestones` short-circuit on
  `displayId` lookup and skip the remaining filters plus their validation.
  `displayId` queries should still apply `project` / `projectId` / `status` /
  `search` conjunctively, matching the task query paths.
