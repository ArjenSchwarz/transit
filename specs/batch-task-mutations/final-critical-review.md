# T2384 final implementation critical review

Source reviewed: `5c42c7e059e8c810e89d366f0889aef132adf5c5`, including the verified common baseline through `a4a60de579e5a30bc2ad9ff88b6954233f7ff42f`.

## Findings

No unresolved source correctness or approved-scope blocker was identified. Four internal specialist reviews cover reuse, quality, efficiency, and the 32 acceptance criteria. The root independently inspected admission, execution, fallback, provider routing, dependency injection, source preservation, and caller reconciliation rules. Compile-only rich-schema annotations and explicit comment-validator probe dependencies were corrected without changing the intended behavior or weakening assertions.

The fresh finalized macOS result independently establishes 2,409 declarations / 3,049 executed cases passed, zero failures/skips/expected failures/runtime warnings, normal exit and complete owned drain. Isolated iOS unit acceptance independently establishes 1,289 declarations / 1,334 cases; UI establishes 21 / 24, with the same zero-failure/skip/warning and normal-drain conditions. The focused integration result independently establishes 17 declarations / 22 cases passed. Focused and full macOS inventories overlap and are not added into a unique total. Native artifacts were independently inspected by the root.

## Questions examined and answered

1. **Can a malformed later item leave an earlier effect?** Whole-request parsing privately constructs a plan only after all bounded shape/safety/collision checks pass. The modern router supplies original JSON before `Any` conversion; the exact fractional-integer route regression passed.
2. **Can preview or a new batch write flush unrelated edits?** Preview uses a separate saved-only, autosave-disabled context. Optional batch clean-phase policy guards new acceptance and every relevant save/rollback/recovery boundary; retained terminal replay/key conflict stays read-only. Existing standalone default behavior is preserved. The fresh full macOS run includes these safety and standalone regressions.
3. **Can a receipt replay substitute later live data?** Per-item authoritative original text, optional error flag, and available JSON are retained independently. Source serialization uses validated raw JSON fragments; original spelling remains part of the underlying protected operation binding. Modern presentation does not rewrite receipt outcomes or retry direction.
4. **Can aggregate encoding fail after a durable item without a deliverable recovery response?** The complete correlated compact fallback is prepared before dispatch. Post-effect source/encoder failure selects its immutable bytes without re-entering encoding. Root inspected separation of normal task UUID links from fixed fallback context; real route encoding-failure and depth-overflow fixtures passed.
5. **Can an unknown result authorize repeating an effect with a fresh key?** The strict commitment classifier stops on unsupported, uncertain, active, or rejected outcomes. Caller documentation explicitly preserves original keys/store/expiry context, identifies absent receipts as inconclusive, and explains batch continuation and current canonical reconciliation.
6. **Does this expand concurrent read or global-import guarantees?** The batch remains one application `tools/call`, outside protected outer-key registration, covered-read deadlines, read admission, and frozen snapshot retention. No global CloudKit transaction/import fence is claimed. The separately coordinated T1734 participating-commit factory remains a later owner-approved obligation, not an undisclosed batch dependency or guarantee.

## Remaining completion boundary

Completion explanations, overview/changelog and the local HTML archive are prepared; final source-equivalence and clean-tree checks accompany handoff. Client activation is unverified and deferred. External private-diff review, GitHub publication, PR creation, merge, and deployment have not occurred; the parent's recorded approval restrictions remain in force. The explicitly invoked pre-push-review workflow archived the report locally through the inspected Pulsar helper with exit0, without a network request or global settings change. It sent no diff to an external reviewer or forge.
