# Implementation and verification

## Outcome

Source/configuration setup is complete on `feature/developer-account-migration`. The owner's `4PJS97G236` team settings and Xcode serialization changes were preserved; the only additional semantic project-setting edits are the required bundle identifiers. The migration itself remains unperformed.

Release now selects `me.nore.ig.apps.Transit`, `iCloud.me.nore.ig.apps.Transit` and the explicit new `me.nore.ig.apps.Transit/release.store` namespace. Development selects separate `.development` identities and store; ordinary Debug remains cloud-free. The same guarded configuration factory handles both app modes. Tests remain memory-only; invalid/cross-mode/legacy identities fail closed before directory creation. Recovery backups and retry sidecars follow the new identity/store boundary; old data is never copied or opened automatically.

Phone/Mac signing inputs use their platform-correct keys. The configuration guard exposed Mac-only APNs/network keys in phone entitlement inputs; those keys were removed from phone inputs and retained on Mac. Model schemas, archive format, import logic and counter allocation semantics are unchanged. The clean backup's hash remains `ea9c38edf8f51127145afb8f769d7ffba55e28df7e27857c4acc4c43bf1769a9`.

## Passed checks

- `make lint`: configuration guards, model-container ownership guard, create-task schema guard and strict SwiftLint pass; 753 Swift files, zero violations.
- `make test-development-policy`: compiled Foundation-only launch-policy/location checks pass, including old-ID rejection, exact/disjoint new URLs, recovery namespaces and memory-test modes.
- `make test-development-store-configuration`: compiled against the actual SwiftData SDK; real `ModelConfiguration` checks pass for Release/development paths and cloud-on/off identity stability, cross-container and legacy-cloud rejection, nil group-container selection, memory-test no-directory behavior and unchanged legacy sentinel bytes.
- The configuration probe never constructs `ModelContainer` or a CloudKit connection. Its directories and sentinel are disposable worktree-local fixtures and are removed on completion.
- Changed Python scripts parse successfully; `git diff --check` passes.
- Project comparison against the saved owner-edit baseline proves every team setting remains `4PJS97G236` and all user project semantics remain unchanged apart from bundle-ID substitutions.
- All nine model source files and the archive/capture/restore verification sources match base `0fc88910`; the verified backup is unchanged.

## Initial blocked checks (superseded where noted below)

One unsigned macOS Release build was attempted with `CODE_SIGNING_ALLOWED=NO`, a worktree-local DerivedData/package-cache copy and no provisioning-update/device-registration flags. It stopped during package resolution, before application compilation:

`cannot open file '/Users/arjen/Library/Caches/org.swift.swiftpm/manifests/ManifestLoading/hummingbird.dia' for diagnostics emission (Operation not permitted)`

At that point the protected cache write was not retried, permissions were not changed, and no sandbox-disabling workaround was used. The result is not a successful full app build. Logs are retained in the task folder as `transit-migration-mac-build.log`; passing checks are in `transit-migration-final-checks.log`.

At that point the iOS build and full model/native/store suites were not run after this shared package-resolution blocker. Existing macro-based standalone probes also remain unrun under the earlier macro-helper sandbox denial. That initial validation claimed no signed artifact, installation, app/test-host launch, simulator run, portal registration, actual CloudKit acceptance or counter operation.

## Remaining owner/cutover work

Follow [docs/account-migration.md](../../docs/account-migration.md): confirm/register the exact new App IDs and private containers under team `4PJS97G236`, associate the matching container only, enable required capabilities and refresh platform profiles. Development cloud provisioning is optional while ordinary Debug remains local-only. If a configured name is unavailable, choose an available replacement and update all selectors together.

The follow-up below records the owner-approved build-cache retry and package verification. Runtime CloudKit acceptance remains a cutover check.

Later cutover requires a fresh-change/device-edit check against the 07:22:35 UTC backup, genuinely new destination and local stores, verified counter high-water marks (known next-value lower bounds 2507/22), supported restore/retry protections, and independent server/follower verification. No live import, wipe, cloud writes or account switch is authorized by the implementation record.


## Follow-up: actual phone build failure and approved validation

