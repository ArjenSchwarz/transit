# Batch task mutations: implementation explanation

This explanation describes the completed feature-local implementation reconciled onto merged main `adc98b55`. Fresh full macOS and isolated iOS units passed at `b90e6f8`; the complete UI rerun passed at `b8f9fc7` after reviewed fixture corrections, with unchanged production/unit sources. See [publication-verification.json](publication-verification.json) for exact evidence and the retained failed first UI attempt. The owner approved publication and configured Claude review; MacBook client activation remains deferred and is not a merge blocker.

## Beginner Level

### What changed

`mutate_tasks` lets a caller submit a plan containing 1–50 explicit task edits, status changes, or comments in one tool call. Each item names one task and supplies its own retry key. Update and status items also supply the revision they expect to edit. A task can appear only once in a plan.

### Why it matters

A caller can preview a canonical description update and several duplicate closures before submitting them. Preview reads saved local records and describes normalized proposed effects without saving anything or reserving retry keys. Execution processes items in order and stops at the first unsuccessful or unverified result. Earlier successful items remain saved.

### Key concepts

A revision detects edits made since an earlier read. A retry key identifies one exact operation in the originating local store. A retained receipt records the original result, so retrying identical arguments can return that result without repeating the effect. The batch has no shared receipt or all-or-nothing transaction: retrying the batch can replay its completed prefix and continue previously unattempted items.

## Intermediate Level

### Changes overview

The feature lives in `MCP/BatchWrites`. Its parser validates the entire bounded request before privately constructing an executable plan. It preserves original argument spellings for the existing protected write coordinator. A saved-read factory provides a private, autosave-disabled context for preview. The batch coordinator invokes the existing protected operation once per attempted item and advances only after authoritative committed evidence.

### Implementation approach

The optional batch policy guards every relevant shared-context phase. Pending UI edits prevent new acceptance, mutation, save, rollback, or unresolved recovery through that context. Read-only retained terminal replay and key-conflict inspection remain available. Standalone writes keep their default policy. Comment validation is shared with the existing comment service, and status-plus-comment remains one protected transaction.

The batch result is one generated logical source. Every returned attempted-item result retains original text, optional `isError`, and available original JSON separately from the aggregate's classification. Common structured presentation adds task-identity link entries outside that source; the delivered common contract explicitly reports navigation unavailable pending its separate foundation. Before any effect, the handler prepares a complete response containing request correlation and compact original index/tool/key/UUID recovery mappings. Later encoding failure selects those ready bytes without running the encoder again.

### Trade-offs

The bounded list reduces round trips while retaining per-item transactions. It does not provide a CloudKit transaction, automatic duplicate selection, or compensation. Saved-only preview avoids disturbing pending edits but cannot certify imported freshness or future write availability. Existing receipt replay preserves historical results even when the target later changes or disappears; it does not certify current canonical contents.

## Expert Level

### Technical deep dive

Shape validation rejects unknown fields, safety-format errors, wrong JSON types, normalized UUID collisions, duplicate tool/key pairs, and exact caller-ID collisions before any item is attempted. Numeric integer fields are checked from original decimal tokens, avoiding floating-point rounding. Domain strings and conditional status-comment authors retain existing per-item validation semantics. Original UUID argument spelling stays part of T2380 payload binding.

The evidence classifier verifies receipt version, tool/key identity, types, target identity, revisions, terminal dates, and optional error flag before treating an item as committed. Unreadable or unsupported evidence cannot prove no effect. Cancellation is observed between attempts; it does not undo committed effects or turn a caller timeout into observed cancellation. An unstarted item has no acceptance attributable to this submission.

Original retained JSON is inserted through validated raw fragments rather than reparsed through Foundation dictionaries. Missing and null fields, unknown fields, numeric lexemes, and exact original text remain preserved. The common parser's 32-container cap can reject a generated aggregate whose individually readable nested receipts were shallower; that post-effect failure selects the preencoded shallow fallback. Compact fallback excludes giant caller labels, raw records, and entity links. Normal result context may carry explicit task UUID source positions while the prepared fallback context stays link-free.

### Architecture impact

The application batch remains one modern `tools/call`, outside protected single-operation key registration, covered-read admission, snapshot retention, and the five-second read contract. Its router must preserve the original JSON argument subtree before the older `Any` bridge. App-owned services, coordinator, and container are injected; no second receipt engine, guard format, or recovery action is introduced.

### Operational limits

Retry guarantees are local-store and retention scoped. Callers retain original arguments, keys, returned expiries, and original submission time when the first response is lost. Removed or expired receipts do not prove the original effect never happened; a removed key can execute as new under the existing write contract. Unknown commitment requires reconciliation with original keys, never automatic key rotation. A retained canonical update may replay while duplicate closures remain unattempted, so callers needing a current canonical-state condition reconcile it before those closures.

## Completeness Assessment

All 32 approved acceptance criteria are implemented and mapped in the internal spec review. Parsing, saved preview, dirty-context safety, authoritative ordered execution, original-evidence aggregates, complete fallback preparation, real tool registration, app injection, and caller documentation are complete. Fresh finalized verification passed: macOS 2,409 declarations / 3,049 cases; isolated iOS units 1,289 / 1,334; UI 21 / 24. All had zero failures, skips, expected failures, and native runtime warnings, normal exits, and complete owned-process drain. Focused integration 17 / 22 also passed and overlaps the full macOS result; these are not added into a unique total. No matching JUnit/coverage runner was detected for this Xcode project; native xcresult artifacts establish these results.

Modern installed-client compatibility and activation remain unverified and deferred to owner MacBook validation. Common link entries remain explicitly unavailable pending T572 navigation support; this batch does not invent URLs. The later T1734 participating-commit factory is separately coordinated; this feature does not claim a global import fence. External private-diff review, GitHub publication, PR creation, merge, and deployment remain held by the parent's recorded approval restrictions. No production writes, client configuration changes, or installed-app restart occurred.
