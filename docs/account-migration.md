# Developer account migration setup

This branch prepares Transit for team `4PJS97G236`, selected by the owner in Xcode before implementation. No Apple resource registration, provisioning update, cloud write, app installation/launch, backup import or live cutover has been performed. The old application, local data and cloud backend remain untouched.

## Configured identities

| Resource | Release | Development |
| --- | --- | --- |
| Bundle/defaults identity | `me.nore.ig.apps.Transit` | `me.nore.ig.apps.Transit.development` |
| Private CloudKit container | `iCloud.me.nore.ig.apps.Transit` | `iCloud.me.nore.ig.apps.Transit.development` when opted in |
| CloudKit environment | Development | Development when opted in |
| Store relative to Application Support | `me.nore.ig.apps.Transit/release.store` | `me.nore.ig.apps.Transit.development/development.store` |
| Recovery backups relative to Application Support | `me.nore.ig.apps.Transit/Backups` | `me.nore.ig.apps.Transit.development/Backups` |
| Default MCP port/name | 3141 / `transit` | 3142 / `transit-debug` |

All app and test configurations retain the owner's team selection. Test IDs use the same new prefix. The source and entitlement files configure these exact names; they are not evidence that the Apple portal has registered them or authorized signed access.

Ordinary Debug stays local-only. `TRANSIT_DEVELOPMENT_CLOUD_SYNC=YES` continues to pair the dedicated cloud entitlement with its runtime startup flag. Optimized `TransitDevelopment` retains development identity. Unit/UI tests remain memory-only with no cloud, counters or automatic listener startup. Neither configuration reads or copies the old default store or `TransitDevelopment/development.store`.

New defaults start fresh: theme/settings, sync preference, MCP enablement, backup bookmarks and scheduled-export preferences are not imported from the old app. Recovery files and retry sidecars also select new namespaces. User-selected backup export folders remain deliberate choices.

## Manual Apple setup before running

1. In Xcode, confirm every project/target configuration still selects team `4PJS97G236`. Open this worktree's `Transit/Transit.xcodeproj`, not the old checkout.
2. Under that team, register or verify the Release App ID `me.nore.ig.apps.Transit` and CloudKit container `iCloud.me.nore.ig.apps.Transit`, and associate only the intended container with that App ID. Enable CloudKit and Push Notifications and obtain the appropriate platform profiles. No automatic provisioning flags were used here.
3. If development cloud access is wanted, separately register/verify `me.nore.ig.apps.Transit.development` and `iCloud.me.nore.ig.apps.Transit.development`, associate them, and refresh the corresponding profiles. Leave ordinary Debug local-only otherwise.
4. Verify actual signed phone/Mac entitlements, including the platform-correct APNs key and Development cloud environment. An unsigned build or source configuration is not signed account/container acceptance.
5. If any proposed identifier is unavailable or associated with another team, stop and choose an available identity with the owner; update the project, entitlements and policy together. Do not silently point the new app back to the old container.

The phone entitlements contain phone APNs/CloudKit keys. Mac networking, bookmark and Mac APNs keys remain in the Mac inputs. These capability requests still require matching profiles; source changes do not grant account permissions.

## Data cutover remains separate

The verified clean backup is `/Users/arjen/Documents/Transit Backups/Transit-clean-20261031T072235Z.transitbackup`, SHA-256 `ea9c38edf8f51127145afb8f769d7ffba55e28df7e27857c4acc4c43bf1769a9`. It represents saved data captured at 2026-10-31 07:22:35 UTC. Recheck newer local/device edits before cutover. The incomplete MacBook is not the recovery authority.

Use genuinely fresh local stores on every joining device. Keep old stores/backups and the old cloud dataset intact; a new container is not an app transfer or an automatic data migration. Quit or coordinate old clients and automation before publication. Import must use the supported recovery/retry protections, followed by restart and independent server/follower convergence verification.

Display-ID counters are outside the backup. Known next-value lower bounds are task **2507** and milestone **22**. Verify current high-water marks or an explicitly agreed safe range before normal writes. The existing counter-advance primitive only advances; this setup neither resets nor seeds any counter. Import alone does not establish these floors. Historical receipt/reservation evidence must not be replayed as new requests.

Schema promotion to CloudKit Production and App Store transfer/distribution are not part of this setup. Keep cloud environment selection separate from Xcode's Debug/Release build label.

## Verification

See `specs/developer-account-migration/implementation.md` for exact checks and their limitations. Policy/path and real SwiftData configuration probes never open a cloud-backed container. Build validation omits `-allowProvisioningUpdates` and device registration. No app was installed or launched.

## Release counter readiness gate

Release checks readiness before task editing, automation or startup maintenance. Routine verification uses only a neutral loading indicator, then opens normal content on success; migration/setup controls appear only for an actual verification error or unprepared destination. Initial verification uses the chosen team/container/Development environment; a durable cloud-active Release store is required. Ordinary Debug and test modes retain their existing isolation.

1. **Inspect destination** reads all pages of Transit's `com.apple.coredata.cloudkit.zone`, applies later deletions and reports physical record counts, unknown zones/types and both next-ID counters. It does not query unrelated default-zone data. SwiftData may create mirror infrastructure while opening the gated store; inspection itself makes no cloud writes. A point-in-time inventory cannot exclude a concurrent writer, so keep other clients stopped during cutover.
2. For an unprepared initial destination, enter explicit next-ID floors (minimum task **2507**, milestone **22**, or verified higher historical values), and confirm the exact displayed container identifier. These minimums do not claim knowledge of the old account's current remote counters.
3. **Prepare fresh destination…** re-inspects the remote graph and checks the saved local graph is empty of user content. Unknown records/zones or nonempty user content block preparation. Explicit confirmation may create the missing Transit zone and increase only `global-counter` / `milestone-counter`, with compare-and-swap retries. Both are read back before any readiness is saved or ordinary writes unblock. Partial success is safe to retry: completed advances are retained, never rolled back, and the app remains gated on failure.
4. A new follower with no local receipt now automatically inspects the selected destination and verifies existing counters against the migration minimums **2507/22**. If sufficient, it saves only a local account-bound receipt and continues; no zone is created and no cloud counter/data is changed. Missing, partial or insufficient counters leave the gate closed for explicit initial setup. **Verify existing counters without cloud writes** remains available as a manual fallback for an already prepared destination or joining follower. It performs the same destination/account/inventory checks and floor read-back, allows known existing user content, and changes only the local readiness receipt. It cannot manufacture insufficient counters. It is not permission to replace an occupied graph.
5. A receipt is bound to team/container/environment and an opaque hash of the iCloud user identity, saved only after both counters verify. Every subsequent Release launch checks the account and counters again before ordinary writes unblock. A missing receipt triggers only read-only adoption; malformed, wrong-account or insufficient readiness remains gated; network failure has no offline bypass. Retry saved readiness after connectivity returns. If sync was disabled, the gate can enable it for the next launch; quit/reopen is required. Readiness records counter preparation, not import completion or cloud convergence.
6. Supported import additionally rejects archived IDs at or above the verified next-counter values. A backup beyond the verified range requires higher counter verification first. Existing recovery archive, replacement, retry and restart safeguards still apply. After a restore the existing mandatory restart remains in force.

No screen or migration code was executed against a live account during implementation. Next operational approval should cover installing/launching this Release build on one primary device and **inspection only** first. Actual counter preparation and backup restore remain separate bounded actions. Check newer edits and agree explicit floors before authorizing them. No old-container deletion is needed for this route.
