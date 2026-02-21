# PR Review Overview - Iteration 1

**PR**: #40 | **Branch**: T-58/mcp-status-filter | **Date**: 2026-02-21

## Valid Issues

### PR-Level Issues

#### Issue 1: JSON Schema declares `array` but runtime accepts `string`
- **Type**: discussion comment
- **Reviewer**: @claude
- **Comment**: "The `status` parameter now declares `type: \"array\"` in the tool schema, but the runtime still accepts a plain string via the backward-compat path in `from(args:)`. These two things are inconsistent."
- **Validation**: Confirmed. Schema at MCPToolDefinitions.swift:57 uses `.array(...)` while MCPHelperTypes.swift:18 accepts single string. Adding `anyOf` to the schema model is disproportionate work. A code comment documenting the intentional defensive string path is the right fix.

#### Issue 2: `not_status` silently ignores a single string
- **Type**: discussion comment
- **Reviewer**: @claude
- **Comment**: "`not_status` has no equivalent [single-string compat] — `args[\"not_status\"] as? [String]` returns `nil` for a string value and the exclusion filter is silently skipped."
- **Validation**: Confirmed. MCPHelperTypes.swift:24 only handles `[String]`. A caller sending `"not_status": "done"` gets silent no-op. Should add the same single-string fallback as `status`.

#### Issue 3: Non-deterministic ordering in `resolvedNotStatuses`
- **Type**: discussion comment
- **Reviewer**: @claude
- **Comment**: "`Set` iteration order is non-deterministic. [...] A deterministic alternative that still deduplicates: `let extra = notStatusesArg?.filter { !terminal.contains($0) } ?? []; resolvedNotStatuses = terminal + extra`"
- **Validation**: Confirmed. MCPHelperTypes.swift:29 uses `Array(Set(...).union(...))`. While it doesn't affect correctness, a deterministic alternative is cleaner and prevents surprises in logs or future serialization.

#### Issue 4: Asymmetric `from(args:type:projectId:)` signature
- **Type**: discussion comment (nitpick)
- **Reviewer**: @claude
- **Comment**: "The factory extracts `status`, `not_status`, and `unfinished` from `args`, but receives `type` and `projectId` as pre-parsed values. [...] A comment noting the delegation boundary would help."
- **Validation**: Confirmed. The split exists because type/projectId parsing involves complex logic (UUID validation, project name lookup with error handling) in `handleQueryTasks`. A comment explaining this is sufficient.

#### Issue 5: Test gap — empty array with non-empty counterpart
- **Type**: discussion comment (nitpick)
- **Reviewer**: @claude
- **Comment**: "It would also be worth testing the case where one is empty and the other has values (e.g., `status: []` with a non-empty `not_status`) to confirm each is independently treated as absent."
- **Validation**: Confirmed. Current `emptyStatusArrayTreatedAsAbsent` test passes both arrays empty. Should add a case with one empty and one with values.

## Invalid/Skipped Issues

None — all issues validated as actionable.
