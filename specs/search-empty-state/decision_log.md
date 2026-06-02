# Decision Log: Search Empty State

## Decision 1: Search-only empty state defers to the generic filter message when other filters are active

**Date**: 2026-05-31
**Status**: accepted

### Context

The dashboard shows an empty-state overlay when no tasks match the active filters. T-198 adds a dedicated `ContentUnavailableView.search(text:)` state for text search. The board has four filter inputs that can be combined (search text, project, type, milestone), so we must decide which empty state appears when search text is active *and* one or more of the other filters are also active and the result is empty.

### Decision

Show the native search empty state (`ContentUnavailableView.search(text:)`) only when search text is the *sole* active filter. When any of project/type/milestone is also active, keep showing the existing generic "No matching tasks. Clear filters to see all tasks." message.

### Rationale

When multiple filters are stacked, the most useful next action for the user is usually to relax a filter, and the generic message says exactly that ("Clear filters"). The native search state ("No Results for '<query>'") implies the query is the problem, which is misleading when a non-search filter may be the real cause of the empty result. Restricting the search state to the search-only case keeps each message's hint accurate.

### Alternatives Considered

- **Search state always wins when search text is present**: Simpler condition (just check non-empty search text) - Rejected because it hides the "clear filters" hint when a project/type/milestone filter is the actual cause of the empty result, misleading the user.
- **A dedicated combined "search + filters" empty state**: A third message covering the both-active case - Rejected as scope creep for a deferred follow-up; the generic message already covers it adequately.

### Consequences

**Positive:**
- Each empty-state message gives an accurate, actionable hint.
- The branching condition stays readable (three mutually exclusive cases, most specific first).

**Negative:**
- Users who search *and* filter never see the native search presentation; they get the generic message instead. Acceptable, since the generic message is still correct.

---

## Decision 2: An empty database takes precedence over search text

**Date**: 2026-05-31
**Status**: accepted

### Context

The empty-state branching has three triggers: no tasks at all, search-only no-match, and generic-filter no-match. When the database is completely empty *and* the user has typed a search query, both the "no tasks" condition and the "search" condition are technically true. We must define precedence.

### Decision

When there are zero tasks in the database, show "No tasks yet. Tap + to create one." regardless of any search text. The empty-database branch is evaluated first.

### Rationale

If nothing exists, there is nothing to search; "No Results for '<query>'" would imply the query is at fault when the real situation is an empty app. Directing the user to create a task is the only useful action. This matches the current behavior, where `allTasks.isEmpty` is checked before any filter branch.

### Alternatives Considered

- **Show the search state when search text is present, even with zero tasks**: Treats search text as the dominant signal - Rejected because it misleads the user about why the board is empty and hides the actionable "create a task" hint.

### Consequences

**Positive:**
- The "create your first task" guidance is never hidden behind a search query.
- Preserves existing first-branch ordering, minimizing behavioral change.

**Negative:**
- A user who searches in a brand-new empty app sees "No tasks yet" rather than a search-specific message. Acceptable and arguably clearer.

---

## Decision 3: Extract empty-state selection into a pure function

**Date**: 2026-05-31
**Status**: accepted

### Context

The choice of which empty state to display is conditional logic. If it lives inline in the SwiftUI view body, it can only be exercised through UI tests, which are slower and more brittle. The repository's Swift rules call for extracting business logic out of views into testable units, and the smolspec requires distributed testing.

### Decision

Implement the empty-state decision as a pure function `DashboardLogic.emptyStateKind(...)` returning an `EmptyStateKind` enum, taking plain value inputs (no SwiftUI types). The view switches over its result.

### Rationale

A pure function lets the branch logic (including the empty-database and search-only precedence rules) be covered by fast unit tests alongside the existing `DashboardLogic` tests, leaving UI tests to verify only what they uniquely can — that the search bar stays visible and the correct identifier renders.

### Alternatives Considered

- **Inline `if/else` in the view body**: Less code - Rejected because the branch logic would be verifiable only via UI tests, conflicting with the repo's "extract logic from views" rule and the distributed-testing requirement.

### Consequences

**Positive:**
- Branch precedence is unit-tested deterministically.
- `DashboardLogic` stays the single home for dashboard view logic.

**Negative:**
- A small enum and function are added rather than a three-line conditional. Justified by the testability gain.

---
