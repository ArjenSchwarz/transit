# Decisions — T-2377

| Decision | Rationale |
|---|---|
| Full spec route | The new MCP tool creates a public API contract. |
| Proceed through spec and implementation | The delegated request explicitly authorises scoped implementation in an isolated branch; no additional permission is needed for reversible local work. |
| Require name and colorHex; default description to empty | These correspond to the project model and UI's optional description/repository fields; explicit color avoids an invented default. |
| Require six-digit RRGGBB or #RRGGBB; preserve case | Matches UI color output and existing prefixed project colors and rejects malformed colors rather than letting the UI silently render a fallback. |
| gitRepo stays free-form | Existing project UI/service imposes no URL restriction; paths and SSH remotes remain usable. |
| Share project metadata formatting | Keep creation and discovery consistent without changing milestone fetching. |

| Recovery decision | Rationale |
|---|---|
| Keep Xcode 27 blockers outside T-2377 | Clean baseline reproduces dependency and actor-fixture failures; correcting them expands scope. |
| Use two independent subagent peer perspectives | External Codex/Kiro MCP peers are unavailable; personal peer-review-validator explicitly allows fallback. |
| Leave In Progress pending compatible validation | Historical initial blocker; superseded by the passing macOS unit suite and subsequent Xcode MCP simulator validation below. |

| Xcode 27 scope decision | Rationale |
|---|---|
| Support Xcode 27 / Swift 6.4 | User explicitly expanded scope to fix the verified baseline blockers; earlier out-of-scope decision is superseded. |
| Pin released AsyncAlgorithms 1.1.3 | Resolver selected this revision; unpatched macOS tests and both builds pass. It removes the rejected generic takeSending helper while keeping other pins unchanged. |
| Make counter protocol/snapshot nonisolated and Sendable | Actor implementations need a contract independent of MainActor; immutable snapshots cross executors safely. |
| Keep deployment minimum at 26 | The toolchain update does not require dropping existing supported OS versions. |

| Xcode MCP/compiler recovery | Rationale |
|---|---|
| Use configured Xcode MCP bridge after user approval | The user requested MCP when make test invocation failed; approval for the bridge caller and worktree was explicitly granted. No global permissions/settings changed by implementation. |
| Move shared fixture actor conformances into extensions | Exact compiler reproduction fails in normal file order and passes with fixtures first. Empty extensions avoid the Swift 6.4 inference/validation interaction while preserving actor executors, state, checked Sendable and API names. Protocol-removal, nesting and local-refinement experiments failed and were reverted. |
| Keep host-source guard macOS-only | Simulator sample proved the existing synchronous #filePath source read blocks the main thread. Runtime description checks still run on iOS, and macOS retains source-literal drift coverage. The canceled run was finalized before a fresh suite started. This temporary approach was superseded by CLI migration after the same source-read stall was sampled on macOS. |
| Migrate source-literal guard into CLI validation | Both GUI app test runners block while opening host source paths. Preserve every assertion in repository validation and run it through lint/test preflight; runtime intent-description checks remain cross-platform. Final macOS suite passes 1823 tests plus the passing CLI guard, with no skipped app tests. |
| Run exact pre-push-review skill locally | Explicit user request after completion; review working-tree changes because no new commits exist. Publication/push remain unauthorised. |
