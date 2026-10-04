# T1734 schema registration: narrow T63 agreement

Reviewed inventory: `tests/typed-task-links/schema-registration-inventory.md` and its unapplied patch on the T1734 branch, inventory source `4459a964`. The parent verified task-1 local RED at `eaf5f461`; task-2 model/schema source follows the approved DAG. This review applies no factory patch or model definition.

T63 grants the schema-list-only addition in `Transit/TransitTests/TestModelContainer.swift`, default `init()`: append `TaskLinkOccurrence.self` and `TaskLinkRemovalEvidence.self` immediately after `MCPWriteReceipt.self`. No competing fixture edit exists. The two real definitions are committed in T1734 `794c155`; the application dependency is satisfied. The designated T1734 worker may apply that exact hunk now on its isolated branch at `e547e55` or its descendant. This is not a whole-file handoff and does not authorize editing the active T63 worktree.

Preserve the current UUID-named configuration, in-memory store, CloudKit `.none`, owning lifetime/retained containers, context construction, custom-schema initializer, rollback helper and counter fixtures. On later component integration, T63 applies the same list-only addition against its latest file after consuming the model definitions; it does not replace the fixture from the inventory checkpoint.

T63's `MCP/Reads` files consume an injected container and contain no model-container factory requiring this registration. No capture, history fence, canonical revision, snapshot, freshness or admission code changes belong in the registration patch. `ContainerFactory` already accepts its caller's schema and needs no extra registration.

Containment has already approved/applied the App and Makefile list additions in T1734 `55c88fa`. The remaining five paths outside T63's ownership are `Transit/TransitTests/MCPWritePersistenceProbeTests.swift`, `tests/mcp-write-probe/ServiceProbe.swift`, `CoordinatorProbe.swift`, `FoundationProbe.swift` and `Probe.swift`. Route those five list-only hunks to their write/probe owner; T63's one-path grant has no remaining ownership dependency. The probe `seed-old` five-model branch, six-entity pre-feature disk fixture and intentionally graph-free isolation migration fixture stay unchanged.

Application order is definitions first, owner-applied registration hunks second, then local schema/migration verification under a separately assigned exclusive test slot. No source application here, competing tests, real CloudKit account/schema operation, client activation or live-data mutation is authorized.
