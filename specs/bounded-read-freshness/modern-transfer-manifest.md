# Staged shared-file transfer to T2383

Status: prepared for the parent to record an explicit transfer. This document does not transfer ownership by itself. Source/test base: `b1f30256b4fb33270809188131d047a29807f162`; production base is unchanged from `90daf44` and the six-file integration `c123210`. Exact file hashes are in `modern-transfer-manifest.json`.

## Verified base and remaining delta

All 64 MCP/portfolio production files match the owner's tested `b4c104e76a482562bc8eae2ae9f54a6e5712ffc5`. Its four current-foundation router tests passed with signed-host preflight, exit zero and normal drain. Earlier helper verification passed 54 declarations/61 cases. T63's own bounded Stage A passed 14 methods/17 executions, and the corrected expiry gate passed one method/six executions at `7a2f4de`. These remain distinct evidence sets; they do not establish final API15 acceptance.

The two corrected router fixtures are now pinned here exactly. Three of four shared fixture dependencies match. T63's `MCPHTTPTestHelpers.swift` intentionally adds nonisolated execution, optional protocol-version headers and `Sendable` response conformance. It is not replaced by the older owner helper. This scheduling/header dependency is the genuine remaining local-harness delta: run the four fixtures with the retained helper during modern integration verification. Do not claim an identical local rerun, and do not repeat the legacy run merely to match bookkeeping.

The owner's `040da36` handoff confirms the corrected fixture hashes and four passing cases at `b4c104e7`. Additional actual-router expiry verification at `ee053269` passed two cases with normal exit/drain: original frozen metadata/expiry before the deadline, exact five-minute snapshot/cursor errors and no recapture. These are two distinct verified source/run identities, totaling six external Stage B cases, not one combined run or local-harness GREEN. The additional expiry fixture has not been imported here; current-helper/modern integration verification must include it.

## Stage 1: release the adapter writer

After the parent records this exact base and file list, T2383 becomes the sole writer for these ten production files:

- `Transit/Transit/MCP/MCPServer.swift`
- `Transit/Transit/MCP/MCPServer+Routing.swift`
- `Transit/Transit/MCP/MCPServer+Responses.swift`
- `Transit/Transit/MCP/MCPServer+ToolListNotifications.swift`
- `Transit/Transit/MCP/MCPServerDecodeTypes.swift`
- `Transit/Transit/MCP/MCPServerLifecycleConfiguration.swift`
- `Transit/Transit/MCP/MCPToolListChangeBroadcaster.swift`
- `Transit/Transit/MCP/MCPTypes.swift`
- `Transit/Transit/MCP/MCPToolHandler.swift`
- `Transit/Transit/MCP/MCPToolHandler+TaskQuery.swift`

The optional seven-file transport-fixture transfer is separately enumerated and hashed in JSON: route, wire-array, notification, tool-list, origin, lifecycle and startup-failure fixtures. The parent must include them explicitly to transfer them. Read coordinator/capture/retention fixtures, T2382's portfolio fixtures and T2384's write fixtures stay with their owners. The common HTTP and environment helpers remain T63-owned; modern header/helper changes are narrow owner-applied patches.

Genuine entry prerequisites are an immutable clean base, matching file hashes, an explicit parent ownership record, and no remaining old writer for those paths. These are source coordination requirements. The current production files already match compiled, tested owner source; local-harness verification is a later acceptance obligation, not a reason to block adapter implementation. T2383's own required RED/GREEN and current execution-permission hold remain its workflow gates; this manifest bypasses neither.

T63 freezes Stage-1 paths after transfer. Any later read/diagnostic change touching them is supplied as a narrow patch to T2383 through the parent. Preserve the process-lifetime coordinator, original decoded admission instant, non-MainActor classification, listener-generation/physical-drain fences and existing write coordinator behavior. Final production takes one JSON-RPC object per POST and rejects arrays; generic coordinator aggregation evidence remains component evidence.

## Stage 2: compose fragments and schemas through retained owners

T2383 supplies its reviewed real encoder/schema modules and exact ABI. T63 applies any narrow binding changes in `MCP/Reads`, `MCPTaskQuerySnapshotStore.swift`, `MCPToolHandler+CapturedRead.swift` and `MCPToolHandler+PortfolioReadPreparation.swift`. T2382 applies reusable-store/portfolio fragment changes in its own modules. Neither owner recreates or re-assesses frozen metadata. Complete actual-ID response bytes and all failure variants must be prepared before the sole publication gate; charge expanded encoded results and uniquely retained backing while keeping original policy and expiry.

`MCPToolDefinitions.swift` remains T63-owned. API15 output-schema/discovery registration is an immediate narrow owner-applied patch from T2383; it does not wait for T63 task 15 descriptions. A later full definition-file transfer requires its own explicit record. T63 can deliver later description changes as patches without holding up API15 delivery.

Before combined runtime acceptance, align the four portfolio router fixtures' request headers with the delivered latest-only adapter and add the separate source/presentation/exact opaque-metadata assertions. These depend on actual delivered APIs; no placeholder or invented interface is accepted.

## Work that does not block Stage 1

T63 tasks 14/15 diagnostics and caller examples, task 16 full macOS/iOS checks, final pre-push review/Pulsar, unrelated typed-task-link schema work, and test-copy bookkeeping do not gate the adapter writer. They remain required for their own ticket completion. Final task 13/API15 GREEN does require the composed adapter/fragment contract and current-helper runtime verification. Heavy jobs remain exclusive and parent-scheduled; this manifest authorizes no run, live write, client activation, merge or deployment.

App, project, signing, isolation and Makefile files remain with the containment/build owner. T2384 retains its write coordinator and write-specific tests. No blanket branch import or shared-file replacement is authorized.
