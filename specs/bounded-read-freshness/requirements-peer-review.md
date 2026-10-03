# T-63 requirements peer validation — final synthesis

The required external Codex and Kiro consultations both completed successfully (exit 0) after the first design-critic review. Successful raw reports are [Codex](peer-codex.md) and [Kiro](peer-kiro.md). They reviewed the supplied launch packet, not the later revisions. After the parent’s final critic reported no new requirements blockers, this peer reviewer read the revised requirements and validated the dispositions below locally; no external consultations were repeated.

## Finding dispositions

| Finding | Final disposition |
| --- | --- |
| Universal transport promise conflicted with mixed-batch exception | Resolved by 1.1 qualification and 1.5; direct user approval permits mixed reads’ production within five seconds while combined delivery waits for writes. External reports’ pending-approval language predates that approval. |
| Combined encoding deadline and batch admission undefined | Resolved at requirements level: 1.5 includes aggregate serialization and affected-read timeout fallback; proposed contract distinguishes JSON-RPC batch elements from one task-query batch operation and defines received-order slot admission with a common decoded-batch timestamp. Design must prove fallback encoding meets the same deadline. |
| Inactive-sync refresh outcome and assessment timestamp undefined | Resolved by 3.4’s not_requested under either policy and 2.2’s assessedAt fixed to original asOf. |
| Additive metadata could change array payload shapes | Resolved by 2.1: outer MCP result metadata preserves existing text-content data value and shape, including empty results. Exact field placement remains design work within the approved compatibility boundary. |
| Coherent/relevant view lacked observable meaning | Resolved by 2.6’s immutable local observation boundary with each completed saved change wholly represented or absent; inability to establish it yields incoherent_capture. 2.4 and 3.6 require import applicability to the running store and capture. Supported SwiftData/CloudKit proof remains a design gate. |
| Storage/encoding/coherence failures lacked stable categories | Resolved by 4.1’s storage_failure/serialization_failure versus incoherent_capture, timeout, busy, and input/cursor categories; caller documentation maps categories to compatible tool error codes. |
| Refresh interval, in-flight events and zero wait unclear | Resolved by 3.6: decision-through-bounded-wait observation, relevant pre-existing imports, explicit zero-wait outcome, and total READ_TIMEOUT precedence. |
| Eight operations described as broad resource bound | Resolved wording: admission bound explicitly excludes total transient-memory bound. Design must disclose large captures and indefinitely occupied slots rather than invent further unapproved limits. Eight remains proposed. |
| Unknown 30–50 second latency lacked useful evidence | Addressed by proposed 6.3 server stage-duration diagnostics with correlated late completion/discard. This is an explicit pending requirements recommendation, not approved instrumentation or a claim that CloudKit caused the incident. |
| Stale approval/ownership records | Resolved in current proposal and decision log, whose headings now distinguish Approval record and Pending requirements choices. Full-spec type approval remains separate from final requirements approval. |
| Cursor policy/precedence and T2382 ownership | Both external reviews found these resolved. 5.1–5.4 preserve original view metadata; T2382 owns reusable external API/lifecycle while T-63 preserves shared capture identity. |

## Final assessment and remaining gates

No additional requirements wording blocker was found in this final local validation. The 30,000 ms import threshold, eight unfinished-operation admission limit, diagnostics recommendation, and complete requirements still need user approval in the parent conversation. The previously approved budgets, additive metadata, default policy, deferred tools, mixed-batch exception and saved-snapshot sharing must not be reopened as unresolved choices.

The final critic’s remaining design risks are valid: independent deadline/batch error encoding despite a blocked MainActor; slot accounting across service stop/restart while old work remains unfinished; a supported immutable capture/import visibility boundary preserving saved local-write visibility; diagnostics that cannot delay bounded results. Current requirements describe required outcomes, not proof of feasibility. These must be resolved with design evidence before implementation.

## Consultation evidence and safeguards

Both initial restricted attempts failed before analysis (Codex app-server initialization; Kiro auth portal). Supported scoped per-command escalation allowed actual consultation without changing global permissions. Codex retained read-only sandboxing; Kiro used zero trusted tools; neither reviewer used tools. The parent supplied direct user approval to share both tickets’ spec documents, findings and relevant repository excerpts with Codex/Kiro (Sentinel_7ba5dca061b4819183c1d6066aa1e949).

Raw CLI logs, failed reports and the exact launch prompt are preserved outside Git/specs in `/Users/arjen/Documents/Codex/2026-10-03/task/t63-review-evidence`: `peer-codex-initial-failed.log`, `peer-kiro-initial-failed.md`, `peer-codex-escalated.log`, and `peer-prompt.txt`. They contain local auth/session initialization details and must not be committed, published or sent to the phone. Only successful external reports and this synthesis remain review deliverables in the spec folder.

This reviewer made no source changes, builds/tests, ticket changes, commits, phone sends or publication. There is no remaining external-consultation blocker. Parent owns user synthesis, phone delivery and the final approval request.
