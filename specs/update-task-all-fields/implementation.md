# Implementation Notes: Extend update_task to Support All Task Fields (T-650)

## Beginner

### What Changed

Until this branch, two surfaces — the MCP `update_task` tool that Claude Code uses, and the `UpdateTaskIntent` App Intent that Apple Shortcuts uses — could only change one thing about a task: its milestone. To rename a task, edit its description, change its type, or update its metadata, you had to open the Transit app and edit it by hand. This branch extends both surfaces so a single call can update any combination of those fields, atomically — either everything succeeds, or nothing changes.

### Why It Matters

Agents and shortcuts can now manage tasks end-to-end without round-tripping through the UI. If an agent gets a task wrong (e.g. classifies a bug as a chore) it can fix it in place. If the spec for a feature evolves, the description can be kept current from the same automation that creates the task. A multi-field update is a single atomic save, so the task can never end up "half-updated" with an invalid value sitting next to a valid one.

### Key Concepts

- **MCP tool vs App Intent**: Two doorways into the same logic. MCP is HTTP+JSON-RPC for Claude Code; App Intent is the Shortcuts/Apple Intelligence path. Both surfaces accept the same JSON shape and return the same response shape.
- **Validation before mutation**: The new shared `TaskUpdateValidator` reads the request and produces a fully-validated update value before touching the task. If the request is invalid, the task is never modified.
- **Empty-string clears**: `description: ""` (or whitespace-only) means "clear the description". `metadata: {}` means "clear all metadata". `clearMilestone: true` still works for milestones. Omitting a field means "leave it alone."
- **Atomic save**: All the validated changes are applied to the task in memory, then a single `save()` writes them to disk and CloudKit. If save fails, the in-memory state is rolled back so the next read sees the original task.

---

## Intermediate (5–10 years experience)

### Architecture

Both the MCP handler (`MCPToolHandler.handleUpdateTask`) and the App Intent (`UpdateTaskIntent.execute`) collapse into the same five-step pipeline:

1. **Parse identifier** (preserve T-634/T-808 semantics — malformed `displayId`/`taskId` produce a field-specific `INVALID_INPUT`, not a generic not-found).
2. **`TaskUpdateValidator.validate(args, task, milestoneService)`** — pure function returning `Result<ValidatedTaskUpdate, TaskUpdateValidationError>`. Walks fields deterministically (`name` → `description` → `type` → `metadata` → milestone), short-circuits at the first failure, and never mutates anything.
3. **No-op echo** — if `update.hasChanges == false` (caller passed only an identifier), skip the save and return the current task JSON via `IntentHelpers.taskUpdateResponseDict`.
4. **`TaskUpdateValidator.apply(update, task, taskService, milestoneService)`** — calls `taskService.updateTask(..., save: false)` for non-milestone fields then `milestoneService.setMilestone(..., save: false)` if milestone changed. Throws service-layer errors only; the handler is responsible for rollback on mid-step throw via `taskService.rollback()`.
5. **`taskService.save()`** — single transaction. `TaskService.save()` already wraps `safeRollback()` on failure.

### Key Patterns

- **`FieldChange<T>` algebraic data type**: `noChange | set(T) | clear`. Eliminates the optional-plus-boolean-flag idiom (`description: String?, clearDescription: Bool`) in the validator's surface — `apply()` translates `FieldChange<String>` into the service's existing `(description: String?, clearDescription: Bool)` parameter pair. Translation happens in one place; downstream code pattern-matches on cases instead of juggling sentinel combinations.
- **`MilestoneAction` enum** carries the already-resolved `Milestone` instance through validation into apply, avoiding a second `findByDisplayID` / `findByName` lookup at apply time.
- **Strict metadata coercion** is a separate helper (`strictStringMetadata`) from the existing `IntentHelpers.stringMetadata`. The existing helper silently drops non-string values; T-650 requires explicit rejection (AC 4.4). The two helpers coexist because their semantics genuinely differ and the strict variant carries a feature-specific error type that doesn't belong in `IntentHelpers`.
- **Surface-specific error translation**: `TaskUpdateValidationError` exposes `mcpMessage: String` and `intentError: IntentError` projections. The validator emits structured errors once; each surface renders them into its own envelope. AC 5.2 explicitly carves out error-message divergence between the two surfaces.

### Trade-offs

- **Apply duplicates `hasChanges` logic locally**: `apply()` recomputes `hasFieldChange` for the "should I call `updateTask`?" decision because `ValidatedTaskUpdate.hasChanges` includes milestone, which `apply()` handles separately. Adding a second computed property (`hasFieldChanges`, excluding milestone) was considered and rejected as not worth the API surface.
- **Two surfaces still have separate orchestration code**: `MCPToolHandler.handleUpdateTask` and `UpdateTaskIntent.execute` mirror each other line-for-line. The duplication is intentional — the surfaces own their parse step, their no-op response encoding, and their error envelope. Hoisting them into a shared helper would either leak too much surface or require generic-over-error-envelope code that costs more than it saves.
- **`clearMilestone: true` on already-unassigned task** triggers a no-op save. The validator emits `MilestoneAction.clear` unconditionally to preserve pre-T-650 behavior — the simpler code costs one redundant save in an edge case that is unlikely to be hot.
- **Last-writer-wins for metadata** (Decision 2). Full replacement keeps the wire format clean; concurrent CloudKit writes from another device can silently overwrite. Acceptable for Transit's single-user model.

