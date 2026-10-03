# Task 4: presentation RED draft

Status: drafted in `stream/structured-presentation-1` from verified source base `df3c23b`; focused RED run pending an explicit exclusive test-slot grant. Rune task 4 remains in progress. No task 5 GREEN implementation has started.

Parent confirmed the implementation boundary: `present` now declares `throws` and a default `@escaping @Sendable` original-worker checkpoint. Its declaration-stage body throws `notImplemented`; no category is fabricated for checkpoint failure. Future presentation must propagate cancellation/deadline errors unchanged, without retaining the callback or renewing its deadline.

The confirmed pointer interpretation uses the documented record object position (for example `/record`) and a separate direct relationship token (for example `/record/projectId`). Provider-declared positions may identify documented entity objects or UUID tokens. All lookup is against the same immutable source; no recursive guesses or current-model reads.

Draft fixtures cover:

- Task/project unavailable links, relationship pointers, source array order, duplicate display IDs with distinct UUIDs, record/currentRecord/recordBeforeDeletion, unknown nested IDs, missing/malformed identities, and unsupported milestone identity.
- Provider positions, object ordering and scalar-exact Unicode/escaped JSON Pointer lookup, including composed/decomposed distinct member names.
- Seeded unknown fields, namespace collisions and shrinking while retaining the asserted task identity/deterministic presentation invariant. Source text and validated fragment bytes remain unchanged.
- All finite explicit categories, known historical codes, unknown codes without prose matching, accepted uncertain effects, contradictory retry evidence, original-key versus maintenance reconciliation, source-authoritative rejection retry, and read retry/restart directions.
- Original worker checkpoint propagation, including an error sharing a parser-boundary type, plus repeated checkpoints during a 2,000-record presentation traversal.

Targeted parsing, no-cache SwiftLint and standalone Swift 6/default MainActor typechecking passed, including pure Results/Protocol modules and the new fixtures with Xcode's Testing framework/macro plugin. No app build or test run is claimed.

Queued focused command:

```sh
make test-quick TEST_TARGETS='TransitTests/MCPResultPresentationTests'
```

Only feature-local tests, declaration/comment interfaces, this evidence document and Rune task status changed. Metadata ordering and compact batch fallback tests remain later task 6/7 obligations. Common API task 15 remains undelivered.
