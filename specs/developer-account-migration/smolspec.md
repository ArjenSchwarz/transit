# Developer account migration setup

## Overview
Prepare Transit for the owner's selected developer team `4PJS97G236` and a fresh CloudKit destination. Preserve Debug/Release isolation and leave the old identities, stores, installed applications and cloud records untouched. This specification covers reversible source/configuration preparation, not a live data migration or Apple resource registration.

## Requirements
- The system MUST retain the owner's team changes for every project/target configuration.
- Release MUST use bundle `me.nore.ig.apps.Transit` and private container `iCloud.me.nore.ig.apps.Transit`; development MUST use the separate `.development` identities. These identifiers are configuration candidates, not claims of Apple registration.
- Ordinary development MUST remain local-only; explicit development cloud opt-in MUST select only its dedicated container and platform-correct entitlements.
- Both app modes MUST select stable, explicit, disjoint local store locations within their new bundle-identity directories and MUST never open or copy legacy stores automatically.
- Unit/UI tests MUST remain memory-only, with no cloud/counters/automatic listeners; invalid/legacy identities and cross-mode cloud selectors MUST fail closed.
- New app/test IDs, runtime selectors, signing inputs and supported local launch/test scripts MUST agree. CloudKit Development remains explicit; no schema promotion is part of this change.
- Backup format and all nine model schemas MUST remain unchanged. No backup restore, cloud writes, deployment or installed-app launch is authorized.
- Verification MUST inspect the configuration and exercise policy/path selection without live stores. Builds MUST omit provisioning updates and device registration; signing/portal/runtime acceptance MUST be reported separately.

## Implementation Approach
- Preserve the user's `Transit/Transit.xcodeproj/project.pbxproj` edits and substitute app/test IDs using the `me.nore.ig.apps.*` convention already used by team `4PJS97G236` in Asterism and Flux.
- Update `Transit/Configuration/DevelopmentCloud*.entitlements`, `Transit/Configuration/ReleaseMac.entitlements`, and `Transit/Transit/Transit.entitlements`; keep phone/Mac push keys separate and ordinary Debug cloud-free.
- Update `Transit/Transit/Services/AppPersistencePolicy.swift` for accepted bundle/container IDs. Add a Foundation-only store-location selector, reused by `IsolatedPersistenceConfiguration.swift`, so its path rules can be checked without opening a database.
- Route both Release and development configurations in `SyncManager.swift` through the explicit isolated configuration factory; preserve the existing launch-fixed sync preference and allocator factory.
- Store URLs are `Application Support/me.nore.ig.apps.Transit/release.store` and `Application Support/me.nore.ig.apps.Transit.development/development.store`, relative to the supplied Application Support root. Configuration names are `TransitAppsRelease` and `TransitAppsDevelopment`. Tests return memory-only configurations before any directory creation. Invalid cloud selections fail before filesystem work. Directory errors retain the existing configuration-error/fatal-bootstrap behavior; store-open errors retain `ContainerFactory`'s degraded in-memory fallback, never a legacy URL.
- Standard defaults start fresh with each new bundle ID, so backup scheduling/bookmarks are not inherited. App-owned recovery backups use the corresponding new bundle-identity directory's `Backups` child; retry sidecars follow the selected store URL. User-selected export destinations remain explicit user choices.
- Extend `tests/development-isolation/PolicyProbe.swift`, its configuration guard, and focused storage/configuration tests; update relevant scripts/Makefile selectors. Legacy identifiers remain only in explicit rejection/denial tests and historical documentation.
- Update `docs/environments.md` and add `docs/account-migration.md` with portal prerequisites, isolated validation evidence, backup/source freshness, counter floors and follower coordination.
- Dependencies: existing SwiftData configuration APIs, guarded app bootstrap, local backup/restore safeguards, and the user's new-team project selection.
- Out of scope: registration/provisioning changes, credentials, schema changes, live import/wipe, cloud counter resets, app transfer, installation/launch, and Asterism actions.

