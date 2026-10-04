# T-63 design peer review — architecture and integration

Reviewed the complete requirements, design, design-critic report, explanation, decision log, and both prototype sources/README. This is the architecture/integration/maintainability perspective in the root reviewer's two-peer fallback. The named external MCP reviewers are unavailable and the parent instructed reviewers to respect the external retry denial; this review made no external calls. It is an independent internal peer perspective, not cross-model external validation.

Also inspected existing MCP routing, task-query selection/page retention, T2382's current portfolio design, and `MCPToolHandler+TaskQuery.swift` from merged foundation `201205bd4e786c7f152d8f99006b37da7da888c7`. No production edits, builds, tests, publication, or commits were performed.

## Conclusion

The revised design is suitable for the user design gate. No remaining architecture blocker was found after revalidation of the correction below. Production feasibility remains conditional on the explicitly named history/import, transport, and publication integration checks; the isolated probes do not satisfy those checks.

## Finding resolved during this review

**High: validate-all-before-commit alone did not prevent same-store index overwrite.** Two children in a read-only batch could prepare whole immutable indexes from the same store version. Both would validate before any commit, then the second swap could erase the first child's newly published entries. Atomic response selection would still return IDs from both successes.

The revised shared-publication paragraph explicitly requires coalescing every selected same-store create/append into one aggregate immutable index candidate and combined reservation outside the gate. Independent same-store index swaps are forbidden; validate all aggregate store candidates before any commit, then swap each store once. I re-read that change and consider the blocker resolved. T2382's batch design already calls for an aggregate candidate; the common contract now states why it is mandatory. Verify batching across two creates, two appends to one root, and creates/appends to different roots in the same store, including competing independent requests.

## Critic findings assessed

- **Whole-batch fallback and physical admission:** valid concerns, adequately addressed in design. The small-error deadline probe rebuilds its array after child completion, so it does not validate the revised prebuilt batch gate or assembly-permit transfer. The README accurately limits its evidence. Require real large-candidate/timeout tests and atomic permit transfer; do not reopen this as a design blocker solely because production tests are not implemented yet.
- **Shared transaction domain:** valid concern. A single common lock, staged capacity, validate-all, nonthrowing commits, preencoded rejection responses, and destruction after unlocking form a coherent contract. The correction above was necessary beyond the critic's original revalidation. Each selected store candidate must be composable before the gate; arbitrary publication objects must not introduce hidden independent locking or overwrite behavior.
- **Complete capture evidence:** valid concern. `.completePortfolio` plus canonical revision/full-record/comment validation prevents selected-read DTOs from silently becoming complete summaries. T2382's retained source can return the same immutable capture without fetching live models; its private retained wrapper holds query scope, indexes and publication state. This is compatible with `MCPRetainedViewSource` as a capture-read interface.

## Integration checks and clarifications

1. **Make completeness relative to resolved scope explicit in tasks.** T-63's enum comment says “all domain records”; T2382 supports both portfolio and project captures. For a project capture, completeness means all selected tasks and required relationship/identity/comment closure under the same fence, not every record in every project. Keep the scope frozen in T2382's retained wrapper and prohibit scope expansion. Project selection inside the capture fence closes the identity-resolution race.
2. **Preserve ordinary query behavior during DTO migration.** Current ordinary task filtering and ambiguity/error precedence are established independently of T2382's physical-identity attribution. Physical keys should support the new consumer without silently changing ordinary UUID-based selection, milestone-name matching, identifier outcomes, or no-comment-fetch summary paths. The merged full-task path obtains canonical `MCPRecordSnapshot.task` over comments before stripping public comments; preserve that revision verbatim.
3. **Strong retained ownership must not extend publication validity.** Returning an immutable capture can keep its bytes alive after logical expiry. Root expiry, lifecycle generation, capacity ownership and index version must still be validated under the shared domain at publication. Lookup/replay must observe committed entries only. Test timeout/expiry between lookup and append.
4. **Measure lock work as well as timer work.** Eight root entries bound one dimension, but cursor indexes can be much larger. Preparing/copying indexes, token allocation and discarded-buffer destruction must remain outside terminal critical sections; the final CAS/reference swaps must stay short. The separate 16 MiB stores are logical encoded retention budgets, not heap bounds.
5. **History/import proof is still an early feasibility gate.** Neither probe demonstrates CloudKit transaction completeness or empty-versus-purged history discrimination. Failing closed for capture and reporting unknown freshness are sound fallbacks, but may leave useful reads unavailable on an unsupported store. Surface that measured result before extending implementation around an unproven fence.

## Alternatives and judgment

Prefer a validated portfolio-capture constructor or stronger internal type to eliminate optional full-record evidence after the boundary; retaining one general DTO is acceptable if construction and consumption both enforce completeness. Keep ordinary and reusable retention stores separate to preserve their approved lifecycles, but share publication-domain machinery. A fully serialized retention actor would simplify ownership while risking executor scheduling behind timeout selection; the prepared immutable candidate and short common lock better match the approved independent deadline.

The shared architecture is justified by the requested deadline, frozen pagination and same-view summary/query behavior. Avoid adding a second capture DTO, refresh implementation, revision encoder, or store commit lock. User design approval remains a separate gate; these observations do not authorize tasks or production implementation.