The owner reported that the attempted phone build failed; installation is not assumed. The recent Xcode activity log `3C09F79E-7A36-4B60-B77A-2C6287DED8D4.xcactivitylog` (2026-10-31 13:42 UTC) identifies `BackupRecoveryFiles.swift:6:44`: `AppPersistencePolicy.Mode` has no member `current`. The migration introduced this invalid default argument. It now explicitly references `AppPersistencePolicy.current`. The focused SwiftData configuration target compiles the real recovery API and its dependencies and checks the Release recovery directory, so this compile boundary is covered.

With the owner's explicit approval, the previously blocked normal SwiftPM manifest-cache write/build was retried once using ordinary Xcode build services. No sandbox workaround, provisioning-update flag, registration, keychain/trust modification, app installation or app launch was used.

- Full unsigned macOS Release build passes (`transit-migration-mac-build-approved.log`).
- Signed macOS Release build passes (`transit-migration-mac-signed-build.log`); strict deep signature verification exits 0 through normal security services. The initial restricted-shell signature/profile readers could not access those services reliably; repeating these read-only checks in the approved normal build environment succeeds. This is not a certificate repair.
- Actual Mac signed entitlements select team `4PJS97G236`, application ID `4PJS97G236.me.nore.ig.apps.Transit`, only `iCloud.me.nore.ig.apps.Transit`, CloudKit `Development` and Mac APNs `development`. Embedded profile matches this App ID/team/container, permits Development/Production and expires 2027-10-31 13:37:55 UTC.
- Signed iOS Release build also passes (`transit-migration-ios-signed-build.log`); strict deep signature verification exits 0. Actual phone entitlements match the same new team/App ID/container and Development environment, with phone `aps-environment=development` and no Mac-only keys. The embedded profile matches and expires 2027-10-31 13:37:51 UTC. These are development-signed Release artifacts, not App Store/Production validation.
- Fresh lint passes with zero violations; policy, configuration guard and recovery-inclusive real SwiftData configuration probes pass. Temporary probe fixtures are removed and no app/cloud container is opened.
- Read-only saved-state check of the old Studio store found no later retained domain history since the clean snapshot; physical counts remain 46 projects / 4,824 tasks / 22 milestones / 9,371 comments. This does not prove absence of unsaved/device/offline edits or remote-only work. Neither new Mac Release store path exists. No independent private CloudKit inventory was performed; container association and package verification do not prove an empty remote destination or successful synchronization.
- The original clean backup hash is unchanged. The old checkout remains at `0fc88910` with its pre-existing untracked `.kiro/` content.

The actual Debug phone target also builds successfully: scheme `TransitDevelopment`, configuration `Debug`, generic iOS device destination (`transit-migration-ios-debug-build.log`). Its strict signature verification exits 0; actual entitlements contain only the new development application/team identity and `get-task-allow`, with no CloudKit/APNs entitlement, as expected for ordinary local-only Debug. Full app-host/model tests, runtime CloudKit sync, counter updates, installation and data migration remain unperformed.

## Counter-preflight implementation follow-up

The required source/setup scope now includes a Release readiness gate. `MigrationCounterPreflight` separates inspection, explicit fresh preparation and read-only adoption of sufficient existing counters. It binds receipts to the selected Release team/container/Development environment and opaque iCloud account identity; each launch re-verifies account and counters. Explicit floor inputs retain the historical minimums 2507/22 without inventing old remote values. Errors, partial preparation, read-back failures and receipt persistence failures leave ordinary writes blocked.

The real existing counter protocol/CAS advance was extracted unchanged from `DisplayIDAllocator.swift` into `DisplayIDCounterStore.swift`. No allocation algorithm, model or archive schema changed. The cloud adapter counts physical record identities across complete zone-change pages and deletions, caps inspection at 100,000 records/1,000 pages, rejects unknown zones/types for preparation and handles missing zones only during explicit preparation. The default zone is outside Transit's storage contract and is not claimed empty. Inventory is a point-in-time check; other clients must remain quiescent for cutover.

