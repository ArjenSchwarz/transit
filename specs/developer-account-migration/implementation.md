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
