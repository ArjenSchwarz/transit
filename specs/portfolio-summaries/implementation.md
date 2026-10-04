# Portfolio summaries implementation

## Beginner Level

### What Changed

`query_project_summaries` reports the recorded workload for the whole portfolio or one selected project. It returns every status bucket, separate idea/workflow/in-progress/nonterminal counts, milestone breakdowns, recent current-record completions, and the newest recorded activity evidence. Empty projects remain visible. Counts describe saved records; they do not claim release readiness or that every workflow task is actively being worked on.

### Why It Matters

An agent can inspect compact summaries without downloading task descriptions or comment bodies. A returned snapshot can then answer task queries against exactly the same saved view, even if live records change. Its original capture time, freshness evidence and five-minute expiry stay fixed across pages and replay.

### Key Concepts

A capture is a consistent copy of saved local records. A snapshot is a temporary retained capture, not a live query. Freshness describes available local import evidence, not CloudKit-wide completeness. Completion windows include their start and exclude their end; they count tasks currently done or abandoned, not historical transitions.

## Intermediate Level

### Changes Overview

`PortfolioSummaryService` aggregates immutable T63 capture values. It attributes records by physical keys, validates the relevant UUID identity closure, and produces deterministic compact counts/activity/diagnostics. The portfolio request parser and snapshot task parser provide strict initial/replay/continuation modes. Snapshot queries support project UUID and effective status filters, summary/full detail and captured canonical revisions, while rejecting comment bodies or scope expansion.

### Implementation Approach

The shared T63 coordinator admits physical reads, evaluates freshness, captures saved values and arbitrates the original request deadline. Portfolio work and encoding operate on detached values. Reusable views use a separate eight-root/16-MiB logical encoded-data budget and immutable index candidates. Successful response encoding and publication are selected together under the shared publication domain; rejection releases reservations and returns typed failure without unreachable IDs.

Prepared modern result fragments are retained by identity. Replay changes JSON-RPC correlation while reusing the exact prepared fragment and original metadata. Read pins validate root identity, original expiry and lifecycle at the completion gate. Seeded router tests compare snapshot task IDs/status counts and completion windows against independently captured records, then mutate saved data and verify frozen replay without another capture.

### Trade-offs

A separate reusable-view store preserves ordinary pagination behavior and budgets. Encoded charges bound logical retention, not total heap use. Scoped capture carries sufficient identity closure to reject attribution ambiguity without broadening reusable query scope. Diagnostics retain exact affected counts with at most ten deterministic samples. Unsupported options fail explicitly instead of reading live data.

## Expert Level

### Technical Deep Dive

Aggregation keeps all eight effective status buckets and reconciles each project's valid milestone, unassigned and invalid-association partitions. Unknown raw task status maps to effective idea; ordinary queries preserve their existing stored-status behavior. Milestone raw/effective status remains independent of task completion. Activity selects the maximum recorded task/milestone creation/status or comment-creation evidence, with deterministic kind, public identity and physical-key tie-breaking. Window parsing restricts accepted precision and emits canonical UTC milliseconds.

Retention construction, page-owner validation, byte comparisons and retirement preparation occur outside the sole completion lock. Per-store changes coalesce into one immutable candidate/version/reservation; all selected stores validate before any swap. Original-operation checkpoints bound cooperative work, while independent deadline arbitration handles noncooperative capture/encoding and retains timed-out physical admission until actual completion. A read pin is not permission to publish after expiry or lifecycle invalidation.

### Architecture Impact

T2382 owns aggregation, reusable-view modules and explicit snapshot query semantics. T63 supplies saved capture, freshness, read budgets, common registration and publication. T2383 supplies latest-only single-object transport and modern provider preparation. Production JSON-RPC arrays are rejected; internal aggregate tests cover atomic publication and protected write receipts without claiming wire batching or a read deadline for mutation calls.

### Potential Issues

The five-second checks measure encoded response availability in the tested runtime, not hard real-time OS scheduling. CloudKit convergence and live signed-store import correlation remain unproved; unknown/unavailable evidence is binding. Corruption-heavy diagnostics and large prepared-owner sets have optional scaling improvements, but no measured deadline failure was established. Installed-client compatibility is explicitly deferred to the user's MacBook after merge.

## Completeness Assessment

Implementation and tests cover all approved portfolio, status, window, activity, identity, snapshot and bounded-outcome criteria. Final native acceptance and exact evidence qualifications are recorded in `integration-acceptance.md`. Temporary interface scaffolding was removed. Runtime verification, local review, publication and push status must be read from that acceptance/handoff rather than inferred from historical prototype or partial console results.

The user approved pushes to the private GitHub destination, external Claude review and overnight merges. PR Pilot proceeds under that approval; earlier paused-gate records remain historical. No client settings, live writes, CloudKit action or deployment were performed.
