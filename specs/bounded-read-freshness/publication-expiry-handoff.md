# Publication expiry follow-up

The shared source checkpoint is `6de04f60dc5ea1bcd7d2ac7d8403e92af10ec519`. The earlier portfolio wiring checkpoint `226db40` remains separately consumable.

## Error contract

The dispatcher preencodes the appropriate publication-gate expiry response before admission:

| Request | Expiry code |
| --- | --- |
| Ordinary task query or ordinary cursor | `QUERY_EXPIRED` |
| Reusable snapshot task query | `INVALID_SNAPSHOT` |
| Reusable task cursor | `INVALID_CURSOR` |
| Summary initial request or snapshot replay | `INVALID_SNAPSHOT` |
| Summary cursor continuation | `INVALID_CURSOR` |

Busy remains `READ_BUSY`; capacity remains `QUERY_CAPACITY_EXCEEDED`. Error responses retain the actual RPC ID and contain no success freshness metadata or unpublished snapshot/cursor ID.

## Verification readiness

Regression preparation is committed at `11cf1ab`; the mapping correction is `1100799`. One parameterized test declares six cases. It uses the actual ordinary/reusable stores, shared publication domain and coordinator. Advancing the domain clock expires the reusable root while its reservation deadline remains valid. Assertions cover the response code, RPC ID, absent success metadata, zero published/pending entries and bytes, and bounded physical worker drain.

At the unchanged mapping checkpoint, five reusable cases are expected to fail by source inspection. No runtime RED or GREEN has been executed. Strict lint, Swift 6 syntax parsing and diff checks passed; app compilation and the focused isolated run remain pending explicit permission. This regression prepares common publication-gate acceptance; portfolio helper acceptance remains separate.

## T2382 owner handoff

Reusable store reservation can throw capacity before reaching the publication gate. The portfolio helpers must normalize that fault to a `QUERY_CAPACITY_EXCEEDED` machine error. Unknown or expired roots/cursors must become `INVALID_SNAPSHOT` or `INVALID_CURSOR`, without implicit recapture. Passing raw capacity to the common capture mapper currently labels it `storage_failure`, so owner tests must cover the pre-gate fault as well.

Both copied helper bodies remain unchanged `notImplemented` stubs. The descriptor alone now exactly matches owner commit `42d2d82b8596c5a0ac65887f83d25b5bc2bf3613`: one JSON-RPC object per POST, rejected wire arrays, and a distinct `mutate_tasks` application batch. This wording does not establish modern wire implementation acceptance.

Evidence and source-only patches are in `../t63-review-evidence/portfolio-wiring/` outside this repository: `expiry-readiness.md`, `expiry-followup.patch`, `descriptor-modern.patch`, import manifests, lint logs and SHA-256 manifest. The original `source-component.patch` remains unchanged.
