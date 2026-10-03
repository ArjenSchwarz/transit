# T-63 decision log

## Quick decisions

| Date | Decision | Rationale / authority |
| --- | --- | --- |
| 2026-10-03 | Work on dedicated `T-63/bounded-read-freshness` branch/worktree from `0db453b` | Delegation explicitly requested isolation and allows branch commits; scoped Git administration escalation succeeded. |
| 2026-10-03 | Preserve all other work, including T2380 | Explicit delegation; inspected separate branch/worktree without editing it. |
| 2026-10-03 | Keep feature name, wire shape, budgets, default policy, refresh tool scope, and cross-ticket snapshot ownership pending | These affect caller behavior and shared T2382 contracts; no approval of unseen proposals was supplied. |
| 2026-10-03 | Do not implement or change ticket status before first approval | Actual creating-spec phase gate; requirements skill also requires a name answer. |

## Approval record

| Date | Decision | Rationale / authority |
| --- | --- | --- |
| 2026-10-03 | Full scope, full spec type, and `bounded-read-freshness` name approved | Parent conveyed direct user statement: “Both tickets scope, spec type, and name are approved” (Sentinel_3ccdbb1152c88191b673f3dde9f76e60). |
| 2026-10-03 | Ticket moved to `spec` | Actual creating-spec transition after scope approval; committed Transit revision `r1:aaaffbb389d4c805f835e3b64bb78731f83e85030897c8e7956c8154b42f31ea`. |

| 2026-10-03 | Preserve existing data payloads with additive freshness metadata; default refresh_if_needed; 5,000 ms total / at most 2,000 ms refresh limits; defer separate refresh tool and maintenance reads | Parent conveyed direct user reply “That's fine” (Sentinel_6b71cb52cf10819190043fb6ad347713 replying to Sentinel_c62cd3e9da0c8191aedc90e0eb304f6e). This reply did not approve the 30-second recency threshold or complete requirements. |

| 2026-10-03 | Summary and detailed task queries may use the same saved snapshot; T2382 owns its external API/lifecycle, T-63 shared capture/freshness supports retained identity | Parent conveyed direct user “Sounds good” (Sentinel_5479ed38c0cc8191a7c47a6487b6c0a1) to same-snapshot reconciliation proposal, and assigned ownership. The same reply approved T2382 legacy count preservation/separate counts; those count requirements belong to T2382. |

| 2026-10-03 | Individual reads/read-only batches have a five-second response limit; mixed read/write batches produce the read result within five seconds but delivery may wait on writes | Parent conveyed direct user “That's acceptable” (Sentinel_a44f8dbe8f1c8191a055e45169b5e685) replying to that exact distinction. Preserves write behavior without claiming an overall mixed-batch delivery deadline. |

## Pending requirements choices

The requirements draft additionally recommends a 30,000 ms recency threshold, eight unfinished reads as an operation-count admission bound, and server phase/late-completion diagnostics to investigate the ticket's unexplained latency. Final requirements and exact metadata/error semantics remain pending. Requirements, design, and tasks approvals remain separate gates.
