# Read-only isolation source review

Reviewed checkpoint: fd3650c65b0e9861fd5c0844ff7cda5d8ea6098b. This review used local source reads only; no source was disclosed externally and no app, test host or CloudKit operation was run.

## Historical blocking finding: isolated bootstrap constructed a CloudKit handle

TransitApp constructs both DisplayIDAllocator instances using the convenience initializer with isCloudSyncActive=false in development/test modes. DisplayIDAllocator.swift:99-106 evaluates its default CKContainer.default() parameter and reads privateCloudDatabase before passing the inactive flag to the designated initializer. Guarded allocation/promotion paths prevent counter RPCs, but do not prevent construction of the production CloudKit adapter. The new target has no CloudKit entitlement, so initialization failure or entitlement handling remains unverified. The standalone persistence harness never constructs the app allocators and does not close this gap.

Before releasing app-host holds, construct inactive allocators with a disabled CounterStore through the designated init(store:isCloudSyncActive:), without constructing CKContainer or CloudKitCounterStore. Keep the production constructor in the sync-active branch only. Extend the standalone bootstrap probe to exercise the exact inactive allocator factory without CloudKit entitlements and with network/live-container denial. This is a narrow app-bootstrap fix, not a change to allocation semantics or T63 reads.

## Paths examined

- Launch resolution runs before SyncManager, store selection and receipt sidecar selection; a development/test production bundle identity is rejected. Debug builds have a distinct identity; test scheme modes are explicit.
- IsolatedPersistenceConfiguration rejects production and returns only cloudKitDatabase.none, explicit development storage or in-memory tests. ContainerFactory fallback is also memory/CloudKit-none.
- SyncManager false allowance short-circuits saved preference loading/default creation, refuses enabling sync and clamps active sync false. CloudSyncBootstrap cannot make isolated sync active.
- App connectivity callbacks and schema initialization are production-only. Counter allocation, promotion and maintenance RPC entry points gate on active sync. The constructor gap above remains material.
- App Intents and entity queries obtain the app's injected services; no separate live ModelContainer constructor was found in those paths.
- T63 reads use the selected container and its single shared domain/coordinator. Its import observer declines subscription when syncActive=false.
- Persistent receipt sidecars derive from selected config.url; test sidecars are unique temporary directories.
- Automatic MCP startup is production-only. Settings still supports explicit manual MCP startup against the selected store; this does not select live storage, but automatic-start isolation is not a global ban on every UI server action. App-host holds continue.
- Production Release remains a deliberate live-storage path. Do not run Release test/profile/archive or reuse stale production xctestrun artifacts as an isolation check.

## Historical conclusion

At the initial checkpoint, do not declare app-host/test isolation ready yet. Resolve the allocator-construction gap, consume T63's owned service-closure fix, pass the build-only gate, and obtain the parent's explicit release of the relevant focused app-host hold. Offline migration cases passed and did not reproduce the CloudKit duplication; root cause remains an inference.

## Bootstrap correction review

The follow-up source review resolves the constructor finding. TransitApp now calls AppDisplayIDAllocators.make with both the resolved mode and effective sync state. Its guard requires production cloud permission and active sync before invoking the CloudKit factory. All other paths construct DisabledCounterStore through the allocator designated initializer. That adapter imports only Foundation, contains no CKContainer/privateCloudDatabase access, and throws on direct reads and writes. The default factory closure constructs the existing production adapter only when invoked in the guarded branch; both production counter record names and allocator behavior are preserved. No read coordinator, domain, schema, receipt or production entitlement changes occur in this correction.

The standalone BootstrapProbe compiles the exact app helper, allocator and production adapter sources. Under network and live-container denial it verifies zero factory invocations for development, unit-test and UI-test with both sync inputs, plus production with sync disabled. It checks both allocator guards, direct disabled-store failure and no promotion/save of a synthetic provisional task. Active production uses a spy factory and verifies both counter names; it does not contact CloudKit. Configuration preflight additionally rejects direct allocator construction in TransitApp.

Offline policy, actual persistence configuration, sequential/concurrent synthetic migration and bootstrap checks passed. The development build-only gate passed with signing disabled, and lint passed (443 files, zero violations). Compiler sandbox remains enabled; every runtime harness child retains network/live-container denial. This review is a local source review, not an independent external review. The original CloudKit duplication remains unreproduced offline. App-host tests and all launches remain held pending explicit parent release.

## Focused host smoke follow-up

A single smoke exception was authorized after the bootstrap correction review. The dedicated target depends on TransitDevelopment, contains only its smoke fixture, and uses the new Debug scheme with explicit unit-test environment. The runner examines built signed artifacts before launch; the exact host path is also checked in-process. AppIsolationSmoke.preflight sits before ContainerFactory and requires memory-only/no CloudKit/no App Group configuration. record inspects the effective container configuration and disabled counter-store types, and validates the sidecar before coordinator construction. Production operation sees these hooks disabled unless the explicit smoke flag is set, in which case mismatched identity/mode fails closed. Memory tests now explicitly use groupContainer.none.

The signed host and runtime smoke passed (one test). Actual store URL /dev/null and memory-only configuration exclude a default or live persistent store through the app's container path. This is configuration/actual-host evidence, not an independent system-wide file-open trace. The exact helper offline spy test remains the evidence for zero CloudKit factory invocations. Installed production application and production entitlements were not changed. Source review and smoke acceptance do not release the broader ticket suites; parent still controls those holds.
