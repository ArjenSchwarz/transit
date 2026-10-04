# T-63 implementation explanation

This explanation describes the integrated source at `dbf3355d66ab51767fc97ef840dac2ead9c3573b`. Production consumes the verified cumulative T2383 modern transport. The successor to `b8c8194` changes only four detached priorities in one macOS fixture, addressing an observed priority inversion while preserving every assertion. Verification status is qualified below.

After T2383's squash merge, production is already on main. The reconciled T63 branch contains only its unique acceptance tests, fixture repairs and documentation; the explanation below describes the integrated behavior that those tests validate.

## Beginner Level

### What Changed

Covered MCP reads return a complete picture of saved local records with the time that picture was captured. The server has five seconds to prepare its response. It can return a timeout even when a slow database operation continues in the background. Eight unfinished operations are allowed, so repeated retries cannot start unlimited work.

### Why It Matters

A caller can distinguish a recent local capture from evidence of a remote import. The app does not claim remote edits have arrived merely because it recently read its database. Failed database reads produce errors rather than plausible empty results. Continuing a page returns the original picture and its original freshness information; a new initial request creates a new picture.

### Key Concepts

`asOf` describes the saved local capture time. `snapshotId` identifies the captured picture. Freshness describes the available import evidence, which can honestly be unknown. A cursor is a bookmark into that original picture. It does not refresh it or extend its expiry.

## Intermediate Level

### Changes Overview

`MCPReadCoordinator` owns process-lifetime admission, the independent response deadline and physical-work cleanup. `MCPReadCaptureBuilder` copies saved records into immutable DTOs under a history/import generation fence. `MCPImportEvidenceMonitor` and the refresh decision preserve applicable import outcomes separately from local capture. `MCPReadService` prepares projections, metadata and categorized failures. `MCPReadPublicationDomain` couples selected encoded responses with retention publication. Ordinary task pages and T2382 reusable views consume the same capture contract while retaining separate lifecycle policies.

### Implementation Approach

The response timer runs independently of MainActor database work. A 4,850 ms internal cutoff leaves a margin inside the five-second server preparation budget. Timeout selects already prepared error bytes; the physical permit stays held until work actually finishes. Stop/start invalidates unpublished work without resetting unfinished counts.

Saved capture uses a fresh autosave-disabled context and compares persistent-history watermarks before and after copying. No live model or context crosses the executor boundary. Required fetch, serialization or coherence failures preserve `isError` and carry an explicit category. Query failures retain `QUERY_FAILED`; project and milestone execution failures use `READ_FAILED`.

Metadata lives in `result._meta["me.nore.ig.transit/read"]`, outside structured tool data. Retained pages preserve the original metadata bytes and records. Publication validates the entire selected set before committing retained entries, so an error or late result cannot expose an unpublished successful snapshot.

### Trade-offs

The current SwiftData integration cannot prove a remote import applies to the selected capture or request a supported force pull. It returns the approved `unknown`/null evidence and `unavailable` refresh outcome rather than inventing recency. Cached reads bypass import waiting but still capture saved data. Inactive sync reports `not_applicable`. The operation-count and encoded-retention limits bound different resources; neither is a promise about total heap size.

## Expert Level

### Technical Deep Dive

Response selection and physical completion are separate terminal events. A non-cooperative capture can outlive timeout, disconnect or generation invalidation while continuing to consume admission capacity. The strict timer and bounded diagnostic enqueue avoid actor-dependent timeout delivery. Prepared retention candidates, preencoded failure bytes and an atomic publication domain keep success identity consistent with visible retention; stale append versions reject with `READ_BUSY`.

History fencing checks saved-store coherence and is independent of remote-import applicability. Positively relevant import evidence must also be visible to the chosen capture before it can yield `recent_import`. Wall-clock and monotonic age checks prevent a clock change from improving freshness. The last valid applicable success is retained separately from later failures and concurrent outcomes. Canonical task revision/comment evidence uses the merged authoritative record snapshot routine; summary projection does not mint a different revision.

### Architecture Impact

Immutable `CapturedReadView` carries typed scope and completeness. T2382 can reuse the same capture identity and freshness for portfolio totals and task views, while rejecting requests beyond the retained scope. Shared preparation and publication primitives avoid a second freshness service. The integrated modern production route accepts one JSON-RPC object per POST and rejects wire arrays; historical generic batch coordinator tests remain component evidence, not advertised transport support.

### Potential Issues

Explicit retries need backoff and a finite attempt limit because timed-out physical work still holds capacity. Frozen cursors intentionally retain old freshness; callers needing newer records must start a new query. Platform import applicability remains unsupported and must not be inferred from notification arrival, a heartbeat, local save or launch state. Diagnostics distinguish stages but do not prove the cause of unexplained delays.

## Completeness Assessment

Saved capture, bounded response selection/admission, frozen metadata, shared retention publication, categorized failures, modern routing and diagnostics are implemented. Task15's original diagnostics/caller/catalog selection finalized normally: 11 declarations and 19 expanded bodies passed, with zero skips, failures or runtime/global issues. Independent hashes pin the executed source.

Task16 is complete: 23 finalized native selections cover all 2,189 configured declarations exactly once, with 2,425 passing executions and zero failures, skips or warnings/issues. Root independently queried their native test trees and reconciled the full inventory. Five earlier stalled attempts remain excluded and preserved; their cause is unproved. One finalized selection retains its post-body overlap qualification. The repaired publication fixture finalized warning-free on a new signed artifact. See [Task16 acceptance](task16-green-acceptance.md) for precise source, artifact and sequencing evidence. Finalized iOS/UI evidence is reused only under the independently verified unchanged active-source/configuration proof, not as macOS verification.

Live signed-store import applicability is unproved; the honest fallback is implemented. Installed-client compatibility is separately owner-deferred for T2383. No deployment, live-data repair, client activation or CloudKit operation is performed. Parent has now forwarded explicit push/Claude-review disclosure approval; the remaining unique tests/docs are reconciled on merged main for PR Pilot.
