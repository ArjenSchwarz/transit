# T2384 pinned API15 isolation component

Recommended source path: consume this single isolation-only commit on 5e135d3dfc3cada13208c86fb5647b15352367ae, branch T-2384/batch-task-mutations. Parent identified this clean owner checkpoint after the ten API15 dependencies imported at fe1c57f and the evidence/encoding RED preparation. Preparation uses a separate fix/t2384-development-isolation checkout; active task-4/transit is unchanged. Owner should consume the commit before requesting a concrete verification slot.

App/project/Makefile/SyncManager/Settings inputs match the original 201205bd base. Narrow original-base isolation hunks applied without conflict; no whole-App/project replacement or speculative read dependencies. Existing helpers move to a same-file extension to keep lint limits. Existing writeServices, MCPWriteCoordinator arguments/lifetime, handler writeCoordinator injection and MCPServer constructor are preserved exactly. All Transit/Transit/MCP files, API15 Results/Protocol imports, models, TestModelContainer and evidence/encoding RED suites remain unchanged. Existing schema retains MCPWriteReceipt.

The component contains established 9ba4297 development/test isolation via the original-base adaptation, plus the fixture-only 33b006a disposable-path correction. Production Release identity/entitlements remain unchanged. Development/Debug use the distinct identity, CloudKit/push/App-Group-free entitlements and explicit unit-test mode; app storage/sidecar/allocator guards stay fail closed. The offline path guard resolves existing directories before adding the new leaf and rejects escaping parent/leaf symlinks; compiler/runtime sandbox guards are retained. No new models or write/coordinator behavior are introduced.

Source verification: clean patch apply/check, static development configuration guard, make lint passed with zero violations across 424 Swift files, diff whitespace passed, complete MCP tree and selected owner files have no changes. No compiler, executable probe, build, host or test suite ran. Previous isolation runtime passes are not claimed as T2384 branch verification. There is no source conflict; branch-local compilation/runtime checks remain pending.

After parent grants the slot, verify this branch first:

```sh
make test-development-isolation
make test-isolated-host-smoke SMOKE_DERIVED_DATA=DerivedData/t2384-isolation-smoke-fresh
```

Use a fresh directory/result bundle. Offline children retain network/live-container denial and the compiler sandbox. TransitIsolationSmoke hosts TransitDevelopment Debug/arm64 with explicit unit-test mode. Before test-without-building its runner checks actual signed development identity, absence of CloudKit/push/App Group entitlements and exact generated host/environment. App startup preflight requires the exact host path and memory-only/no-CloudKit/no-group configuration before container construction; post-bootstrap checks disabled counter adapters and isolated tmp sidecar. A smoke failure stops the sequence.

Only after branch-local smoke and the parent's focused-suite clearance, build a fresh shared Transit Debug host with exact selectors TransitTests/MCPBatchTaskEvidenceTests and TransitTests/MCPBatchTaskEncodingTests, private DerivedData/result paths, Debug arm64, locked packages, local ad-hoc signing and serial execution. Verify the signed Transit.app is me.nore.ig.Transit.development and the generated xctestrun explicitly unit-test; set TRANSIT_ISOLATION_SMOKE=1 and TRANSIT_SMOKE_HOST_PATH to that verified host path before test-without-building. Require empirical discovery matching the intended 13 declarations/52 expanded synthetic cases; do not count compile failure or zero discovered tests as RED. Legacy make test-quick without artifact/startup verification is not the readiness path.

App/project ownership remains with the isolation owner. Existing API/provider/result/write integration ownership is unchanged. No installed app launch, MCP enablement, live settings/data, client activation, CloudKit account/schema/provisioning or production release actions are authorized by this source component. Evidence stays local; no routine file delivery.
