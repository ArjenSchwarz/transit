# T63 bundled Settings request for task19

Prepared against subscription RED fixture4366824 and handoff f40dfb3. Task18 remains in progress; this is an owner coordination request, not task19 implementation or a new approval of its gate. Keep the reviewed RED source and its515-input/command pin unchanged. Current queue: T63 corrected13-body RED → T2384 task8 GREEN → T2383 task18 RED → T2382 full-platform work.

## Exact retained file and minimal first seam

T63 remains sole writer of `Transit/Transit/MCP/MCPSettings.swift`. Current recipient SHA256: `c2fe9f43e2283c792a98691d349da34ff7fe5dcb3545e5fb23e2c5a40d1cf062`. Its private broadcaster is the actual object notified by `maintenanceToolsEnabled.didSet`; the handler cannot independently substitute another broadcaster.

Please deliver one getter through an exact single-file owner patch, with pre/post hashes and source commit:

```swift
@MainActor var subscriptionBroadcaster: MCPToolListChangeBroadcaster {
    toolListChangeBroadcaster
}
```

This is a proposed internal getter of the existing type, not a new stream/envelope type or guessed serializer API. It returns the same existing object on every access, introduces no storage, and has no setter. The existing private stored property stays private. Current observer, locked nonisolated availability snapshot, persisted preferences, defaults and init behavior remain unchanged. The accessor can be prepared by T63 independently of task19, but will not be imported into the pinned RED checkpoint before its run. No heavy build is requested for this request preparation.

If T63 prefers a narrow registration forwarding method instead, agree its exact signature after T2383 delivers the request-registration type; do not invent an additional Settings stream engine. The getter is the minimal bridge that compiles against the currently existing broadcaster type.

## Bundle the later compatibility cleanup

Task19 migrates the broadcaster to per-request registrations. Its registration accepts the validated original JSONRPCId, supported requested tools filter and actual channel-close future; same RPC IDs on separate requests remain separate registrations. The router/handler uses the above getter on MainActor. Accepted filters, ack staging, bounded coalescing, prepared notification/complete bytes and SSE delivery stay with T2383's existing owned broadcaster/server paths. Settings continues feeding exactly that object from the same observer. No read capture or admission is added.

The later import must be bundled with removal or migration of legacy source references so every compiled test still builds. Actual current references:

- Settings `createToolListChangeSession`, `toolListChangeNotifications(sessionID:channelClose:)`, `finishToolListChangeSessions` and `activeToolListChangeStreamCount`.
- T2383 handler forwarding and the old server notification response helper.
- T2383-owned `MCPModernBindingTests` availability test still consumes a legacy session stream; migrate its notification observation to the modern request path while preserving all frozen classification/availability assertions.
- The new task18 suites use the existing finish/count hooks for shutdown and cleanup; keep their names as forwarding aliases if useful, with request-scoped semantics and no session state.

T2383 must supply exact final symbols and common commit before requesting a T63 cleanup patch. T63 owns the Settings patch only; T2383 owns its common callers and test migration. Deliver a complete import set together, not a Settings file that references unavailable symbols or a broadcaster that leaves compiled callers broken. Neither retaining old wire/session behavior nor a second observer is part of this request.

## Lifecycle changes outside the Settings file

T2383's owned server hook will finish request streams even when there is no active listener and on current-generation listener exit. Stale generation completion must preserve replacement streams. Existing T63 readCoordinator stop/start, admission transitions, generation ordering, physical permits and the graceful listener release fence remain intact. T63 may review this narrow subscription delta; it is not a request to widen read deadlines or change its publication engine.

## Handoff and evidence

Parent routes this document to T63. Return exact patch/commit, recipient pre/post hash, ownership statement, and any collision with active T63 source. Integration waits task18 meaningful RED and a coordinated common/Settings bundle for task19. Selected task18/19 fixtures must establish ack-first, filters/correlation, no capture/admission, writer failure/disconnect/cancel cleanup, stop/restart/port-change and current/stale listener behavior. No live settings or real-client action is requested here.

## Task19 follow-up owner cleanup

The exact same-object getter was imported in fe497b6. Task19 removes the unsupported session engine from owned broadcaster/handler/transport paths and migrates the old availability fixture. It requires T63's retained Settings file to remove only its two unused forwarding methods: createToolListChangeSession and toolListChangeNotifications(sessionID:channelClose:). Keep subscriptionBroadcaster, finishToolListChangeSessions and activeToolListChangeStreamCount forwarding to modern request registrations; keep the existing availability observer, locked nonisolated snapshot, defaults and persistence unchanged. No transitional create-session stub is proposed.

Exact un-applied proposal: `.codex-cache/task19-subscription-source/settings-legacy-forwarder-cleanup.patch`. Patch SHA256 f86de63a2c649cd05bef62c6a23e72e224c45728838612f669662ed3ace0753a; before SHA25613cc27828c387fe4e62ce987ae593912ae61ae57d0e6096c3a6117f4dfcd3238; proposed after SHA256a9a5be9884ea481747458c70c52683a75a10d30072060564c7b471d1755d0009. Scope is14 removed lines in the two methods. Internal critic recommends exact owner cleanup instead of retaining a fake session namespace. Root will consume an exact T63 handoff; retained Settings has not been independently edited. This is source coordination before GREEN compilation, not a client setting change or activation.
