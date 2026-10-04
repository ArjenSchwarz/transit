# Shared read integration ownership

Status: coordination proposal before task 13 GREEN. No shared-file handoff has occurred. The verified T63 component baseline is `dc85eabb5b35a6bd6b9ee16908d72aeb2c55bf15`; it does not enable production bounded routing. Task 12 routing fixtures reached actual app RED at `099415e832afc312a94e9521e3704eba729e441d`: saved reads leaked UI changes, frozen metadata was absent, valid and invalid reads exceeded five seconds, and a late cursor root became visible. Lifecycle/helper fixtures may proceed independently of actual T2382 delivery. Actual-module acceptance cannot pass on fixtures alone.

## Integration layers

1. T63 admits a classified read on the non-MainActor transport path using the original decoded admission instant. Protocol/header/envelope validation and availability classification use immutable transport state. Tool-domain validation, saved project/milestone resolution, policy decisions and capture run inside the bounded operation; they cannot add an unbounded MainActor hop before admission.
2. T63's policy-bound capture preparation starts the import observation window before the decision, preserves the original remaining budget, captures saved values inside the history/generation fence, and freezes metadata. T2382 receives that same complete declared-scope view for aggregation and reusable retention. A generic preparation callback must preserve observation lifetime and private reservation ownership.
3. Ordinary reads and T2382 helpers prepare tool-level results without an originating RPC ID. `MCPPreparedToolRead.encodedToolResult` is authoritative at the current baseline; its logical result is not a replay encoder. T2383's approved `MCPResultEncoder.freeze(...) -> MCPResultToolFragment` is the later modern representation. Cursor replay retains the original fragment, metadata, policy and expiry.
4. The transport prepares the complete RPC response bytes, with the current ID, before offering `PreparedReadResult` to the common publication domain. Candidate grouping and all-store validation precede one terminal selection. No response serializer runs after publication, and a timeout never releases an unfinished physical worker's permit.
5. T2383 takes the modern wire adapter after a verified T63 integration commit and explicit ownership transfer. Modern production rejects wire arrays. Existing coordinator batch tests may remain historical component evidence; T63 adds no dual-era protocol support. Final routing acceptance uses the modern adapter.

The parent and T2382 confirmed these tool-level helper signatures before delivery:

```swift
handlePortfolioSummary(request: MCPPortfolioSummaryRequest,
                       view: CapturedReadView,
                       operation: MCPReadOperation) throws -> MCPPreparedToolRead
handleSnapshotTaskQuery(request: MCPSnapshotTaskQueryRequest,
                        view: CapturedReadView,
                        operation: MCPReadOperation) throws -> MCPPreparedToolRead
```

The earlier no-ID `PreparedReadResult` scaffold is not a valid final-response boundary. T63 owns the one outer RPC encoder, including fallback response bytes and the original budget. The confirmed helper return composes with T2383 frozen fragments.

The types-only capture seam is `MCPReadCapturedPreparing.prepareCapturedRead(request:policy:operation:transform:)`. Its `MCPPreparedReadCapture` capsule carries `view` and `frozenMetadataBytes`. The Sendable async transform may use pure DTO work off MainActor and explicitly hop for handler/store work. Capture remains synchronous on MainActor inside the fence. The observation window remains held through transformation and private result/reservation preparation. This seam's implementation belongs to task 13; declarations do not establish delivery.

## File ownership

| Files or surface | Current owner | Later handoff |
| --- | --- | --- |
| `MCPServer.swift`, `MCPServer+Responses.swift`, `MCPServer+ToolListNotifications.swift` | T63 through verified bounded integration | T2383 becomes the sole writer for modern wire validation, discovery, subscriptions and response adaptation after explicit transfer. |
| `MCPToolListChangeBroadcaster.swift` | T63 retains current shared ownership; no new edits planned for read preparation | T2383 transport/subscription ownership with the same explicit transfer. |
| `MCPTypes.swift` | T63 preserves the existing metadata/result contract | T2383 modern envelope/result encoding after verified baseline; preserve T63's independent read metadata namespace. |
| `MCPToolHandler.swift`, `MCPToolHandler+TaskQuery.swift` | T63 common construction, classification and dispatch; actual T2382 registration | T2383 becomes the sole writer after verified integration. Later T63 diagnostic/read patches are narrow patches coordinated through that owner. |
| `MCPToolDefinitions.swift` | T63 through task 15 caller descriptions and common registration | T2383 supplies a narrow output-schema/discovery patch for T63 to apply; full transfer follows the verified description checkpoint. |
| All `MCP/Reads` files | T63 | Retain ownership. T2383 supplies narrow fragment/preparation changes for T63 to apply. Public physical-scope and freshness contracts remain shared. |
| `MCPTaskQuerySnapshotStore.swift` and ordinary retained-page hooks | T63 | Retain ownership for modern fragment retention and exact accounting. Never extend a retained root's original expiry. |
| Portfolio aggregation, request parsing, projection, separate handler/schema modules and reusable store | T2382 | T2382 delivers clean verified modules; T63 wires shared entrypoints. T2383 coordinates its reusable-fragment change through T2382. |
| `MCP/Writes/MCPWriteCoordinator.swift` and coordinator-specific write tests | T2384 | Remain T2384-owned. T63 uses separate read/server write-preservation tests and requests any overlap through the parent. |
| Capture, read coordinator, policy, publication and ordinary-retention fixtures | T63 | Retain ownership. |
| Modern transport fixtures | T2383 after transfer | T63 retains bounded-operation assertions through agreed test injection seams; no concurrent test-file edits. |

No blanket handoff is implied by this table. The parent records the exact clean revision and final file list before each transfer. Separate approved modules may progress independently while shared files remain with their current owner.

## Actual-module delivery dependencies

T2382 delivers its separate portfolio summary and snapshot query handlers, descriptors/tool definitions, reusable-store lifecycle hooks, participant aggregation, and tests from a clean verified revision. It confirms the helper return layer described above. T63 supplies the generic policy-bound capture preparation and shared dispatch registration; portfolio aggregation and reusable lifecycle logic remain in T2382 modules.

T2383's interface-only `8ea94ce0b3b9a3b73fcee330aed0c9883a08e92f` declares `freeze(source:presentation:metadata:)`, `encode(fragment:id:)` and `prepareMutationFallback(...)`. These methods are placeholders, not completed delivery. Its GREEN encoder must preserve original text/isError/source/presentation and frozen `_meta` values without renewed assessment or lossy numeric conversion. Retention charges expanded `encodedResult.count` plus uniquely retained backing once, retaining original policy and expiry. Complete response bytes must be ready before terminal publication.

Foundation tasks 1–11 and task 12's fixture draft do not depend on those later modules. Task 13 actual-module acceptance and final modern routing do. This separates preparation from delivery without making T2382/T2383 foundations wait for final T63 production routing.

## Verification and release

Each shared integration is a clean local ticket-branch commit with explicit source paths. The user approved local implementation sub-branch merges into ticket branches in `Sentinel_eafda56391a48191a3c414fef34d1307`; main/PR merges and deployment remain unauthorized. T2380 worktrees are not modified.

Heavy app/build/simulator jobs run only under an explicit exclusive slot from the parent. A worker releases the slot after app processes and physical fixture workers drain. T63 currently has no slot. Remaining task 12 preparation and light lint/type checks may proceed; further actual RED/GREEN jobs wait for a new grant. Final macOS/iOS validation and the full pre-push-review/Pulsar step follow actual-module integration.
