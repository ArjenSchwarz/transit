# Decision Log: Task Priority

## Decision 1: Three fixed priority levels with medium default

**Date**: 2026-06-05
**Status**: accepted

### Context

The feature needs a way to express relative task importance so the board can signal what to focus on. The range of values must be simple enough to read at a glance and to map onto a single glyph.

### Decision

Priority is one of exactly three values — low, medium, high — with medium as the default for new and unspecified tasks.

### Rationale

Three levels are the minimum that distinguish "now / normal / later" without forcing the user to make fine-grained judgments. Medium as the default means a task that no one has triaged sits in the neutral middle rather than implying either urgency or deferral.

### Alternatives Considered

- **Numeric scale (e.g. 1–5)**: More granularity - Rejected as harder to glyph and over-precise for a single-user tracker.
- **Two levels (normal / high)**: Simpler - Rejected because the user explicitly wants a "can wait" signal, which needs a low tier.
- **A fourth "none/unset" level**: Distinguishes untriaged from medium - Rejected; medium-as-default already serves the untriaged case and a fourth value complicates the glyph and filter.

### Consequences

**Positive:**
- Maps cleanly to a three-state glyph and a three-option filter.
- The "unset" case is resolved silently by the accessor default (see Decision 2 and AC 1.3) rather than surfacing as a distinct value users must handle.

**Negative:**
- No way to mark a task as deliberately un-prioritized distinct from medium.

---

## Decision 2: Default-value backfill, no migration code

**Date**: 2026-06-05
**Status**: accepted

### Context

Transit uses SwiftData with CloudKit, where post-deployment schema changes must be add-only and all properties must be optional or carry a default. Existing tasks predate the priority field and need a sensible value.

### Decision

Store priority as a raw value with a default of medium, and have the computed accessor return medium when the stored value is absent. No explicit migration or backfill pass is run.

### Rationale

This mirrors the existing `typeRawValue` / `statusRawValue` pattern on the task model, satisfies the CloudKit add-only constraint, and makes every pre-existing task read as medium automatically. A migration pass would add risk and code for no behavioral gain.

### Alternatives Considered

- **One-time backfill routine on launch**: Explicitly writes medium to every old task - Rejected as unnecessary; the computed default already yields medium and avoids a write storm and sync churn.

### Consequences

**Positive:**
- Zero migration code; consistent with established model patterns.
- No CloudKit sync burst from rewriting existing records.

**Negative:**
- Old records carry no stored priority until next edited; correctness depends on the accessor's default rather than the data itself.

---

## Decision 3: Priority affects display and filtering only, not ordering

**Date**: 2026-06-05
**Status**: accepted

### Context

The board sorts tasks within each column by `lastStatusChangeDate` (with an "Organized" toggle). Priority could plausibly influence ordering so high-priority tasks float to the top.

### Decision

Priority is shown as a glyph and is filterable, but does not change task ordering within columns. Existing sort behavior is unchanged.

### Rationale

The stated goal — seeing what to focus on — is met by the glyph and filter. Folding priority into the sort is a larger, riskier change to existing ordering logic and the Organized toggle, and was not requested. Filtering to "high only" achieves the focus use case directly.

### Alternatives Considered

- **Priority as a sort tie-break or new sort mode**: Surfaces high-priority work automatically - Deferred; larger UI/logic change to existing sort, can be added later if filtering proves insufficient.

### Consequences

**Positive:**
- No change to existing, tested sort logic.
- Smaller, lower-risk scope.

**Negative:**
- High-priority tasks are not automatically promoted; the user must apply a filter to isolate them.

---

## Decision 4: Priority editable in the in-app create and edit screens

**Date**: 2026-06-05
**Status**: accepted

### Context

Tasks can be created and edited inside the app (AddTaskSheet, TaskEditView) as well as via MCP and App Intents. Priority could be settable only through automation, or also in the app.

### Decision

Add a priority control to both the in-app task creation screen and the task edit screen, in addition to MCP and App Intent support.

### Rationale

A user working directly in the app should not have to drop to MCP or Shortcuts to set priority. Including it in the existing create/edit forms keeps the feature usable for the primary in-app workflow and matches how `type` is already handled.

