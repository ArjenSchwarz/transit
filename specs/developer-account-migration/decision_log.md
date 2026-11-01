# Decisions

| ID | Decision | Basis |
| --- | --- | --- |
| D1 | Implement reversible migration setup on the existing `feature/developer-account-migration` branch. | The owner created the branch/worktree, selected the new team, and explicitly requested all remaining required setup changes. That instruction authorizes this settled setup scope; no separate implementation permission is inferred for cutover. |
| D2 | Use `me.nore.ig.apps.Transit` and its `.development` variant as configuration IDs. | Actual new-team evidence: all 12 Transit configurations use `4PJS97G236`; Asterism and Flux under that same team use `me.nore.ig.apps.<App>`. No Transit registration is asserted. |
| D3 | Preserve the existing CloudKit Development environment in new, separate containers. | The request establishes a fresh destination, not a promotion to CloudKit Production. Production distribution needs separate schema/provisioning verification. |
| D4 | Choose explicit bundle-identity directories for both Release and Debug stores; tests stay memory-only. | Existing development isolation pattern; new namespaces prevent account changes from reusing legacy defaults/global stores. Old files are not migrated, deleted or opened. |
| D5 | Keep counter mutation and backup import outside this setup. | Fresh destination counters must preserve verified high-water marks; 2507/22 are known lower bounds, not permission to reset a live counter. |
| D6 | Use smolspec for the local setup, not the live migration. | Behavior is established by the owner's fresh-destination choice and existing isolation architecture. No persisted schema, public protocol or remote authorization boundary is changed in this work; the local changes can be reverted. |
| D7 | Namespaced app-owned backup recovery locations; fresh defaults/schedules. | New bundle identities intentionally do not inherit settings or bookmarks. Recovery enumeration must also avoid the old global `Backups` directory when Application Support is not sandbox-scoped. |
| D8 | Keep Mac-only APNs/network keys out of all phone entitlements; retain them in the Mac files. | The new platform guard found both APNs spellings in the Release phone input and Mac network keys in the phone inputs. Platform-specific inputs already exist; this is necessary signing-input consistency, not removal of valid Mac capabilities. |

## Document validation

The required clean-context explain-like review produced all three levels. Its four findings (exact path contract, configuration failure behavior, verification matrix, and auxiliary/defaults boundaries) were wording/completeness gaps resolved from existing bootstrap and isolation behavior. None requires a new owner behavior choice. Design critique checked legacy fallback, cross-container acceptance, auxiliary directories, platform push keys, and proof of registration; the settled plan specifies those boundaries and leaves remote acceptance to the manual gate. The owner's implementation request and existing branch name supply the scope/name authorization; no additional cutover approval is claimed.


D9 (follow-up): add code for a destination/account-bound counter preflight under the owner's required-setup request, after confirming import has no counter handling. This supersedes D5 only for source/test implementation; cloud writes and restore remain unperformed and require later cutover approval. Historical floors 2507/22 are minimum inputs, not invented current old-cloud values. Preparation refuses a nonempty or unknown Transit graph; a saved readiness receipt permits later nonempty restored content only after account/counter re-verification. No model/archive schema change is required.

D10: the owner explicitly approved automatic read-only follower adoption ("Yes" to fixing verification without cloud counter/data changes). A missing device receipt now permits inspecting the already-prepared destination; it does not authorize cloud initialization or repair. Existing receipts keep their stricter account/destination checks. No deployment or live verification is part of this code-only follow-up.

D11: the owner explicitly requested removal of the routine readiness-screen flash. Change only presentation while the existing asynchronous check runs: neutral loading, then normal content on success, actionable form on actual failure/unprepared destination. Do not reveal editable content or resume services early; do not alter offline policy.

D12 (pre-push review): address minor payload/launch-latency and stale-documentation findings without changing migration semantics. Add an overridable test destination to isolate required verification from other simulators. Required native testing encountered disabled Mac Developer Tools authorisation; do not change security or bypass the merge gate implicitly.

D13 (native verification follow-up): correct the synthetic MCP readiness fixture to reject both normal Release and Debug listener ports, and assert the configured server identity in discovery tests. The Debug contract remains `transit-debug`; application identity and protocol behavior do not change. The owner explicitly authorised Developer Tools debugging authorisation, which was enabled, but that alone did not resolve simulator instrumentation. Automation Mode is a separate pending authorisation; do not change its authentication policy or waive native/UI validation implicitly.
