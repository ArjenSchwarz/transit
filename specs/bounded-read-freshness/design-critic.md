# T-63 design critic review

Reviewed the proposed design against the approved requirements, decision log, explanation, and isolated prototype sources using the local design-critic skill. This is an internal document review, not design approval or production validation. No tests, external review calls, ticket changes, or production edits were performed by this reviewer.

## Original findings and revalidation

| Priority | Original finding | Revised disposition |
| --- | --- | --- |
| Blocker | Individual timeout bytes did not establish a complete batch fallback; large candidate-array assembly could delay timeout or outlive physical admission accounting (requirements 1.1, 1.3, 1.5). | Addressed in design: a whole valid fallback array is prepared at decoded admission and held by an independent batch terminal gate. Candidate assembly is private; it retains a participating element permit until physically finished. Timeout selects complete fallback without waiting for assembly. Verify the reserved permit transfers atomically and cannot be released between element completion and assembly ownership. |
| Blocker | `MCPRetainedViewSource` exposed lookup but omitted the transaction contract needed to combine T-63 response selection and T2382 retention publication (requirements 1.4, 5.3). | Addressed in design: `MCPReadPublicationDomain`, `MCPPreparedPublication`, and `PreparedReadResult` define a shared lock domain, pending reservations, nonthrowing commit/discard, generation checks, and atomic batch publication. Large destruction is outside the lock. Verify every visibility/capacity/expiry transition follows this domain and that stale append CAS is checked in the same critical section as terminal selection. |
| Blocker | Optional task revision/full-record/comment fields allowed a portfolio consumer to accept an inadequate capture as complete evidence (requirements 4.2, 5.3). | Addressed in design: `CaptureCompleteness.completePortfolio` is required at the aggregation/retention boundary, with mandatory canonical task revision/full-record and complete comment-evidence validation; inadequate capture fails before counting or publishing. Missing required fetches remain storage failures. Verify these invariants are enforced at construction and consumption rather than only documented. |

No remaining design blocker was identified in this revalidation. The revised project-selector fence also closes the separate pre-capture identity-resolution race. Pending-plus-published create/append capacity, immutable index versions, and UUIDv4/v8 routing provide explicit integration rules; they still need implementation tests.

The final publication correction was also re-read: every selected reservation runs `validateLocked` before any commit in the same domain; `PreencodedPublicationErrors` supplies rejection bytes, and rejection discards the entire selected publication set and returns the matching error or batch fallback. No child success publishes before whole-batch selection. This explicitly prevents returning a staged success with an unpublished snapshot/cursor ID and clarifies the atomic CAS/terminal-selection requirement.

## Residual verification risks

1. **Persistent history is not yet proven as a CloudKit coherence fence.** The probe rejects one intervening saved local change, but does not prove remote-import history completeness, concurrent purge handling, or the empty-history sentinel. Test a genuinely empty store separately from nonempty/purged/unavailable history. A store for which the invariant cannot be established must fail with `incoherent_capture`; an alternative mechanism requires the stated design gate.
2. **Import applicability remains conditional.** Verify actual SwiftData history and CloudKit event store identifiers and evidence that the completed import is visible to the selected fresh context. Define/test the monitor's serialized observation boundary so queued event processing is not confused with proof that all earlier callbacks have been incorporated. Until supported, retain `unknown`/null import time and unavailable refresh rather than asserting recency.
3. **The deadline headroom is empirical.** The independent strict timer is supported by isolated evidence; router-return availability and batch fallback preparation are not yet measured in production. Test the maximum permitted request body, large IDs, slow result encoding/aggregation, blocked MainActor, cancellation, and stop/restart. Fallback preparation is included in the admission budget, and no fallback assembly may depend on a timed-out candidate worker.
4. **Shared publication is a concurrency integration gate.** Exercise timeout/success/stop/disconnect races, pending reservation rollback, concurrent append CAS, expiry, and batch commit/discard. Ensure no store lock nests under the domain and no large copy or final destruction runs inside it. Verify unfinished capture/encoding/assembly stays within eight physical operations, including after timeout/restart.
5. **T2380 parity must be checked on the aligned implementation base.** The revised document records PR249 merge `201205bd4e786c7f152d8f99006b37da7da888c7` with the same tree as inspected `b618acf9e3d66a4a1ce493eea94091c058721731`; this reviewer did not independently inspect that merged tree. Preserve its canonical comment-covered r1 in full task views, including omitted public comments and normalized status, and retain its ordinary summary no-comment-fetch behavior.

## Required answers and evidence before implementation completion

- Which atomic ownership transition retains the assembly permit, and do generated race tests prove it is never released early or twice?
- Do append version validation and terminal/publication selection occur under the same domain lock, with reservation discard exactly once?
- Do complete-portfolio construction and consumer validation reject every missing required revision/record/comment dependency?
- What live saved-state/import/history evidence establishes the fence, or demonstrates the documented fail-closed/unknown fallback?
- Do real router-return measurements meet the approved five-second availability contract under the named blocked-actor and large-batch cases?

These are implementation verification gates, not claims that the isolated probes have already answered them. User design approval remains separate.
