# MCP Project Creation Design

Register `MCPToolDefinitions.createProject` in coreTools and dispatch `create_project` from MCPToolHandler. Required schema fields are name and colorHex; description and gitRepo are optional strings. Color is required so clients explicitly select the persisted project color without a platform-dependent UI default.

Validate both required strings with the existing requiredString helper. Require colorHex to match `^#?[0-9A-Fa-f]{6}$` with a whole-string match; preserve letter case. Reject present non-string optional fields, including null, before calling ProjectService.createProject. Description and gitRepo contents pass through unchanged, including literal escapes and newlines. The service trims names, checks existing locale-stable case-insensitive uniqueness, inserts, saves, and deletes the inserted model on save failure. Map invalidName and duplicateName to actionable errors; report underlying storage errors as creation failure.

Return a JSON object inside the existing MCP text-result envelope, matching get_projects project metadata fields. New projects have zero active tasks and no milestones. Reuse one project metadata formatter for get_projects and create_project so response shapes stay consistent. Do not fetch milestones after creation: a failed follow-up fetch must not report a saved creation as failed.

The existing derived mutatingToolNames set automatically blocks this new tool in fallback storage. Tests cover schema discovery, validation/atomic rejection, duplicate lookup failure, returned metadata, subsequent task creation, discovery, and fallback rejection. Existing ProjectServiceTests cover successful persistence and ModelContextSaveHelpersTests cover failed-save cleanup; no new service injection hook is needed.

## Risks and verification

MCP fields establish a public contract. Lock required fields and response shape with tests. Preserve existing get_projects milestone behavior via its regression suite. Keep changes behind macOS guards and verify both platform builds.

## Xcode 27 compatibility

Use the released AsyncAlgorithms 1.1.3 revision `9d349bcc328ac3c31ce40e746b5882742a0d1272` in Package.resolved; retain all other dependency pins. This release removes the generic takeSending helper rejected by Swift 6.4. Avoid application concurrency-mode downgrades or dependency-cache modifications.

Declare DisplayIDAllocator.CounterSnapshot as nonisolated and Sendable, with its existing immutable Int/String? values. Declare its async CounterStore protocol nonisolated and Sendable, allowing independent actor implementations instead of inheriting the app's default MainActor isolation. Production CloudKitCounterStore remains MainActor isolated; allocator gate, retries, and compare-and-swap semantics remain unchanged. Existing actor-backed allocation/concurrency tests verify the behavior. The shared fixture actors declare their conformances in empty extensions, avoiding Swift 6.4 declaration-order inference errors without changing their executors or state.

Document Xcode 27 / Swift 6.4 as the development toolchain; keep the iOS/macOS minimum deployment versions at 26. Validate make lint, make build, make test-quick, and the full simulator unit/UI suite. Use Xcode MCP for build/test invocation issues, as requested by the user.

Host-source literal-drift assertions run in CLI validation before lint and test commands. Runtime description checks remain cross-platform; app test runners never synchronously open host source paths.
