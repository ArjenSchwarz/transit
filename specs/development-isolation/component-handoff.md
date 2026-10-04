# Conditional component handoff

Status: verified isolation component; one dedicated smoke exception completed. Broader ticket app-host holds remain in effect. Baseline isolation commit fd3650c alone is incomplete. The follow-up AppDisplayIDAllocators correction resolves the constructor gap and its exact offline bootstrap probe passed. T63's exact 46bec7c fix has now been applied and the development build passed. The parent must announce the final verified isolation/fix commits before branches run hosts.

## Integration sequence

1. T63 supplies its narrow owned service patch; containment applies it without replacing TransitApp or read wiring. Containment owns App/project/target/scheme/entitlement selection. T63 retains read-service, routing, publication-domain and coordinator ownership.
2. Containment closes inactive allocator construction and verifies that exact bootstrap helper offline. Preserve the production allocator branch and all domain/write behavior.
3. Run configuration_guard.py, standalone offline isolation harness and build-development-macos in the parent's exclusive slot. Preserve the evidence and report actual results. Passing these gates does not automatically clear app-host holds.
4. Parent publishes the final commit set and explicitly releases each branch's focused host suite. Only then may workers consume the configuration and request their own non-overlapping slot.

For a branch already containing the agreed T63 foundation, the isolation component can be reviewed with:

```sh
git show --stat fd3650c
git cherry-pick fd3650c
```

The cherry-pick is a future authorised integration instruction, not executed by this handoff. Use the final follow-up commit set too; fd3650c alone leaves the review gap. Older branches must first receive the parent-selected foundation. Do not pull the whole containment branch into an older branch blindly or restore complete files from fd3650c. Stop conflicts in App/project files for the containment owner. Preserve branch-specific schema models and handler/server interfaces through a narrow merge.

## Components to preserve

- AppPersistencePolicy and IsolatedPersistenceConfiguration, plus AppDisplayIDAllocators and DisabledCounterStore.
- App mode resolution before any persistence/sync/sidecar construction; selected container plus effective sync false passed into allocators and T63 reads.
- SyncManager cloudSyncAllowed behavior; production Release behavior unchanged.
- Native TransitDevelopment target, its always-isolated identity/flag and CloudKit/push/App-Group-free entitlements. Transit Debug is isolated too. Shared filesystem source groups include new branch files automatically.
- Shared Transit test scheme in Debug with explicit unit-test mode. Every UI launch supplies ui-test; do not rely solely on XCTest class detection.
- Isolated persistent/temporary receipt sidecars and suppressed automatic MCP startup.
- Configuration guard in lint preflight and offline standalone harness. Build commands never install, launch or provision.

## Branch-specific merge boundaries

T63: preserve MCPReadAppDependencies.make, one coordinator from reads.snapshots.domain, and that same coordinator in handler and server. Later constructor changes come through the App owner.

T2382: preserve its portfolio adapters/services and the agreed T63 publication domain. Do not substitute an older handler or App blob to resolve a constructor conflict.

T2383: preserve structured result/protocol changes while retaining isolated startup and the shared read coordinator. New response types are not permission to use a live host.

T2384: retain new batch commands, revision/receipt semantics and schema inputs while keeping sidecars tied to isolated config.url. Never point synthetic probes at historical or current live snapshots.

T1734/T2381: App owner integrates new link/consolidation model additions into the schema list. Do not replace the six-model receipt schema or accidentally omit MCPWriteReceipt. Use synthetic fixtures for graph/canonical/undo scenarios.

## Host-run acceptance boundary

After explicit parent release, use the shared Transit scheme with configuration Debug and the named focused suite, serial execution, a private DerivedData/result bundle and locally resolved packages. The test host must identify as me.nore.ig.Transit.development. Do not use TransitDevelopment as the unit-test scheme: it intentionally contains no test targets. Do not override production identity, entitlements, launch mode or switch to Release to make a failed test invocation work. No install/run targets, app activation, live MCP calls or production store repair are authorised by this component handoff.

Each branch reports its exact command, host identity, suite count, outcome and remaining limits; the parent controls concurrency and Asterism quiet windows. The historical database snapshot is not a current mutation map: the user renumbered some live records afterward.

## Current gate result

T63 immutable fix 46bec7c386624ce755c11940ef58bf046999cb02 is integrated as an exact one-line patch and the development-target build passed. Baseline branches need both fd3650c and that exact T63 fix, plus the verified allocator-bootstrap correction. Do not release app-host holds or copy old App blobs merely because the target now compiles. The correction checkpoint includes BootstrapProbe, refreshed verification evidence and the guarded app wiring. Parent release remains required before any host runs.

## Dedicated smoke command and final component

The focused host smoke now passed: one test, store URL /dev/null, memory-only, effective CloudKit sync disabled, both counter adapters disabled, temporary development-container sidecar. The dedicated TransitIsolationSmoke scheme uses TransitDevelopment directly and compiles only TransitIsolationSmokeTests; it does not compile or run ticket suites. This avoids existing MCP read-test compilation failures in the shared test target, which remain for their owner.

```sh
make test-isolated-host-smoke SMOKE_DERIVED_DATA=DerivedData/isolation-host-fresh
```

Use a fresh unused directory; the runner refuses to overwrite a previous result bundle. Before launch it checks signed identity/entitlements and generated environment/path; app preflight rejects any unsafe configuration before storage construction. No installed app activation, MCP enablement or broad-suite release accompanies this command. The cumulative isolation component patch excludes T63's owned MCPReadService compiler fix; retain that exact fix separately. Integrators T63/2382/2383/2384 must merge narrow App/project wiring while preserving their read domain/coordinator and branch-specific handler/schema behavior.
