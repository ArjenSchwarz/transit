# Development and test storage isolation

Status: standalone isolation verification and development-target build passed; app-host acceptance blocked by the allocator-construction finding in source-review.md. Branch fix/development-store-isolation is based on the T63 ownership checkpoint 36f7ee328f53250413beff825af3ae826e25d3d0. The containment owner preserves T63 read construction and owns only the narrow isolation changes.

## Resulting policy

TransitDevelopment is a separate native target and shared scheme, using me.nore.ig.Transit.development for Debug and Release. Its entitlements contain neither CloudKit/push nor App Groups. Existing Transit Debug builds and their test hosts also use the isolated identity. Transit production Release configuration and entitlement source are unchanged.

Launch mode resolves before SyncManager, a container, or sidecar creation. Debug/development builds with production identity fail closed. Test requests with production identity also fail closed. The test scheme explicitly supplies TRANSIT_PERSISTENCE_MODE=unit-test; every UI launch explicitly supplies ui-test. Runtime XCTest detection is only an additional isolated fallback. Invalid launch modes never fall through to production.

IsolatedPersistenceConfiguration returns a named development.store below TransitDevelopment in the development app support directory, or an in-memory test container. Both use cloudKitDatabase.none. Production mode is rejected by this factory. Isolated SyncManager ignores saved sync preferences, rejects enabling sync and clamps active sync false. Development/test automatic MCP startup and sync connectivity callbacks are suppressed. Receipt sidecars use the isolated persistent URL or a unique temporary test directory. T63's one shared publication domain/read coordinator is retained.

## Checks already completed

- Project/entitlement/Info plist syntax and shared scheme XML parsing.
- Source configuration guard for bundle identity, entitlements and explicit test launch mode.
- Exact equality of production Release build configuration and production entitlement file against T63 base.
- Strict focused SwiftLint: no violations in changed app/policy/configuration/probe Swift files.
- Whitespace diff check.

Standalone compilation and synthetic harness verification passed. Full make lint passed across 441 Swift files. No app-host test, activation, deployment or live-data mutation occurred.

## Requested exclusive verification commands

Run from /Users/arjen/Documents/Codex/2026-10-02/task/transit-isolation:

```sh
make test-development-isolation
```

This compiles two standalone executables only. Compiler subprocess sandboxing is retained. Swift help describes -disable-sandbox as disabling sandbox use for subprocesses; it is not a SwiftPM-only option. The approved invocation explicitly supplied an empty flag variable, and the isolation target now always omits that optional legacy compiler flag. Normal per-command escalation was approved; no approval was bypassed. Runtime children use sandbox-exec to deny network and access to the production Transit container and Group Containers. Synthetic stores are confined to a fresh DerivedData/tmp/transit-synthetic-* directory; the probe rejects other paths. No app main, listener, allocator or sync service is launched. Each child operation is bounded; results go to DerivedData/isolation-verification.json. The actual isolated configuration is exercised before sequential and overlapping old/new schema cases. Projection revision tokens use the production revision algorithm under a synthetic projection name, not a claimed complete task revision.

A second, build-only gate needs locally staged resolved packages:

```sh
mkdir -p DerivedData/SourcePackages
ditto /Users/arjen/Documents/Codex/2026-10-03/task/transit-t63/DerivedData/SourcePackages DerivedData/SourcePackages
make build-development-macos
```

The target uses two build jobs, offline resolved package flags and CODE_SIGNING_ALLOWED=NO. It does not install or launch an app. App-host tests remain separately held. If dependencies cannot resolve offline, report the failure rather than enabling downloads or provisioning. Do not edit T63-owned read files to solve unrelated baseline errors.

## Interpretation boundaries

The historical snapshot proves seven duplicate rows were inserted by a CloudKit import at 13:23:41 UTC. The failed matching import was logged by the installed process. Mixed entity numbering and binary receipt markers support concurrent model generations sharing the live store, but do not prove the full causal chain. Offline synthetic verification can prove local compatibility outcomes only; it cannot reproduce a remote CloudKit import. Live repair and any separate development CloudKit provisioning remain separate decisions.

The phone renumbered some duplicates after the snapshot. Current live IDs must be re-read through supported installed-app access; do not use historical display IDs as mutation targets. At the last access check, the installed app was running, the console was locked, MCP had no listener on 3141, and this session exposed no UI-control tool.

## Verified results

The standalone harness exited 0 without -disable-sandbox. Launch policy checks passed. The actual development configuration created its explicit isolated store; actual unit/UI test configurations saved synthetic records in memory. Sequential migration preserved task/project UUIDs, display ID, status, relationships and synthetic projection revision; the new receipt was saved and read back. The overlapping old/new process case also retained one task and the relationship with zero UUID duplicates. Both disposable databases passed quick_check. This offline case did not reproduce the live CloudKit duplication; import-specific behavior remains unverified.

