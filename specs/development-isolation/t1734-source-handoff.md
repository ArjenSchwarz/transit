# T1734 independent feasibility isolation component

Prepared on exact owner checkpoint 594c54987146b39257f26b1d152999fb452e8f6b in a separate fix/t1734-development-isolation checkout. The active task-6/transit-t1734 worktree is unchanged. Parent asked for this source-only component for the approved independent task1 feasibility preparation; no task2 CloudKit setup or later graph implementation is included.

Recommended integration: consume this single isolation-only commit, preserving all owner changes. It applies established 9ba4297 isolation through the narrow original-base adaptation from f7cbb04. App/project/startup changes are owned by the isolation owner. App/Makefile/project/SyncManager/Settings inputs match 201205bd; code hunks applied cleanly with no whole-App/project replacement. Existing helpers moved into a same-file extension for the type-length bound. All MCP/read plumbing, models, TaskLinkMigrationTests and TestModelContainer remain unchanged. Actual existing handler/server constructors are preserved; no absent T63 APIs, graph models or schema registration are introduced.

Source checks: git apply --check and git diff --check pass; static development identity/entitlements/unit-mode/guarded-allocator/smoke-target preflight passes. Changed/new isolation Swift files pass strict lint (15 files, zero violations). Required full make lint ran but fails on three pre-existing violations in unchanged TaskLinkMigrationTests.swift: superfluous function_body_length disable at source lines 84 and 134 (reported against declarations 85/135), plus orphaned doc comment at 131. Owner should remove those unnecessary comments; this component does not edit the fixture. Full lint is not claimed green. No build, executable probe, host or test run occurred, and no previous runtime result is claimed for this branch.

After owner consumes this component and fixes its baseline lint issues, parent must grant an exclusive verification slot. Run branch-local offline isolation checks and the dedicated signed-host smoke first:

```sh
make test-development-isolation
make test-isolated-host-smoke SMOKE_DERIVED_DATA=DerivedData/t1734-isolation-smoke-fresh
```

TransitIsolationSmoke uses TransitDevelopment Debug/arm64 and explicit unit-test mode. Its runner verifies signed identity/entitlements and exact host/environment before launch; app preflight rejects unsafe mode/path/memory/CloudKit/group configuration before ContainerFactory. Counters are disabled without constructing CKContainer/default/privateCloudDatabase. Sidecars remain development tmp; automatic MCP and cloud bootstrap are suppressed.

Only after the parent's focused-run clearance, prepare a fresh shared Transit Debug test binary selecting TransitTests/TaskLinkMigrationTests, verify its signed development bundle and derived xctestrun environment/path, and run test-without-building serially. Set TRANSIT_ISOLATION_SMOKE=1 and TRANSIT_SMOKE_HOST_PATH to that verified Transit.app bundle to enforce the startup preflight. Require the intended two declarations/three expanded cases in xcresult: two missing-model capability cases may supply expected RED, plus synthetic disk saved-state control. Zero discovered cases is not evidence. The control is not closed-store migration or CloudKit compatibility.

Live/default data, installed/client activation, MCP enablement, development CloudKit/schema provisioning and production schema remain held. Later foundation/schema/model integration still requires the owner/parent's prerequisite resolution and narrow App-owned patch; this independent isolation component does not declare those foundations ready. Evidence stays local and no routine document delivery is requested.
