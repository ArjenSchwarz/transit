# T-63 requirements critic — first review

Reviewer: independent design-critic subagent applying the actual local design-critic skill. Reviewed the initial requirements draft and contract proposal, read-only.

1. High: per-read production versus complete HTTP batch response is ambiguous. A mixed write can delay delivery despite a produced read result. Define the boundary without changing write behavior.
2. High: multi-entity capture lacks a consistency invariant. An import observed during capture must not relabel previously fetched data as recent.
3. High: excluding a reusable snapshot API may conflict with T2382 acceptance. State pending ownership and compatible common capture semantics.
4. Medium: eight unfinished operations do not bound transient bytes. Define disposal, distinguish transient capture from existing retained-page limits, and test blocked MainActor and slots retained after timeout.
5. Medium: cursor policy omission/conflicts and invalid-input precedence need definition.
6. Medium: refresh outcomes overlap when trigger is unavailable, imports are in flight, failures/successes compete, or little total budget remains.

Questions before design: What response boundary does five seconds cover for batches? What makes the selected multi-entity view coherent? Which ticket owns reusable capture? What bounds lingering work and transient memory? What cursor validation precedence and competing refresh outcome rules apply?

## Draft response for peer validation

- Added separate read-only combined-batch and mixed-batch production/delivery requirements; mixed-batch delivery caveat is an explicit pending user choice.
- Added coherent immutable selected-view requirement and restriction that import evidence must be visible to that view.
- Clarified T2382 shared view compatibility while leaving API/lifecycle ownership to the parent.
- Added slot/data disposal requirement and tests for blocked MainActor and lingering slots. Retained pages keep their existing limits; no transient-byte limit has been approved. The design must disclose that operation-count admission does not alone bound store fetch memory.
- Defined omitted/same/conflicting cursor policy behavior and validation precedence.
- Defined competing refresh outcome priority and shortened wait within remaining deadline.

These edits are draft requirements, not user approval or a claim of proven design feasibility.

## Final critic validation

The same independent critic re-read the final revised requirements after external Codex/Kiro findings were incorporated. It found no new requirements blocker: per-element JSON-RPC admission, outer MCP metadata preserving text payloads, capture boundary, refresh precedence, stable failure categories, and latency evidence are now explicit.

The remaining risks belong at design approval: demonstrate deadline delivery and batch encoding while MainActor is blocked; preserve admission accounting across stop/restart with unfinished work; establish a supported immutable observation boundary and applicable import evidence; keep diagnostics from delaying the bounded response. The 30-second threshold, eight-operation limit, diagnostics, and final requirements remain user approval choices.
