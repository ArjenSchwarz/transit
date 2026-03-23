# Parse Comment Newlines

## Overview

When comments are submitted via MCP tools (`add_comment`, `update_task_status` with comment), literal `\n` sequences in the content appear as-is instead of rendering as actual newlines. The root cause is client-side: MCP callers (agents) send strings with literal backslash-n characters rather than actual newlines. The JSON-RPC transport correctly handles encoding/decoding, but the input string already contains the literal escape. This fix adds a compensating unescape step at the MCP input boundary before passing content to the service layer.

## Requirements

- The system MUST replace literal `\n` sequences in MCP comment content with actual newline characters before storage
- The system MUST apply the same unescaping to comments submitted via `update_task_status`
- The system MUST preserve newlines already present as actual newline characters (no double-conversion)
- The system SHOULD keep the unescaping logic in the MCP layer, not in `CommentService`

## Implementation Approach

**Key file to modify:**
- `Transit/Transit/MCP/MCPToolHandler.swift` — add a private helper to unescape `\n` in strings, call it on comment content in `handleAddComment` (line 671) and on the comment parameter in `handleUpdateStatus` (line 232)

**Pattern:** A private method on `MCPToolHandler`:
```swift
private func unescapeNewlines(_ text: String) -> String {
    text.replacingOccurrences(of: "\\n", with: "\n")
}
```

Apply before passing to service calls:
- `handleAddComment`: unescape `content` before passing to `commentService.addComment()`
- `handleUpdateStatus`: unescape `commentText` before passing to `taskService.updateStatus()`

**Response behavior:** After unescaping, stored content contains real newlines. The JSON response (line 701) will correctly re-encode these as `\n` in JSON output. Callers that previously matched on literal `\n` in response content will see different output — this is the intended fix.

**Dependencies:** None — uses only Foundation `String.replacingOccurrences`.

**Out of Scope:**
- Unescaping other escape sequences (`\t`, `\\`, etc.)
- Changes to `CommentService` or the UI layer
- Markdown or rich text processing in comments
- The `create_task` description field (same issue may apply but is a separate concern)

## Risks and Assumptions

- **Assumption:** The literal `\n` originates from MCP callers sending escaped text. This fix normalizes input regardless of exact client behavior.
- **Risk:** Comments intentionally containing a literal backslash followed by `n` (e.g. `path\name`) would be converted to a newline. | **Mitigation:** This is an edge case for task tracker comments. The benefit of readable multi-line agent comments outweighs this risk. A more precise regex (`(?<!\\)\\n`) could avoid this but adds complexity not justified by the use case.
