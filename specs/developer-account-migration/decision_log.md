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
