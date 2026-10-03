# Deadline feasibility assessment for requirements review

The approved requirement remains a five-second encoded response available to transport for individual reads and read-only JSON-RPC batches. Mixed read/write batches retain the user-approved exception: read result production is bounded but combined delivery may await writes. Checking a timeout only after a blocked MainActor resumes does not satisfy the approved response requirement.

## Source evidence at base 0db453b

- `Transit/Transit/MCP/MCPServer.swift`: `makeRouter` is explicitly nonisolated; its comment states Hummingbird/NIO route callbacks hop to MainActor for dispatch. The POST callback currently awaits `handler.handle`, which is the boundary to coordinate independently.
- `Transit/Transit/MCP/MCPServer+Responses.swift`: `jsonResponse` is explicitly nonisolated and accepts `Encodable & Sendable`, so response construction does not require MainActor.
- `Transit/Transit/MCP/MCPTypes.swift`: request, response, request ID, and MCP tool result are explicitly nonisolated Sendable value types for the NIO/MainActor boundary.
- `Transit/Transit/MCP/MCPToolHandler+TaskQuery.swift`: current query handling fetches synchronously and publishes serialized pages before returning. Adding a timer there cannot bound a blocked MainActor read; the publication path also needs terminal-state checks before retained snapshots become visible.

## Credible architecture to validate during design

A transport-side coordinator can admit a decoded read, establish its deadline and prebuild a small timeout response, then launch an unstructured read worker that awaits MainActor. A one-shot terminal gate chooses the encoded success or timeout. The transport must return the chosen response without waiting for the underlying non-cooperative fetch to finish. A structured task-group race that waits for canceled work at scope exit is insufficient.

The physical unfinished worker remains counted against the proposed eight-operation admission bound until it actually finishes. Queued or running work must not escape accounting during server stop/restart. If timeout wins, the late worker cannot emit another response or publish a caller-visible retained snapshot. Snapshot publication must consult the shared terminal state, not merely a timer on MainActor.

Deadline delivery, fallback encoding, and read-only batch aggregation must stay independent of a blocked MainActor and of any expensive success encoding. The design should assess prebuilt timeout bytes and a short critical section/independent timer executor rather than placing timeout work behind the fetch or encoding task it bounds.

This assessment shows a plausible route supported by existing source isolation, not a completed design or verified implementation. Xcode 27 validation must demonstrate a blocked MainActor still permits the bounded transport response, late work remains accounted for, no late snapshot is published, and read-only batch output meets the shared deadline. There is no source evidence establishing that the approved deadline is impossible.

T2382 must consume the same deadline and capture metadata semantics. Its reusable summary/task-query API/lifecycle is separately owned, but it must not silently weaken the response deadline to a success-admission cutoff.
