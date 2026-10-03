# Design explanation and self-validation

## Beginner level

### What this does

A read has two lifetimes: how long the caller waits and how long the computer keeps doing the underlying work. The caller gets a result or timeout within five seconds; a slow read continues to occupy one of eight places until it actually stops. This prevents repeated retries from filling an unlimited queue.

### Why it matters

A timeout means the server could not finish the selected read in time. It does not mean there are no tasks, the work was canceled, or the endpoint caught up with every other device. The answer carries the time its local data was captured and only the import evidence the server can support.

### Key concepts

A captured view is an immutable copy of the selected local data. A history fence checks whether a saved change happened while that copy was being made. A freshness caveat tells the caller when remote import evidence is missing; it is separate from whether local data could be read.

## Intermediate level

### Implementation approach

The transport coordinator reserves capacity before queueing MainActor work. A strict timer and one-shot gate live outside MainActor; the physical worker and deadline race over prepared encoded bytes. Store and model access stays in a synchronous MainActor capture; projection uses typed Sendable values afterwards. Publication and the chosen result share the terminal gate so an old worker cannot expose a snapshot after timeout.

### Trade-offs

A fresh autosave-disabled context reads saved state and avoids cached model values or accidentally saving UI edits. Persistent-history token/storeID fences detect a save crossing selected fetches. The user explicitly requires saved data only, so unsaved UI state is excluded. A failed/unsupported fence produces a visible read failure; unsupported import proof produces unknown freshness and valid local data when a coherent capture is available.

## Expert level

### Architecture implications

Physical admission is process-scoped; server generation is a publication/admission epoch, not a reset of active permits. Success bytes and retention capacity are prepared outside the commit lock. For read-only batches the final combined bytes and their publication set commit together; per-element successes cannot publish before selection into the final batch. Mixed batches retain write ordering and the approved delivery exception.

### Edge cases

Default Dispatch asyncAfter timer coalescing exceeded the five-second limit in the isolated experiment; strict timers still need internal response headroom. @concurrent entry and direct continuation completion keep result delivery off MainActor. A saved-store history fence must also cover CloudKit/background changes, while import storeID equality and context visibility need live verification. Same-view T2382 queries preserve canonical r1 from stored/comment-covered content, even when the public status projection is normalized.

## Validation findings

The beginner pass exposed the need to distinguish incomplete physical work from a completed timeout response and the saved-versus-unsaved context choice. Both are explicit in the design. The expert pass exposed batch publication, stop/restart permit accounting, timer coalescing, and import/history applicability; the design records the first three as invariants and the last as an early verification risk with fail-closed/unknown outcomes. No mechanism claims global remote convergence or cancellation of a synchronous fetch.

Outstanding user technical choices are the proposed metadata namespace, internal timer/encoding reserve, fail-closed history fence, and shared separate portfolio retention budget. Saved-only data is explicitly approved. Final design approval must include the design choices; production feasibility remains subject to the named integration checks.