---

## Expert

### Deep Dive

The architecture decouples *what the request means* from *which surface received it*:

- `TaskUpdateValidator` is the contract.
- `ValidatedTaskUpdate` is the canonical representation post-parse, with field representation chosen so invalid states are unrepresentable: non-clearable fields (`name`, `type`) use `Optional<T>`; clearable fields (`description`, `metadata`) use `FieldChange<T>`; milestone uses `MilestoneAction` so a resolved `Milestone` instance rides the validation boundary.
- `apply()` is a function over `(ValidatedTaskUpdate, services)` — pure dispatch into the service layer with `save: false`.
- The single `save()` provides the transaction. `TaskService.save()` already calls `modelContext.safeRollback()` on throw; the handler additionally invokes a new `TaskService.rollback()` (a thin `safeRollback()` wrapper) when `apply()` throws between its two service calls — `updateTask` may have mutated the task in memory before `setMilestone` failed.

The two-stage do/catch around `apply` and `save` exists because their rollback contracts differ: `apply` does not own a transaction (it called `save: false` twice), so a mid-step throw needs an explicit rollback; `save` owns the transaction and rolls back on its own throw. Collapsing them into one catch would require either a sentinel "did we get past apply?" boolean or a redundant rollback after save failure — both worse than the explicit two-stage form.

### Architecture Impact

- `IntentHelpers.taskUpdateResponseDict` is a new builder specifically for the AC 9.1 shape. It cannot reuse `taskToDict(detailed: true)` because that helper encodes `task.taskDescription as Any` — `nil` becomes `NSNull` in JSON, which violates the omit-when-empty rule. It also includes `lastStatusChangeDate`/`completionDate`, which AC 9.1 forbids. The two builders coexist permanently: `taskToDict` for query/create responses, `taskUpdateResponseDict` for update responses.
- `TaskService.rollback()` is a new public API. It exists because the handler needs to revert in-memory mutations *before* `save()` is called when a multi-step apply throws between steps. The existing `ModelContext+SafeRollback` extension is internal to the service layer; the new method opens it just enough for orchestrators.
- `MCPToolDefinitions.updateTask.inputSchema` now lists `name`, `description`, `type`, `metadata`. The prose for `description` and `metadata` carries the empty-string-clears / `{}`-clears discoverability requirement (AC 8.2) — JSON Schema alone can't express these sentinel semantics, so they live in the description string. The parity test (`UpdateTaskAllFieldsParityTests`) asserts both surfaces document them with the same wording.
- The `inputParameterDescription` static on `UpdateTaskIntent` duplicates the `@Parameter` literal because the macro requires a compile-time literal but tests need to assert on the prose. The duplication is small and the test-seam value (proves the wording matches the MCP schema in parity tests) justifies the maintenance cost.

### Edge Cases

- **Identifier-only request with unknown fields**: AC 6.3 — unknown fields are silently ignored and do not flip the request from no-op to save. The validator only reads keys it knows about, so `hasChanges` stays false regardless of stray keys.
- **`clearMilestone: false`** (explicitly false): falls through and resolves any other milestone fields if present. Matches pre-T-650 behavior.
- **`description: "   "`** (whitespace-only): trims to empty, treated as `.clear`. Same as `description: ""`. Consistent with how `name` trims (though `name` rejects empty rather than clearing).
- **Metadata with `NSNumber` values from `JSONSerialization`**: `as? String` cast fails, returns `"metadata values must be strings"`. The existing permissive helper would have silently dropped them; the new strict helper rejects.
- **Multi-field invalid request**: AC 5.2 — only one error is surfaced. The walk order is deterministic (`name` → `description` → `type` → `metadata` → milestone) but not part of the public contract. The MCP and App Intent surfaces may legitimately surface different messages for the same multi-field-invalid input; success-case parity is enforced separately by `UpdateTaskAllFieldsParityTests`.
- **Save failure after CloudKit-size hit**: routes through `TaskService.save()` → `safeRollback()` like any other save failure. AC 5.3 explicitly says there is no separate error code for size violations.

### Completeness Assessment

- **Fully implemented**: all 9 acceptance criteria — name (1.1–1.4), description (2.1–2.4), type (3.1–3.4), metadata (4.1–4.5), atomicity (5.1–5.3), no-op echo (6.1–6.3), milestone backward compat (7.1–7.2), cross-surface parity (8.1–8.2), response shape (9.1).
- **Partially implemented / acknowledged gap**: AC 5.3 has no handler-level test for save failure. The design notes that `TaskService` is `final` without a protocol seam, so faking save failure at the handler level is out of scope for T-650; the catch path is a single line, and AC 5.3 coverage is provided by the existing `TaskService.save()` service-layer test that asserts `safeRollback()` runs on failure. This is a deliberate carve-out, not a missing piece.
- **Missing / deferred**: visual `EditTaskIntent` (a Shortcuts-friendly UI for editing fields) and changing a task's project are explicitly listed as non-goals in requirements.md and deferred to separate tickets.
- **Documentation**: CHANGELOG.md has phase-by-phase entries describing the new fields, the rewrite, and the parity test. `docs/agent-notes/mcp-server.md` Tools Exposed table updated with the extended `update_task` and the omit-vs-clear gotcha. README.md / CLAUDE.md were not updated — they describe the data model and intent overview rather than per-field semantics, so the existing wording remains accurate.