`PersistenceAvailability` holds the ordinary-write gate. Startup schema saving, local evidence maintenance, connectivity promotion, MCP listener and scheduled backup startup wait for readiness; task/settings/detail/add windows show the gate instead of editable content. The shared main context's autosave remains off until success. MCP initializes only its local retry scope while gated so its later supported replacement safeguards remain available; mutation entry points still consult shared availability. Supported import rejects IDs outside the actually verified next-counter range. Debug/test isolation is unchanged.

Fake tests compile the actual production preflight, extracted counter CAS extension, inventory accumulator and persistence gate without SwiftData macros or a model/app host. The namespace fixture supplies only allocator error/type names and a container-outcome stub; all counter and readiness behavior under test is real production source. Cases cover inspection without writes, conflicts/retry exhaustion, monotonic higher counters, partial failure/retry, failed read-back, failed local receipt publication, malformed/version/floor/account receipt failures, invalid destination/floors, populated/unknown cloud graphs, adoption without counter writes, import bounds, paginated physical counts/deletions and page-limit failure. No live CloudKit/store calls, installation, app launch, counter mutation or restore were performed.

Verification: `make test-migration-preflight` passes under Swift 6/MainActor, with no app host, model macros or native cloud adapter linked. `make lint` passes: 762 files, zero violations. Existing development policy/configuration guards and actual SwiftData configuration/recovery probes pass. The final changed macOS Release signed build passes (`transit-migration-counter-mac-accepted-build.log`). Final signed macOS and iOS Release packages both pass (`transit-migration-counter-mac-final-artifact.log`, `transit-migration-counter-ios-final-artifact.log`); strict deep signature verification exits 0 on both. Built `TransitSigningTeam=4PJS97G236` and `TransitCloudEnvironment=Development` are asserted on both artifacts, alongside the expected bundle/container entitlements. Artifact inspection caught arbitrary custom `INFOPLIST_KEY` fields not being emitted; both source plists now carry the expanded team/explicit environment keys, with a regression guard. Final checks are in `transit-migration-counter-definitive-checks.log`: lint762/0, Swift 6 fake preflight tests and policy/real-SwiftData configuration probes pass. UI/app-host execution remains intentionally unrun; no claim of real CloudKit acceptance or runtime migration success is made. Account switching during preparation, single-flight rejection and a nonempty local graph are additionally covered with fakes. Deferred Release startup services resume once on successful verification; the local retry scope remains available to the supported import path.


## Automatic follower-adoption fix

A fresh phone reached the manual gate because `verifySaved` returned false before reading cloud counters when its local receipt was absent. Startup now invokes a private read-only adoption path only in that absence case. It checks the existing destination inventory for unexpected zones/types, requires both counters at least 2507/22, then shares the existing read-back/account/cancellation/local-receipt publication logic with explicit adoption. It never calls zone creation, counter advancement or import. Existing receipt decoding/version/destination/account checks remain strict and do not fall through to automatic adoption. Online verification policy is unchanged.

Focused fakes cover a nonempty prepared destination with higher counters, local receipt creation and subsequent saved verification, missing/partial/insufficient counters, inspection/read-back failures, account changes, unknown zones/types, local receipt failure, wrong runtime destination and mismatched existing receipts. Every case asserts zero zone/counter writes. A stale sufficient inventory with an insufficient actual read-back is rejected. No phone/device or live Release data is accessed by these tests.

Validation passes: `make test-migration-preflight` compiles/runs the actual preflight/CAS/gate with fakes under Swift 6/MainActor; all existing and new cases pass. `make lint` passes with 763 Swift files and zero violations (`transit-follower-adoption-verified-checks.log`). Signed generic iOS Release and macOS Release builds pass (`transit-follower-adoption-ios-build.log`, `transit-follower-adoption-mac-build.log`) using existing provisioning and ordinary build caches, without provisioning updates. No installation, app/test-host launch, device access, live Release-store read, cloud mutation or counter preparation was performed during this fix. Existing offline fail-closed policy is unchanged.

The owner can install this feature-branch update from this worktree with `make install-release`. Existing same-identity app data/readiness remain in place; a genuinely fresh follower automatically verifies the prepared cloud destination and records local readiness. The change is committed locally only, not merged or deployed.


## Quiet ordinary-launch presentation

