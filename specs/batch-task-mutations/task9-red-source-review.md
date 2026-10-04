# Task9 ordered execution RED source review

Reviewed source: `943a1edc723240b3b4bde5409d64985495da3977`.

Root independently reviewed the ordered-execution contracts, persistent fixtures, declaration boundary and readiness package. Source review is clear for the next exclusive RED run; this is not runtime acceptance or Task9 completion.

## Contract and boundary

The selection contains 30 declarations and 126 planned bodies: 10 synthetic declarations/98 bodies, 13 durability declarations/20 bodies, and seven independent existing-coordinator declarations/eight bodies. The 118 batch-loop bodies are expected to fail at the declaration shell (113 caught boundary failures and five explicit prerequisite diagnostics); eight existing-coordinator controls are expected to pass. Actual compiled discovery and runtime counts remain unverified.

The contracts require ordered committed prefixes, original source text/JSON/optional error preservation, exact original tool/key/UUID binding, replay without live recertification, cancellation at item boundaries, unsuccessful evidence precedence, and no fabricated no-effect claim following a dispatched failure. Mixed status/reason/comment operations, stale or ambiguous targets, domain rejection, atomic status/comment failure, retention expiry, active-key competition, local namespace separation and dirty UI state have substantive assertions.

`MCPBatchTaskCoordinator.run` only throws `notImplemented`. The sole existing policy change declares an optional default-no-op observer; it is not invoked by production code. Task10 must bind the typed pending-edit fact at the actual synchronous dirty-stop branch, rather than infer it from generic uncertainty text or a later context state. Supplemental hints cannot override original receipt evidence. There is no ordered-loop implementation, shared router wiring, write-store change or live operation in this package.

## Fixture lifetime and verification

New fixtures retain independent persistent owners and do not delete backing stores during fixture teardown. Planned runtime creates 29 marked fixture directories. These stores remain until owned processes drain and a matching Task9 cleanup guard is reviewed; earlier Task7/8 cleanup guards do not authorize their deletion. Existing fixture sources remain unchanged.

Root independently verified all 41 readiness hashes: seven owned source files, 17 protected source files and 17 readiness artifacts. Expected case names match the three-suite inventory; declaration/body totals are 30/126. The new Task9 build result, runtime result and selected xctestrun paths were absent. Full lint passed across 452 files; targeted lint, syntax and whitespace checks passed.

Bounded declaration typechecks passed for two sources with an import-only prefix. Four helper/source copies also typechecked against the prior validated module. Root inspected the recorded copy diff: import prefixes plus removal of the new observer initializer argument only in the ignored fixture copy. Consequently this check verifies existing model/service APIs but does not verify the new observer call binding, full app compilation or suite execution. No app-host build/runtime ran during preparation.

The actual existing snapshot comment-capture fault is exercised through a pre-apply preparation hook. A direct commit-phase ModelContext comment-fetch injection seam is unavailable; no store corruption or new production seam was introduced. Earlier read-fault evidence and the synthetic post-dispatch throw complement this case but do not prove direct commit-phase injection coverage.

## Next gate

An exclusive parent START is required for the pinned, serial private Debug build, signed isolated development-host preflight, exact compiled inventory and focused RED runtime. Fail closed on source/hash/configuration/preflight/inventory mismatch or zero matches. Release the heavy slot immediately after owned processes drain, before extended result analysis. Task9 remains in progress and Task10 remains pending until meaningful RED is verified. No new feature approval is requested.
