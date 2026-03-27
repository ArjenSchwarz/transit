# Bugfix Report: MCP Comment Newline Unescape Corrupts Literal Text

**Date:** 2026-03-27
**Status:** Fixed

## Description of the Issue

The `MCPToolHandler.unescapeNewlines` helper performs a global `replacingOccurrences(of: "\\n", with: "\n")` on comment content received through the `add_comment` and `update_task_status` MCP tools. This converts every literal backslash-n sequence into a real newline character, corrupting user content that intentionally contains backslash-n — such as Windows paths, code examples, or regex patterns.

**Reproduction steps:**
1. Call `add_comment` via MCP with `content: "Path: C:\\new\\notes"` (JSON: `"Path: C:\\\\new\\\\notes"`)
2. The stored comment becomes `Path: C:` + newline + `ew` + newline + `otes`
3. Expected: the literal text `Path: C:\new\notes` is preserved

**Impact:** Any MCP comment containing a backslash followed by the letter `n` has that sequence silently converted to a newline, corrupting the stored content.

## Investigation Summary

- **Symptoms examined:** Literal `\n` sequences in MCP comment content are replaced with real newlines
- **Code inspected:** `MCPToolHandler.swift` — `unescapeNewlines` helper (line 711-713) and its two call sites: `handleAddComment` (line 684) and `handleUpdateStatus` (line 232)
- **Hypotheses tested:** Whether the JSON-RPC transport introduces literal `\n` that needs compensating — it does not. JSON `\n` decodes to a real newline; JSON `\\n` decodes to literal backslash-n, which the user intended to keep.

## Discovered Root Cause

**Defect type:** Incorrect input transformation

**Why it occurred:** T-561 introduced `unescapeNewlines` to handle MCP callers that appeared to send double-escaped newlines. The assumption was that literal `\n` in the decoded string always meant "the caller intended a newline." In reality, JSON-RPC already handles newline encoding correctly: `\n` in JSON becomes a real newline after decoding. The only way a literal backslash-n arrives in the decoded string is if the caller sent `\\n` in JSON — meaning they intended the literal characters.

**Contributing factors:** The original spec acknowledged the risk of false positives (e.g., Windows paths) but dismissed it as an unlikely edge case. The spec was also based on the incorrect assumption that MCP callers send double-escaped newlines as a transport artifact, when in fact it was likely a specific caller bug that has since been fixed.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/MCP/MCPToolHandler.swift` — Removed the `unescapeNewlines` helper method and its two call sites. Comment content now passes through to the service layer unmodified.

**Approach rationale:** The JSON-RPC transport correctly handles newline encoding/decoding. Removing the unescape step restores correct behavior: real newlines from JSON `\n` are preserved as-is, and literal backslash-n from JSON `\\n` is preserved as-is.

**Alternatives considered:**
- Smarter regex with negative lookbehind (`(?<!\\)\\n`) — Still wrong; there's no reliable way to distinguish "transport artifact" from "intended content" because the transport already handles encoding correctly.
- Opt-in flag on the MCP tool — Adds API complexity for a problem that doesn't exist at the transport level.

## Regression Test

**Test file:** `Transit/TransitTests/MCPCommentTests.swift`
**Test names:** `addCommentPreservesLiteralBackslashN`, `updateStatusCommentPreservesLiteralBackslashN`

**What it verifies:** That literal backslash-n sequences in MCP comment content are stored as-is, not converted to newlines.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/MCP/MCPToolHandler.swift` | Removed `unescapeNewlines` helper and its call sites |
| `Transit/TransitTests/MCPCommentTests.swift` | Replaced T-561 unescape tests with T-576 preservation tests |
| `Transit/Transit/TransitApp.swift` | Fixed pre-existing `Sendable` build error (unrelated to bug) |

## Verification

**Automated:**
- [x] Regression test passes
- [x] Full test suite passes
- [x] Linters/validators pass

**Manual verification:**
- Confirmed that the `unescapeNewlines` function is the sole source of the corruption
- Confirmed that JSON-RPC transport handles newline encoding correctly without manual intervention

## Prevention

**Recommendations to avoid similar bugs:**
- Do not add compensating transformations at application boundaries without confirming the transport layer actually has the deficiency
- When transforming user content, always consider whether the transformation could corrupt legitimate data
- Test with content that contains the characters being transformed (not just the "happy path" of the transformation)

## Related

- T-561: Original ticket that introduced `unescapeNewlines`
- `specs/parse-comment-newlines/smolspec.md`: Original spec that acknowledged but dismissed the corruption risk