The setup form previously rendered immediately, before its asynchronous verification task started, causing a visible saved-readiness flash even on prepared devices. `MigrationPreflightView` now starts in a presentation-only checking state and renders a neutral progress indicator with the accessibility label "Opening Transit". Successful verification proceeds directly to the existing `onReady` callback; no setup form or readiness text is rendered during checking/success. An unprepared destination or actual verification error reveals the existing actionable form and error message. Retry also uses the neutral checking presentation. Window sizing is preserved.

`MigrationLaunchPresentation` is a small value enum wrapping the existing verification result for presentation tests. It does not change account/counter/destination checks, readiness receipt storage, the shared write gate, deferred startup services or online/offline policy. Focused fake tests cover the initial checking state, actual saved-receipt success without re-adoption/writes, unprepared counters, account mismatch and counter-read failure, asserting setup visibility and the unchanged underlying verification result. No native UI/device/live-data execution is performed.

Validation passes: `make test-migration-preflight` exercises all existing counter/follower tests plus presentation regression cases under Swift 6/MainActor; `make lint` reports 765 files, zero violations (`transit-quiet-launch-verified-checks.log`). Signed generic iOS and macOS Release builds pass (`transit-quiet-launch-ios-build.log`, `transit-quiet-launch-mac-build.log`) with existing profiles and normal build caches, no provisioning updates. The preflight service, persistence gate and app bootstrap are unchanged by this presentation fix. No installation, app/device restart, live-data access or cloud mutation occurred; actual device visual confirmation awaits the user's next install.


## Pre-push review and completeness (2026-11-01)

Four independent native Codex review passes covered the complete 65-file change: code reuse, quality/security, efficiency and spec/documentation. No major findings were raised. Minor findings were fixed: inventory now requests only `nextDisplayId` while counting physical identities/types, independent read-only counter loads run concurrently before the existing account fence, the overview no longer claims the resolved cache blocker, and the current architecture note uses new-account identities. A selectable `TEST_DESTINATION` keeps required simulator runs confined to a disposable device.

### Beginner level

Transit gets a separate data home for the new developer account, preserving the old one. Initial preparation protects task/milestone numbering; joining devices verify the prepared destination without changing cloud data. Normal launches verify quietly, and editing stays blocked only until verification succeeds.

### Intermediate level

One guarded persistence factory selects explicit Release/development store URLs and container IDs; Debug stays local-only and tests stay memory-only. Existing compare-and-swap counters are advanced only by explicit preparation. Account/destination-bound local receipts support read-only follower adoption and normal launch verification. UI presentation hides setup during pending/successful checks without opening the write gate early.

### Expert level

Metadata-only zone-change traversal preserves physical record counts/deletions, rejects unexpected zones/types, and is capped at 100,000 records/1,000 pages. Independent Sendable counter stores are read with structured concurrency, then checked against floors before the existing account/cancellation fence and local receipt publication. Partial CAS success is retryable, higher counters are never intentionally lowered, and import bounds/recovery/retry/restart safeguards remain intact. Inventory is point-in-time evidence, not a global cloud transaction; the default zone and independent follower convergence remain outside its proof. Offline fail-closed policy is unchanged.

### Completeness assessment

The source/configuration migration, counter gate, automatic follower adoption and quiet launch presentation are implemented. Focused fake tests and strict lint pass after the review fixes. Native CloudKit runtime and actual UI appearance are not covered by the fake suite. Required `make test` was attempted on disposable simulator `09BB20FC-4601-4CDA-A7B6-89CE9EC703F0`; compilation reached simulator instrumentation startup, but Xcode could not obtain its analysis task handle. The full run timed out after 600 seconds before tests executed. Normal security-service status reports Developer mode disabled. `make test-ui` was not started after this prerequisite failed. No security setting was changed, no failing check bypassed, and no tracked or untracked source files were changed by the test run. Full required verification and merge remain blocked pending appropriate Mac Developer Tools authorisation.

Post-review focused migration tests and strict lint pass (765 files, zero violations), and signed macOS/iOS Release builds pass for the minor review fixes. The simulator verification blocker is unchanged; passing compilation does not replace the required executed suites.
