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
