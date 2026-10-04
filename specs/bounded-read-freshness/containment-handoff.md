# T63 containment ownership handoff

Source checkpoint: `36f7ee328f53250413beff825af3ae826e25d3d0` on `T-63/bounded-read-freshness`. Source was clean before this document. Stage A is lint-clean but has not passed app compilation/runtime GREEN. Existing app-host and live-write holds remain until the parent explicitly clears them.

## Narrow ownership transfer

The containment worker may own `Transit/Transit/TransitApp.swift` and the development target's project, scheme, entitlement, and build/test selection changes. T63 has no active edits to those files and will not edit them concurrently. T63 retains its read coordinator, dispatcher, service, capture, retention, and read-test files. Any later app-construction change from T63 should be a narrow patch applied by the containment owner.

Pinned source blobs at the checkpoint:

- `Transit/Transit/TransitApp.swift`: `ac0ffa791047285c7526dba96bfa920733f0f734`.
- `Transit/Transit.xcodeproj/project.pbxproj`: `e9d10d37ee46aaa5bde17863b8692857c5ef846a` (T63 has not changed this project file).

Use a clean containment patch or commit chosen by the parent; do not replace the whole app file from an earlier branch. T63's app delta against `e3812b1` is the read construction below plus a mechanical move of the MCP-start methods to an extension.

## Preserve the T63 construction

After the final selected container and effective sync mode are known, preserve these relationships:

```swift
let reads = MCPReadAppDependencies.make(container: container, syncActive: cloudSyncActive)
let readCoordinator = MCPReadCoordinator(domain: reads.snapshots.domain)
// Handler construction retains its existing writeCoordinator and persistence inputs,
// and receives taskQuerySnapshots: reads.snapshots,
// readService: reads, readCoordinator: readCoordinator.
// MCPServer receives that SAME readCoordinator.
```

There is one coordinator per app lifetime; listener restart must not construct another. Ordinary retention and the coordinator share one publication domain. `MCPReadAppDependencies` reads public history and starts an observer; it does not save records or establish positive import visibility. In isolated development/test storage, effective sync must remain false. Keep the protected-write `MCPWriteReceipt` model in the app schema and keep receipt sidecars in the isolated storage policy.

## Containment acceptance boundary

The existing `NSClassFromString("XCTestCase")` test-host heuristic is not verified for the Swift Testing host processes. The new development/test target must select isolated storage deterministically and fail closed before live container creation or sidecar selection; runtime class detection alone cannot be the safety boundary. Development bundle identity, store URL, CloudKit entitlement/configuration, receipt sidecar, and automatic MCP startup must follow that target's explicit policy. Do not launch/reconnect the development MCP server as part of this handoff.

Synthetic disposable-store migration checks are owned by containment and must preserve UUID/display-ID and receipt/revision evidence. Seven rows imported in one CloudKit transaction and mixed model generations are evidence/hypothesis reported by the parent, not a cause established by T63. This document authorizes no live record correction, deletion, merge, reassignment, or guard reset.

App-host verification resumes only after the parent reviews the verified isolation result and explicitly clears the hold. The parent granted the isolated component integration and the six focused suites after containment's verified smoke checkpoint `9ba4297`. T63 integrated the component at `6806262`, retained the owned actor fix `46bec7c`, and added the missing fixture import at `c614a9b`.

The verified Stage A checkpoint is `b500543369ebbd53f01634fa829bf74a8fceabe5`. Its dedicated isolated smoke passed one test; the shared Transit Debug build passed, signed-host/xctestrun preflight passed, and six sequential suites passed fourteen methods / seventeen device executions with zero failures or skips. Both timed full-response cases completed below five seconds. Initial fixture assertion failures and the initial runner termination limitation are retained separately from the corrected passing results. All owned processes drained and the exclusive slot was released.

Evidence and exact commands are preserved outside Git at `/Users/arjen/Documents/Codex/2026-10-03/task/t63-review-evidence/stage-a-isolated/`. This grants no broader suite, production launch, live Transit write, or app MCP enablement. Final T2382 and modern protocol integration remain separate acceptance gates. Containment keeps App/project/isolation ownership; T63's future construction changes remain owner-applied narrow patches.