## Risks and Assumptions
- Risk: a new team alone can still point at legacy storage. Mitigation: new explicit paths and rejection tests, with no legacy fallback.
- Risk: configured IDs may not be registered to the new team. Mitigation: no automatic provisioning flags; report the precise manual registration/association check without claiming it passed.
- Risk: unsigned builds prove compilation, not signed CloudKit access. Mitigation: keep backend acceptance and cutover separate from setup verification.
- Assumption: `.apps.Transit` follows the owner's established new-team naming convention; the chosen account must still authorize those exact resources.
- Prerequisite: the final clean backup stays untouched; known next-counter lower bounds 2507/22 require a current high-water/freshness check before later cutover.

## Acceptance Matrix
| Mode | Cloud | Storage | Verification |
| --- | --- | --- | --- |
| Release | Dedicated Release container, Development environment | Explicit release URL | Project/entitlement guards and unsigned platform builds |
| Debug / optimized TransitDevelopment | None by default | Explicit development URL | Policy/location checks and existing isolated probes where available |
| Development cloud opt-in | Dedicated development container only | Same development URL | Configuration inspection, with no cloud-backed container construction |
| Unit / UI tests | None, no counters/listener | Memory only | Policy/configuration guards; invalid/legacy identities rejected |

Platform entitlement checks cover both phone and Mac inputs. Launch/install scripts receive static selector inspection only; registration, signed access and live cutover remain unverified.

## Escalation Note
This change was scoped as a smolspec. If implementation reveals ambiguity only the user can resolve, an irreversible boundary (public API, persisted schema, auth path), or a contested architectural choice, stop and escalate to the full spec workflow rather than deciding it inline.


## Counter readiness follow-up (specified before implementation)

The owner requested all required setup changes; read-only follow-up found that supported import preserves display IDs but never advances cloud counters. This source-only follow-up adds a Release launch preflight, not permission to execute cutover.

- Release MUST block ordinary UI, intent/MCP writes and startup maintenance until destination/account-bound counter readiness succeeds. Debug/test behavior is unchanged.
- Preflight MUST expose read-only paginated Transit-zone inventory and counter values using the selected Release container/environment; no ModelContext content is changed by inspection. Unknown zones/types, incomplete inventory, account errors and nonempty user graph MUST block initial preparation.
- Preparation MUST be explicitly requested with task/milestone floor inputs at least 2507/22, retaining higher current counter values. Existing CAS advance and read-back verification MUST succeed for both counters before readiness is saved or ordinary writes unblock. A partial advance remains safe/retryable and blocked; no counter rollback or ID reassignment.
- Readiness MUST bind to the explicit team/container/Development environment and opaque iCloud account identity. On subsequent launches, counters MUST be read and verified against saved floors before writes unblock; malformed/missing/wrong-account receipts fail closed. Stored readiness is not evidence of backup import or cloud convergence.
- A missing Transit zone may be created only during explicitly requested counter preparation, never during inspection. The read-only inventory covers Transit's custom zone, not unrelated default-zone data. SwiftData may create mirror infrastructure while opening its gated empty local store; inspection must report this limitation.
- Tests MUST use fakes/disposable receipts, including conflicts, higher counters, readback failures, partial completion, invalid floors/identities, nonempty/unknown destinations, pagination and receipt/account mismatch. No live cloud/store invocation is authorised.


## Approved automatic follower adoption follow-up

The owner approved automatic verification for new devices after the manual follower workaround succeeded. When no local receipt exists, startup MUST use the existing read-only destination/account/inventory and sufficient-counter checks, saving only a local readiness receipt after success. Missing, partial or insufficient counters MUST leave the gate closed without any cloud write; explicit fresh preparation remains manual. An existing mismatched/invalid receipt MUST still fail closed, never fall through to adoption. This follow-up MUST NOT change offline verification policy, schemas, signing, installation, cloud counters or live data. Fake tests MUST prove sufficient fresh-follower adoption and zero zone/counter writes across success/failure cases.


## Approved normal-launch presentation follow-up

The owner requested removal of the saved-readiness setup-screen flash on ordinary launches/force-quit relaunches. While the existing verification is pending, the UI MUST show only a neutral normal-launch loading presentation, not migration/setup text or controls. Successful saved/follower verification MUST proceed directly to normal content. Actual verification errors and unprepared destinations MUST still show the actionable setup/error form. The existing write gate, counter/account/destination checks and online/offline policy MUST remain unchanged. Focused fake regression tests cover saved-ready success, pending presentation and real failure/unprepared presentation. No install, restart, device/live-data access or cloud mutation is authorised.
