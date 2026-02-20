# PR Review Overview - Iteration 1

**PR**: #37 | **Branch**: T-158/bugfix-scenephasemodifier-modelcontext-per-eval | **Date**: 2026-02-20

## Valid Issues

### PR-Level Issues

#### Issue 1: Unused `taskService` binding in test

- **Type**: discussion comment
- **Reviewer**: @claude
- **Comment**: "In the first test, `taskService` is instantiated but never called — the test verifies promotion visibility by fetching directly from `context`. Either remove it (the service isn't needed to prove context visibility) or use it to verify the promoted ID is accessible through the service's own query path."
- **Validation**: Confirmed. `taskService` is created on line 18 of `SharedContextPromotionTests.swift` but never referenced. The test fetches directly from `context` on line 36. The binding is dead code and should be removed.

#### Issue 2: `seedBoardScenario` uses `container.mainContext` instead of `sharedModelContext`

- **Type**: discussion comment
- **Reviewer**: @claude
- **Comment**: "`seedBoardScenario()` writes via `container.mainContext`, a different context from `sharedModelContext` that the services observe. Worth aligning, or at minimum adding a comment explaining why `mainContext` is intentional here."
- **Validation**: Confirmed. Line 144 of `TransitApp.swift` uses `container.mainContext` while the rest of the PR establishes `sharedModelContext` as the single shared context. Since `sharedModelContext` is accessible from this method, it should be used for consistency with the PR's principle.

## Invalid/Skipped Issues

_None._
