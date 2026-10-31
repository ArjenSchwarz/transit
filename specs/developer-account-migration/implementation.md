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

## Blocked and not-run checks

One unsigned macOS Release build was attempted with `CODE_SIGNING_ALLOWED=NO`, a worktree-local DerivedData/package-cache copy and no provisioning-update/device-registration flags. It stopped during package resolution, before application compilation:

`cannot open file '/Users/arjen/Library/Caches/org.swift.swiftpm/manifests/ManifestLoading/hummingbird.dia' for diagnostics emission (Operation not permitted)`

The protected cache write was not retried, permissions were not changed, and no sandbox-disabling workaround was used. The result is not a successful full app build. Logs are retained in the task folder as `transit-migration-mac-build.log`; passing checks are in `transit-migration-final-checks.log`.

The iOS build and full model/native/store suites were not run after this shared package-resolution blocker. Existing macro-based standalone probes also remain unrun under the earlier macro-helper sandbox denial. No signed artifact, installation, app/test-host launch, simulator run, portal registration, actual CloudKit acceptance or counter operation is claimed.

## Remaining owner/cutover work

Follow [docs/account-migration.md](../../docs/account-migration.md): confirm/register the exact new App IDs and private containers under team `4PJS97G236`, associate the matching container only, enable required capabilities and refresh platform profiles. Development cloud provisioning is optional while ordinary Debug remains local-only. If a configured name is unavailable, choose an available replacement and update all selectors together.

A full platform build still needs completion in an environment permitted to use its required SwiftPM diagnostic cache, followed by actual signed-entitlement/account verification. No broader access was requested as part of this source setup.

Later cutover requires a fresh-change/device-edit check against the 07:22:35 UTC backup, genuinely new destination and local stores, verified counter high-water marks (known next-value lower bounds 2507/22), supported restore/retry protections, and independent server/follower verification. No live import, wipe, cloud writes or account switch is authorized by the implementation record.
