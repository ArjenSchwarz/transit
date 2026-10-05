# T-2384 Requirements Review

Status: requirements approved at Sentinel_35dae4e67398819184369b41649ec75b, including final transport clarification in 9b5122c. This records the requirements review; design/tasks/implementation remain separate gates. Scope/name were approved in the parent at `Sentinel_4fd40b3fecf48191a57ce03897d3e7ec`; design/tasks/implementation remain unapproved.

Review [requirements](requirements.md) and [decisions](decision_log.md). The approved scope led to the normal workflow status change to Spec with its comment; the live MCP result confirmed commitment. No production implementation or heavy tests have begun.

## Proposed behavior

- A single domain tool call supports 1–50 explicit task updates, status changes with optional reason/comment, or standalone comments.
- Tasks use UUID selectors; one operation per normalized target UUID per batch. Same-task property plus separate comment edits require another call. Standalone comments retain their current lack of revision checking.
- Dry run validates every item's current local state, returns proposed normalized effects and diagnostics, and touches no domain/receipt/guard state or pending edits. Retry-key state is explicitly unchecked.
- Execute commits items in order, advances only on authoritative understood commitment, and stops after the first unsuccessful/unreadable result. Remaining items are not_attempted; earlier successes remain committed.
- Explicit item keys retain T2380 local-store/tool binding, exact original operation arguments and replay windows. There is no durable outer batch replay. An identical batch retry can recover earlier commits and continue with unstarted items.
- T2383 supplies the approved transport-neutral result adapter; original receipt text, unknown fields, missing/null distinctions, saved revisions, item isError and retryAction remain authoritative. T2384 adds no transport migration.

## Recovery limits to review carefully

A preview is not a reservation. A matching-key submission may replay a historical success even when a current-state preview is stale or the target was deleted. Replaying a canonical update does not prove its current contents still justify closing duplicates; callers requiring that condition must reconcile the current canonical task before submitting new closures.

A lost response does not prove no effects. Retain original requests/keys and any returned expiry. If the first response was lost, retain submission-time context and reconcile when the replay guarantee cannot be established; missing or removed receipts do not prove the original effect never occurred. Expired removed keys can execute anew under T2380. Unknown commitment never warrants a fresh key.

## Critic and independent peers

Mode: **internal peer fallback**, explicitly authorised for this work. No external model/service disclosure occurred, despite PERSONAL_PROJECTS=1. The local design-critic ran first, followed by two independent peers applying the documented peer-review-validator method: correctness/recovery and API/architecture. Their perspectives are internal agents rather than distinct external models.

The critic identified five issues, all incorporated:

| Finding | Requirements resolution |
| --- | --- |
| Unknown/unreadable outcomes could allow later writes | Only understood authoritative commitment advances execution; unknown result stops without fabricated receipt state. |
| Historical item isError omitted | Preserve item flag separately from aggregate flag. |
| Transient results described as durable outcomes | Do not promise terminal retention for transient rejection/in_progress/uncertain responses. |
| Shape/domain failure boundary ambiguous | Whole-request rejection for type/safety/structure errors; individual failure for invalid domain values or missing status-comment author; diagnostics include indexes. |
| UUID normalization could change key binding | Normalize only collision detection/mapping, preserve original operation arguments. |

Both peers agreed with these resolutions. The API peer additionally required lossless unknown-field/raw-text preservation. The recovery peer required unknown-expiry guidance and the historical-canonical caveat above. These were incorporated. There was no unresolved divergence or blocking peer finding; the user still owns the proposed behavior choices.

## Validation and coordination

The requirements contain six one-line stories and 32 unique EARS acceptance criteria with granular anchors. A source-level document check verified anchors, keywords, Markdown line breaks and clean whitespace. This is document validation, not implementation testing. Requirement 6 defines the eventual meaningful automated scenarios, including failures after commit and historical replay parity.

T63 remains sole writer of MCPServer/MCPTypes/common dispatch/schema wiring until coordinated handoff. T2383 confirmed historical T2380 results are authoritative and shared serialization must not override retryAction or reread live state. T2383 reported approved latest-only 2026-07-28 scope; its requirements and concrete adapter remain under their own approval gates. T2384 does not require legacy JSON-RPC arrays. Historic unknown-key collisions must not be overwritten by supplemental classifications or links; installed-client migration readiness remains a separate reported blocker. Approved T63/T2382 specs were inspected read-only; frozen cursor revisions and comment-covered canonical r1 remain protected. No T2381 dependency is introduced.

## Requirements gate (closed by explicit approval)

**Do the requirements look good or do you want additional changes?**

Approval includes the proposed 50-item bound, UUID-only targets, one operation per task, stop-on-first-unsuccessful execution, receipt-blind advisory preview, standalone-comment precondition behavior, and the replay/continuation limits above. The parent can collect changes before approval. Design starts only after explicit requirements approval; task approval and implementation authorisation remain separate.
