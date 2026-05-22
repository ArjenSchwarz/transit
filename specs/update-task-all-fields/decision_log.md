# Decision Log: Extend update_task to Support All Task Fields

## Decision 1: Description Clearing via Empty / Whitespace-Only String

**Date**: 2026-05-22
**Status**: accepted

### Context

The `update_task` tool needs a way for a caller to clear a task's description. Three signaling options were considered: a JSON empty string (`""`), JSON `null`, and an explicit boolean flag (`clearDescription: true`). `TaskService.updateTask` already supports a `clearDescription` flag at the service layer.

A secondary question: how should whitespace-only descriptions (`"   "`, `"\n\n"`) be treated? The name field trims and rejects empty-after-trim; description could either mirror name (trim + reject), trim and treat empty-after-trim as a clear signal, or store whitespace verbatim.

### Decision

Treat any `description` field whose value is the empty string OR is only whitespace as the clear signal: trim leading/trailing whitespace; if the trimmed value is empty, clear the description. Otherwise, store the trimmed value. JSON `null` and any explicit `clearDescription` flag are rejected as invalid for this tool's surface area.

### Rationale

Empty string is the simplest wire-format contract: one field, one type (string), one validation rule (must be a string). Callers don't need to know about a side-channel flag. Tasks render no differently when the description is empty vs absent, so collapsing those states loses no observable information. Trimming and treating whitespace-only as a clear signal is consistent with how `name` handles whitespace and prevents storing visually-empty garbage.

This semantic is non-obvious from JSON Schema alone — JSON Schema can only state that the field is a string. AC 8.2 requires the prose description in `tools/list` and the App Intent parameter description to document this behavior explicitly.

### Alternatives Considered

- **Explicit `clearDescription` flag**: Mirrors `clearMilestone` for consistency within this tool — Rejected because it doubles the surface area for an operation with no useful "set to literal empty string" alternative, and because the empty-string signal is already unambiguous.
- **JSON `null`**: Standard JSON way to express "no value" — Rejected because it complicates Swift `[String: Any]` decoding and the existing pattern across MCP handlers is to reject `null` for typed fields.
- **Trim + reject empty-after-trim**: Strictest; treats description like name — Rejected because it leaves no inline clearing path, forcing callers to add a flag or omit the field entirely.
- **No trim; store whitespace verbatim**: Most literal — Rejected because storing `"   "` is never what the caller wants and diverges from name's trim rule.

### Consequences

**Positive:**
- Smallest schema surface
- One validation rule per field
- Consistent whitespace handling between `name` and `description`
- Handler translates `description: ""` or whitespace-only to `clearDescription: true` when calling the service

**Negative:**
- A caller who legitimately wants to set the description to a literal whitespace-only string cannot — acceptable because the model treats those states identically in display/query
- The empty-string-clears semantic must be discoverable through prose documentation rather than schema type information
- The `update_task` tool now has two clearing idioms: `clearMilestone: true` (boolean flag) and `description: ""` (sentinel value). A future change could converge them, but breaking the existing `clearMilestone` contract is out of scope here

---

## Decision 2: Metadata Full Replacement with Last-Writer-Wins Semantics

**Date**: 2026-05-22
**Status**: accepted

### Context

The user brief said "support clearing individual keys" for metadata. Two semantics were considered: (a) full replacement — the provided dict overwrites the stored dict entirely; (b) partial merge with null-clears-key — provided keys overwrite, omitted keys are preserved, null values clear specific keys. `TaskService.updateTask` currently does full replacement.

CloudKit sync means a task's metadata can be mutated by other devices between read and write, even when only one agent is calling `update_task`. The concurrency story matters for any chosen semantic.

### Decision

Pass `metadata` as a full dictionary that replaces the task's existing metadata in its entirety. To clear individual keys, the caller must read current metadata, remove the unwanted keys, and submit the modified dict. Submitting `{}` clears all metadata. Updates are last-writer-wins: a concurrent write from another device or the UI between the caller's read and `update_task`'s save can be silently overwritten.

### Rationale

Full replacement matches existing service behavior and requires no service-layer change. The wire format stays clean ([String: String] with no nullable values). The user brief's intent — "let agents clear keys" — is satisfied: the operation is supported, just via read-modify-write instead of patch-style null markers.

Last-writer-wins is acceptable for the Transit single-user model. Multi-device CloudKit writers are infrequent in practice (most metadata is written by one agent at a time), and the cost of a more sophisticated merge strategy (CRDT-style or version vectors) is far higher than the cost of the rare lost update.

### Alternatives Considered

- **Merge with null-clears-key**: `metadata: {"a": "v", "b": null}` sets a, removes b, leaves others — Rejected because it requires a new service method (`patchMetadata`), introduces `[String: String?]` Swift handling and null detection in `[String: Any]` decoding, and complicates validation (string-or-null vs string-only).
- **Separate `metadata` (replace) + `metadataPatch` (merge)**: Most expressive — Rejected as doubled surface area, doubled tests, doubled docs for a need the user can satisfy with read-modify-write today.
- **Optimistic concurrency with version tokens**: Add a `metadataVersion` or similar to detect concurrent writes — Rejected as significant model and protocol complexity for a low-probability problem in a single-user app.

### Consequences

**Positive:**
- No service-layer change
- Validation reduces to "object whose values are all strings"
- Wire format mirrors `create_task`'s `metadata` argument

**Negative:**
- Partial updates require a prior `query_tasks` call
- Concurrent writers (other devices, the UI, future second agents) can silently lose updates — documented as last-writer-wins

---

## Decision 3: Identifier-Only Call Is a No-Op Echo

**Date**: 2026-05-22
**Status**: accepted

### Context

A caller might invoke `update_task` with only `displayId` or `taskId` and no other fields — either as a probe ("does this task exist?") or accidentally. Two options: (a) treat as a no-op that returns the current task; (b) return an error requiring at least one update field.

A related ambiguity: which fields count as "mutating"? An explicit clear (`description: ""`, `metadata: {}`, `clearMilestone: true`) is structurally similar to a "no field" but is semantically a write.

### Decision

When the request includes only an identifier and no semantically mutating field, the handler resolves the task, skips the save operation, and returns the current task JSON. Explicit clears count as mutations and trigger save. Unknown JSON fields are silently ignored and do not block the no-op path.

### Rationale

The call is harmless and the response is useful (it doubles as a single-task lookup with the same response shape). Skipping the save avoids spurious CloudKit churn. An error here would reject a useful client pattern for no real benefit.

Treating explicit clears as mutations is the only consistent reading: `metadata: {}` is the documented signal for "clear all metadata" (AC 4.2) and must invoke save.

Silently ignoring unknown fields matches every other MCP handler in the codebase. It is forward-compatible: a future client sending a newer-version field will not break against an older build.

### Alternatives Considered

- **Return an error**: More explicit — Rejected because it rejects a benign call and provides no protective value.
- **Return current task and a `noOp: true` marker**: Lets callers distinguish probe from update — Rejected as protocol noise for limited benefit; callers can compare before/after themselves if needed.
- **Reject unknown fields**: Catches client typos early — Rejected because it breaks forward compatibility and diverges from the rest of the MCP surface.

### Consequences

**Positive:**
- Useful echo / existence-check pattern for clients
- No write amplification on probe calls
- Forward-compatible against future schema additions

**Negative:**
- Slightly less explicit about intent — a caller who forgot to add update fields gets no signal
- Client typos (`nmae`, `descrption`) are silently ignored — acceptable trade for forward compatibility

---
