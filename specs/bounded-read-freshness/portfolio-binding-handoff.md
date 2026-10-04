# T63 portfolio binding seams

Current source integration is `c123210`: the exact six implemented portfolio files from owner `8478b17` are consumed, with all handoff hashes matching. The signatures and frozen-capsule contract below remain authoritative. Earlier scaffold and lightweight-validation statements describe historical interface preparation; owner implementation has separate 54-declaration/61-case verification, while local Stage B and final modern acceptance remain pending. See `routing-integration-plan.md` for current readiness.

## Original capture bytes

Use the existing shared `MCPPreparedReadCapture` from the verified T63 preparation revision. It carries `view` and `frozenMetadataBytes`; do not declare another capsule or reconstruct the bytes from `view.metadata`.

The exact proposal relayed to T2382 for confirmation is:

```swift
handlePortfolioSummary(request: MCPPortfolioSummaryRequest,
                       capture: MCPPreparedReadCapture?,
                       operation: MCPReadOperation) throws -> MCPPreparedToolRead

handleSnapshotTaskQuery(request: MCPSnapshotTaskQueryRequest,
                        operation: MCPReadOperation) throws -> MCPPreparedToolRead
```

Initial summary requires the nonnil capsule supplied directly by the admitted `prepareCapturedRead` transform. Summary replay/continuation requires nil and obtains original bytes, identity, policy and expiry from its retained root. Snapshot task queries retrieve their existing `RetainedView` themselves and bypass live capture/refresh. These replace the earlier view-only proposal, which could not preserve the original byte representation. T2382 confirmation and its concrete handler delivery remain pending.

The transform uses the same `MCPReadOperation` and original admission budget. T63 holds the import observation through private aggregation/encoding/retention preparation, then prepares the actual-ID full response before the common publication gate. T2383's later validated/sealed fragment boundary remains a separate delivery.

## Shared schema definition

Source-only commit `f4e29556feb36dec62e8ebeb7f20b5110a5b6f4b` extends the existing `JSONSchemaProperty` with optional `minimum: Int?`, `maximum: Int?`, `const: Bool?`, and `defaultValue: String?`. The last encodes as `default`. Unset values are omitted, preserving existing helpers and callers.

T2382 can bind limits `minimum = 1`, `maximum = 100`, snapshot comments `const = false`, and initial policy `defaultValue = "refresh_if_needed"`. T2383 consumes this same definition rather than introducing another schema type. T63 retains common schema registration and must merge/replace the query cursor branch rather than append an overlapping alternative. Descriptor registration is not verified by this declaration change.

Patch: `/Users/arjen/Documents/Codex/2026-10-03/task/t63-review-evidence/schema-seam/f4e2955-schema-seam.patch`. Strict standalone actual-source typecheck and lint passed; no app build ran.

## Fault preparation

Source-only commit `1b2e813f154b8dbfd542cb63d4bb66bdac669e1c` exposes the existing MainActor-isolated `MCPReadService.prepareFailure(_:tool:operation:policy:) -> MCPPreparedToolRead`. Existing mapping and payload behavior are unchanged. The admitted portfolio bridge can use it for capture faults before outer encoding, avoiding accidental classification of storage/coherence failures as envelope serialization failures.

Fault injection uses the existing real `MCPReadService(source:monitor:snapshots:...)` and handler `readService` input. A test source conforming to `MCPReadCaptureSource` can throw typed storage, serialization or incoherent-capture errors. No mock shared API or duplicate error mapper is needed. Portfolio request/scope errors retain their own typed handling.

The existing non-query mapper returns plain failure text even though its local selected code is `READ_FAILED`. Integrated fault assertions must verify the intended wire code/category/text and repair any mismatch through the approved RED/GREEN process. This seam does not claim that a machine error code is already present in that text.

Patch and detail: `/Users/arjen/Documents/Codex/2026-10-03/task/t63-review-evidence/failure-mapper/prepare-failure.patch` and `handoff.md`. Strict narrow lint/diff checks passed; no app test, helper wiring or live Transit write ran.
