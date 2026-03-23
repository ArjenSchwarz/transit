# Implementation Explanation: Parse Comment Newlines (T-561)

## Beginner Level

### What Changed
When AI agents add comments to Transit tasks through the MCP (Model Context Protocol) interface, they sometimes send the text `\n` as two literal characters — a backslash followed by the letter "n" — instead of an actual line break. This meant multi-line comments looked like `"Line one\nLine two"` in the UI instead of:

```
Line one
Line two
```

This fix detects those literal `\n` sequences and converts them into real newlines before the comment is saved.

### Why It Matters
Transit is designed to work with AI agents. Agents frequently write multi-paragraph comments (status updates, analysis, reasoning). Without this fix, those comments are hard to read because all the line breaks appear as raw `\n` text.

### Key Concepts
- **MCP (Model Context Protocol)**: A JSON-RPC protocol that lets external tools (like AI agents) interact with Transit — creating tasks, updating statuses, adding comments.
- **Literal vs actual newlines**: In code, `\n` means "new line." But when text travels through certain transports, the `\n` can arrive as two visible characters instead of a line break. This fix compensates for that.
- **Input boundary**: The point where external data enters the system. Fixing data at this boundary keeps the rest of the codebase clean.

---

## Intermediate Level

### Changes Overview
A single file was modified: `MCPToolHandler.swift`. A private helper `unescapeNewlines(_:)` was added and called at two entry points:

1. **`handleAddComment`** (dedicated comment endpoint) — unescapes `content` before passing to `CommentService.addComment()`
2. **`handleUpdateStatus`** (status change with optional comment) — unescapes the optional `comment` argument via `.map { unescapeNewlines($0) }`

### Implementation Approach
The fix uses `String.replacingOccurrences(of: "\\n", with: "\n")` — a straightforward Foundation method. It lives as a private method on `MCPToolHandler`, keeping it at the MCP input boundary rather than pushing it into the service layer.

The two call sites handle optionality differently: `handleUpdateStatus` uses `.map` on an optional string, while `handleAddComment` operates on a non-optional (already validated by a guard). Both patterns are correct for their respective contexts.

### Trade-offs
- **Simplicity over precision**: A naive replacement converts *all* `\n` sequences, including hypothetical intentional ones like `path\name`. A negative lookbehind regex could avoid this, but the added complexity isn't justified — task tracker comments rarely contain literal backslash-n.
- **MCP layer only**: The spec explicitly keeps this in `MCPToolHandler` rather than `CommentService`. App Intents and direct service calls don't need unescaping because they receive properly encoded strings.
- **Scope limited to `\n`**: Other escape sequences (`\t`, `\\`) are not handled. This is a targeted fix for the observed problem, not a general-purpose unescaper.

---

## Expert Level

### Technical Deep Dive
The root cause is client-side: MCP callers (typically LLM agents) construct JSON strings where newlines are double-escaped. The JSON-RPC transport correctly decodes the JSON, but the resulting Swift string contains literal backslash-n characters (`\\n` in source, `\n` in the string value) rather than newline characters (`\n` / U+000A).

`String.replacingOccurrences(of:with:)` is O(n) on string length — negligible for comment-sized text. The method is called once per MCP request at most, so there's no performance concern.

The `handleUpdateStatus` path uses optional chaining (`.map`) which correctly short-circuits to `nil` when no comment is provided, avoiding an unnecessary allocation.

### Architecture Impact
- **No service layer changes**: The fix is contained within the MCP boundary. `CommentService`, the UI, and App Intents are unaffected.
- **Response encoding**: Stored comments now contain real newlines. When serialized back to JSON in the MCP response, `JSONSerialization` re-encodes these as `\n` in the JSON string — which is correct JSON behavior. Callers that previously pattern-matched on literal `\n` in response text will see different output; this is the intended fix.
- **Precedent for `create_task` description**: The same issue likely affects task descriptions submitted via MCP. The smolspec explicitly marks this as out of scope — a separate ticket if needed.

### Potential Issues
- **False positives**: A comment containing an intentional backslash-n (e.g., a Windows path `C:\new`) would have the `\n` portion converted to a newline. This is documented as an acceptable trade-off given the task tracker domain.
- **No round-trip guarantee**: If a caller reads a comment via `query_tasks`, the JSON response contains real newlines encoded as `\n`. If the caller then submits that text back as a new comment, the `\n` would be unescaped again — but since it's already a real newline in the JSON, the transport decodes it to a real newline, and `replacingOccurrences` finds no literal `\n` to replace. Round-tripping is safe.
- **`\r\n` (CRLF)**: Not handled, but unlikely from agent callers. If needed, a separate normalisation step could be added.

---

## Completeness Assessment

### Fully Implemented
- Literal `\n` unescaping in `add_comment` content
- Literal `\n` unescaping in `update_task_status` comment
- Preservation of existing real newlines (no double-conversion)
- Unescaping logic confined to MCP layer
- Test coverage for both code paths and preservation behavior

### Not Applicable / Out of Scope
- `create_task` description field (separate concern per spec)
- Other escape sequences (`\t`, `\\`)
- Service layer or UI changes