The build-development-macos gate used staged local resolved packages, two jobs and signing disabled. It reached app compilation but xcodebuild exited 65 on MCPReadService.swift:97:26: the applicability closure is non-Sendable and main actor-isolated in an outside-actor call. This file is T63-owned and unchanged by this patch. No isolation-specific compiler diagnostic was observed, but the target build remains failed, not verified complete. Parent/T63 must provide an owned fix before a fresh build gate; do not release app-host tests on the strength of the standalone gate alone.

Evidence is in verification/isolation-verification.json and verification/build-diagnostics.json. The original live snapshot remains separate historical evidence, and current renumbered live tasks are outside this implementation's mutation scope.

## Build after T63 compiler handoff

Applied the exact one-line source from T63 commit 46bec7c386624ce755c11940ef58bf046999cb02, verified byte equality with that commit, then ran build-development-macos. Exit 0 / Build Succeeded. Generated app Info identifies me.nore.ig.Transit.development, Transit Development, executable TransitDevelopment. No install, launch or app-host test occurred. Earlier failure diagnostics are retained as historical evidence.

Independent local read-only review then identified an isolated-bootstrap CloudKit handle-construction gap in DisplayIDAllocator's default convenience initializer. Counter RPC guards are present, but this constructor path was not covered by the persistence harness. App-host holds stay in place pending a disabled-store allocator path and exact offline bootstrap verification. The conditional component-handoff.md must not be read as a host-run release.

## Inactive allocator bootstrap correction

Resolved the reviewed constructor gap after 4f1a81f: AppDisplayIDAllocators checks launch mode and effective sync before selecting adapters. Inactive modes use DisabledCounterStore through the designated initializer, so CKContainer.default/privateCloudDatabase is never constructed on that branch. Active production retains the original CloudKit convenience initializer and global-counter/milestone-counter names. T63 source and shared coordinator wiring are untouched.

Added an exact-source offline bootstrap executable covering both sync inputs for every isolated mode, production sync-off, fail-closed direct counter access, allocation rejection and provisional-task promotion no-op. Production dispatch is tested with a spy factory, without constructing a CloudKit handle. Every executable runs under the existing network/live-container-denying sandbox; swiftc subprocess sandbox is retained. The complete isolation harness passed; development build-only gate passed; lint passed with zero violations across 443 files. No app-host tests, launches, live reads/writes or server actions ran during this correction. Source review resolves the bootstrap finding, with app-host release still controlled by the parent.

## Minimal isolated test-host smoke

The parent explicitly released one isolated smoke exception while retaining all broader host holds. Added a dedicated TransitIsolationSmokeTests target and TransitIsolationSmoke scheme hosted only by TransitDevelopment; it builds a single opt-in fixture. The original shared test target could not build because of existing ticket-owned MCP read-test import errors, so those tests were left unchanged. Isolated memory configuration now explicitly disables App Group selection as well as CloudKit.

The host_smoke.py runner verifies the actual signed development bundle ID, absence of CloudKit/push/App Group entitlements, exact generated host path and explicit unit-test environment before test-without-building. It sets opt-in attestation and exact host path in a derived xctestrun; no global settings or permission changes occur. App preflight rejects wrong identity/mode/path or persistent/CloudKit/App Group configuration before ContainerFactory invocation. Post-bootstrap attestation checks actual container configurations, disabled counter adapters and the temporary sidecar before its coordinator is created.

One test in one suite passed. The actual configuration URL was /dev/null; memory-only true, effective cloud sync false, both counters disabled, sidecar in the development app container's tmp directory. This proves the app bootstrap selected no live/default persistent store; no system-wide file-open trace was captured. Xcode adds its standard test-driver sandbox/debug entitlements to the ad-hoc test host, with no CloudKit/push/groups; production entitlements are untouched. No installed app launch, MCP enablement or broader test suite ran. All smoke build/test workers exited. The refreshed offline harness and lint also passed.

Reusable command (a fresh, unused result directory is required):

```sh
make test-isolated-host-smoke SMOKE_DERIVED_DATA=DerivedData/isolation-host-fresh
```

This target builds Debug/arm64 with two jobs, locked package resolution, local ad-hoc signing and no provisioning, verifies the generated artifacts, then runs only TransitIsolationSmokeTests/DevelopmentIsolationSmokeTests serially. The shared Transit scheme remains the separate future route for ticket suites after explicit parent release.
