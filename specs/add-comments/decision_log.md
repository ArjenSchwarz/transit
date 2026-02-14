# Decision Log: Add Comments

## Decision 1: Author Field as Free-Form String

**Date**: 2025-02-14
**Status**: accepted

### Context

Comments need author attribution. The system must support both human users and various agents (claude-code, orbit, CI bots, future integrations). The author identification approach affects flexibility for future integrations.

### Decision

Use a free-form `String` field for `authorName` on the Comment entity. The user's name comes from an `@AppStorage("userDisplayName")` setting. Agents provide their own identifier string.

### Rationale

A string field is the most flexible option. The set of possible agents is open-ended and will grow over time (Orbit orchestrator, CI systems, other tools). An enum would require code changes for each new agent type. The user's display name as a setting (rather than hardcoded) allows personalisation.

### Alternatives Considered

- **Enum (user/agent/system)**: Typed and safe — rejected because it limits future agent diversity and requires code changes to add new agent types
- **Hardcoded user name**: Simpler — rejected because the user wants their actual name shown, not a generic "User" label

### Consequences

**Positive:**
- Any future agent or integration can identify itself without code changes
- User sees their chosen name on comments

**Negative:**
- No compile-time validation of author names

---

## Decision 2: Append-Only Comments with Individual Delete

**Date**: 2025-02-14
**Status**: accepted

### Context

Comments need a mutability policy. Options range from fully editable to completely immutable.

### Decision

Comments are append-only (no editing). Individual comments can be deleted. No bulk delete action.

### Rationale

An activity log mental model fits Transit's use case better than editable notes. Agents record what happened — editing those records would undermine their value as an audit trail. Individual deletion covers the case of removing incorrect or outdated comments without the complexity of edit history.

### Alternatives Considered

- **Fully editable**: Edit + delete — rejected because it adds UI complexity (edit mode, save/cancel) and undermines the log-like nature of comments
- **Fully immutable**: No delete — rejected because users need a way to clean up mistakes or irrelevant comments

### Consequences

**Positive:**
- Simple UI (no edit mode, no save/cancel flows)
- Comments serve as a reliable activity log
- Delete covers the "oops" case

**Negative:**
- Users cannot fix typos without delete + re-add

---

## Decision 3: Block Comment Creation When Display Name Is Empty

**Date**: 2025-02-14
**Status**: accepted

### Context

The user's display name is used as the author for comments created via the UI. If the display name is not set, comments would have an empty or meaningless author field.

### Decision

When a user attempts to add a comment via the UI and the display name setting is empty or whitespace-only, prevent comment creation and show an actionable message directing them to Settings.

### Rationale

Blocking ensures every comment has a meaningful author. A fallback like "User" would create comments with a generic label that can't be retroactively fixed once the user sets their name. Requiring the name at the point of use (rather than onboarding) avoids adding friction to first launch.

### Alternatives Considered

- **Fallback to "User"**: No friction — rejected because it creates comments with a meaningless author that persist forever
- **Require on first launch**: Catches it early — rejected because it adds onboarding complexity for a feature users may not use immediately

### Consequences

**Positive:**
- Every comment has a meaningful, user-chosen author name
- Simple to implement (check before create)

**Negative:**
- Minor friction on first comment if the user hasn't visited Settings yet

---

## Decision 4: isAgent Boolean for Agent Detection

**Date**: 2025-02-14
**Status**: accepted

### Context

The UI needs to visually distinguish agent comments from user comments. The initial approach compared `authorName` against the current `userDisplayName` setting, but this breaks when the user changes their display name — all previous comments would be reclassified as agent comments.

### Decision

Add an explicit `isAgent: Bool` field to the Comment entity. Set `false` when created via the UI, `true` when created via App Intents.

### Rationale

A boolean field makes the agent/user distinction permanent and stable at creation time. It doesn't depend on the current state of any setting, so changing the display name has no effect on existing comments. This was identified during review as a critical flaw in the original string-comparison approach.

### Alternatives Considered

- **String comparison against display name**: No extra field — rejected because changing the display name retroactively reclassifies all previous user comments as agent comments
- **Author type enum (user/agent/system)**: More structured — rejected as unnecessarily complex for a boolean distinction

### Consequences

**Positive:**
- Agent/user distinction is stable and permanent
- Display name changes don't affect existing comments
- Simple boolean check in the view layer

**Negative:**
- Extra field on the entity (trivial storage cost)

---

## Decision 5: User-Facing Shortcut with Typed Parameters

**Date**: 2025-02-14
**Status**: accepted

### Context

The Add Comment intent needs to be usable both as a Shortcut by users and programmatically by agents. The existing App Intents use a single JSON string parameter, but this is hostile for user-facing Shortcuts where users would need to manually construct JSON.

### Decision

Create the `Transit: Add Comment` intent with typed parameters (task identifier, comment text, author name) instead of a single JSON string. JSON-based agent intents (Add Comment, Comment on Status Update, Comments in Query Results) are out of scope for this spec.

### Rationale

Typed parameters integrate naturally with the Shortcuts UI — users get prompted for each field individually. The JSON pattern is appropriate for programmatic/agent use but creates a poor user experience in Shortcuts. Agent-facing intents will be addressed in a separate spec.

### Alternatives Considered

- **JSON string parameter (matching existing pattern)**: Consistent with other intents — rejected because it makes the Shortcut unusable for non-technical users
- **Both JSON and typed versions**: Maximum flexibility — rejected as unnecessary complexity; agent intents will be separate

### Consequences

**Positive:**
- Shortcuts prompts users naturally for task, comment, and name
- Discoverable in Shortcuts app and Spotlight
- Clean separation: this spec handles user-facing, agent-facing comes later

**Negative:**
- Different parameter style from existing JSON-based intents (acceptable since this serves a different audience)

---

## Decision 6: Comment Count Badge on Dashboard Cards

**Date**: 2025-02-14
**Status**: accepted

### Context

Users need to know which tasks have activity without opening each task's detail view.

### Decision

Display a comment icon with count on kanban dashboard task cards when a task has one or more comments. No indicator for zero comments.

### Rationale

A comment count gives at-a-glance visibility into task activity. Hiding the indicator for zero comments keeps cards clean for tasks without comments (which will be the majority initially).

### Alternatives Considered

- **No indicator**: Simpler cards — rejected because users would have to open every task to check for activity
- **Always show (even zero)**: Consistent — rejected because it adds visual noise to every card for a feature that won't apply to most tasks initially

### Consequences

**Positive:**
- Quick visual scan for task activity
- No clutter on tasks without comments

**Negative:**
- Requires fetching comment counts for all visible tasks (acceptable for a single-user app)

---