### Alternatives Considered

- **MCP/Shortcuts only**: Smaller scope - Rejected; it would make priority unsettable for someone using the app directly, undermining the focus goal.

### Consequences

**Positive:**
- Priority is settable through every task entry point (app, MCP, intents).

**Negative:**
- Adds a control to two more screens and their tests.

---

## Decision 5: Priority query filtering — multi-value on MCP, single-value on the intent

**Date**: 2026-06-05
**Status**: accepted

### Context

The explicit ask for MCP was to return priority and allow setting it. The existing query surfaces filter by `status` and `type`, and their cardinality differs *per surface*: the MCP `query_tasks` tool reads an untyped `[String: Any]` and accepts `status` as an array (`statuses: [String]?`), while the App Intent `QueryTasksIntent` decodes a typed `Codable` `QueryFilters` struct in which **every** filter — `status` and `type` — is scalar (`String?`). There is no array filter on the intent surface.

### Decision

`query_tasks` (MCP) filters by one or more priority values (multi-value array, mirroring the MCP `status` array). The query-tasks **intent** filters by a single priority value (scalar `String?`, mirroring its own `status`/`type` fields). Both reading and setting priority are supported on both surfaces; only the query-filter cardinality differs.

### Rationale

Each surface mirrors its own existing convention, which is the least surprising and lowest-risk choice. On MCP, accepting an array is free (untyped args, defensive single-or-array parsing already used for `status`). On the intent, every filter is a scalar field on a `Codable` struct; adding a multi-value `priority` would require custom single-or-array `Codable` decoding (a bare `"high"` would otherwise throw a generic decode error before priority-specific validation runs). That complexity is not justified — an agent needing multi-value filtering can use MCP. The resulting MCP-array / intent-scalar split is not a new inconsistency: it is exactly how `status` already behaves across the two surfaces. An earlier framing claimed the intent's `status` filter was multi-value; that was factually wrong and is corrected here.

### Alternatives Considered

- **Multi-value on the intent too**: Literal "one or more" everywhere - Rejected; needs a custom `StringOrStringArray` decoder (the riskiest new code in the feature) for a use case MCP already covers.
- **Return/set only, no query filter**: Matches the literal MCP request - Rejected; server-side filtering directly serves the focus goal and matches how `status` already works.

### Consequences

**Positive:**
- Each surface follows its own established filter convention; no custom decoding.
- MCP agents can request a priority subset in one call.

**Negative:**
- The intent filters one priority at a time (an agent wanting "high or medium" via Shortcuts must issue two queries or use MCP).
- MCP-array vs intent-scalar asymmetry persists — but it matches the existing `status` filter, so it introduces nothing new.

---

## Decision 9: Dedicated `INVALID_PRIORITY` error code

**Date**: 2026-06-05
**Status**: accepted

### Context

When a priority value outside {low, medium, high} reaches the MCP tools or the JSON intents, an error must be returned. The codebase already defines dedicated per-enum error codes `INVALID_TYPE` and `INVALID_STATUS`, used in exactly the validation flows priority joins (e.g. `CreateTaskIntent`, `QueryTasksIntent`).

### Decision

Add a dedicated `INVALID_PRIORITY` error code to the intent `IntentError` enum and the MCP error-code set, used for every invalid-priority condition (create, update, query filter).

### Rationale

Every other enum field gets its own error code; folding priority into the generic `INVALID_INPUT` would be the inconsistent choice and would deny clients the code-based handling they already get for `type` and `status`. Req 6.4 requires handling "consistent with the existing invalid-type handling," which means a dedicated code.

### Alternatives Considered

- **Reuse generic `INVALID_INPUT`**: Avoids adding an enum case - Rejected; breaks the established per-enum-code pattern and AC 6.4's consistency requirement.

### Consequences

**Positive:**
- Clients parse priority validation errors the same way as type/status errors.

