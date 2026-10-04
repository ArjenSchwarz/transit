# Proposed task 2 registration ownership split

Source checkpoint: `4459a96451588266c6b13c3475bac5a3243c9cc3`, branch `T-1734/typed-task-links`. The adjacent `pending-schema-registration.patch` is a review artifact only; it has not been applied. Ownership agreement is pending. Owners must adapt these narrow additions against their actual latest integrated source rather than replace files from this checkpoint.

| File / context anchor | Minimal proposed change | Proposed coordination |
| --- | --- | --- |
| `Transit/Transit/TransitApp.swift`, `init`, `let schema = Schema([` | Add the two model types after MCPWriteReceipt. No initializer, persistence-mode, CloudKit, allocator or server changes. | Containment/App owner applies or explicitly hands off this schema-list hunk. |
| `Transit/TransitTests/TestModelContainer.swift`, default `init()` | Register both model types in the default schema. Keep owning retention, custom-schema initializer and CloudKit `.none` unchanged. | Parent-designated common-fixture owner confirms the exact list-only handoff; T-63/containment coordinate current integrated source. |
| `Transit/TransitTests/MCPWritePersistenceProbeTests.swift`, computed `schema` | Add both models to this current receipt/task schema; no fixture lifecycle changes. | Parent confirms test-file ownership. |
| `tests/mcp-write-probe/ServiceProbe.swift`, `main`, literal schema | Add both model types; keep storage and service construction intact. | Parent-designated MCP write-probe owner confirms list-only handoff; do not infer T-63 ownership. |
| `tests/mcp-write-probe/CoordinatorProbe.swift`, `main`, literal schema | Add both model types; no coordinator or receipt logic changes. | Parent-designated MCP write-probe owner confirms list-only handoff; do not infer T-63 ownership. |
| `tests/mcp-write-probe/FoundationProbe.swift`, `receiptStorage`, literal schema | Add both model types to the receipt-storage schema. | Parent-designated MCP write-probe owner confirms list-only handoff; do not infer T-63 ownership. |
| `tests/mcp-write-probe/Probe.swift`, `if mode != "seed-old"` | Append both models only inside the existing nonhistorical-mode branch, alongside MCPWriteReceipt. Preserve the historical five-model seed-old branch exactly. | Parent-designated MCP write-probe owner confirms mode-specific handoff; do not infer T-63 ownership. |
| `Makefile`, `MCP_PROBE_MODELS` | Add the two definition filenames to the existing standalone compiler source list. No commands, flags, targets or run policy changes. | Makefile/probe owner coordinates this compile-list hunk. |

T-1734 proposes to own new `Models/TaskLinkOccurrence.swift` and `Models/TaskLinkRemovalEvidence.swift` only after the task 1 boundary and ownership split are resolved. The approved shape has defaulted scalar UUID/String/Date storage, explicit UUID/time construction, programmatically immutable identity/endpoint/kind fields, and no relationships, cascades, uniqueness or validation shortcuts. No model definitions are included in this patch.

The schema list changes require those real model definitions. Applying the patch without them causes compilation failure and supplies no runtime migration evidence. The existing current-schema RED is not an implementation substitute.

The six-entity `TaskLinkPreFeatureDiskFixture`, five-entity `Probe.seed-old`, and intentionally graph-free development-isolation migration fixture remain unchanged. `ContainerFactory` receives its caller's schema and needs no registration change. JSONSchema is unrelated. This patch neither changes the snapshot/revision contract nor grants access to an owner’s other shared files.

Task 2's disk migration and separately cleared development CloudKit schema/deletion evidence remain required before dependent work. These proposed source additions authorize no build, runtime probe, client activation, schema initialization/promotion or live record mutation.