**Negative:**
- One more error code to document (in CLAUDE.md's error list and the MCP/intent error tables).

---

## Decision 6: Board card shows a glyph only for low and high, not medium

**Date**: 2026-06-05
**Status**: accepted

### Context

The board card needs a priority glyph. Medium is the default, so the large majority of cards will be medium. The original idea was a glyph on every card (circle for medium, arrows for high/low).

### Decision

The board card displays a priority glyph only for low and high priority tasks. Medium tasks show no priority glyph. The glyph distinguishes low from high by both symbol shape and color (not color alone). Finalized glyphs: high = `arrow.up.circle.fill` tinted red; low = `arrow.down.circle.fill` tinted blue; medium = no glyph. The filter menu and detail view still represent medium (orange dot / text label), so medium remains discoverable there even though it is suppressed on the card.

### Rationale

A glyph on every card — most reading "medium" — adds visual noise across the entire board for no signal. Marking only low and high means the glyphs that appear actually indicate something worth noticing ("focus now" / "can wait"), while the neutral default stays clean. Distinguishing by shape as well as color keeps the indicator legible for colorblind users and lets VoiceOver name the level.

### Alternatives Considered

- **Glyph on all three (circle/up/down)**: The literal original description - Rejected; the medium glyph is noise on the majority of cards and dilutes the signal.
- **Color-only dot per level**: Compact - Rejected; color alone fails accessibility and is harder to read at a glance than shape + color.

### Consequences

**Positive:**
- Board stays uncluttered; high/low cards stand out.
- Shape + color differentiation supports accessibility.

**Negative:**
- A glance cannot distinguish "medium" from "priority not yet considered" on the card (both show no glyph); the detail view and edit screen show the explicit value.

---

## Decision 7: Priority shown on the detail view, excluded from reports

**Date**: 2026-06-05
**Status**: accepted

### Context

Beyond the board card and create/edit screens, priority could also appear on the task detail view and in generated reports of completed/abandoned tasks.

### Decision

The task detail view displays priority for all three levels (including medium). Generated reports are unchanged — priority is not included.

### Rationale

The detail view shows a single task's full data, so omitting priority there (when the card shows it) would be inconsistent; and unlike the dense board, a detail screen has room to show medium explicitly. Reports summarize completed/abandoned work where priority — a "what to do next" signal — has limited value, so it is left out to avoid scope and noise. Reports can add priority later if a need arises.

### Alternatives Considered

- **Include priority in reports**: Completeness - Rejected; priority is a forward-looking focus signal with little value in a completed-work summary, and it widens scope.
- **Board card only (no detail view)**: Smallest scope - Rejected; showing priority on the card but not the detail view would be inconsistent and confusing.

### Consequences

**Positive:**
- Priority is visible wherever a user inspects a task interactively.
- Report logic and format are untouched.

**Negative:**
- Completed-task reports carry no record of priority.

---

## Decision 8: Priority is non-clearable; omitting it on update leaves it unchanged

**Date**: 2026-06-05
**Status**: accepted

### Context

On the MCP `update_task` tool and the update-task intent, every field has explicit "omitted = no change" semantics (the existing per-field contract in `TaskUpdateValidator`). Priority is always one of three values with medium as the default, so there is no meaningful "no priority" state to clear to.

### Decision

Omitting priority on an update leaves the task's current priority unchanged. Priority cannot be cleared to an empty/absent value; it can only be set to one of low, medium, or high.

### Rationale

Without this rule, an implementation could default priority to medium on every update, silently downgrading a high-priority task during an unrelated edit. Making omit mean "unchanged" follows the codebase's established per-field update contract and prevents that data-loss footgun. Since medium is both the default and a real selectable value, "set to medium" must be expressible explicitly and distinct from "leave unchanged."

### Alternatives Considered

- **Default to medium on every update**: Simpler to implement - Rejected; it silently resets priority on unrelated edits, losing user/agent intent.
- **Allow clearing priority to absent**: Symmetry with nullable fields - Rejected; there is no "no priority" state (the accessor always yields a value), so a clear operation has no meaning.

### Consequences

**Positive:**
- Unrelated updates never disturb priority.
- Matches the existing per-field update semantics, so the API behaves predictably.

**Negative:**
- Callers must send an explicit `medium` to set medium; "unchanged" and "set to medium" are different operations they must distinguish.
