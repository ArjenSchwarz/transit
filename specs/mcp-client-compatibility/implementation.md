# MCP client compatibility correction

## Scope and decision (2026-11-06, before implementation)

The user explicitly requested a quick backward-compatible correction for direct Codex requests rejected for missing per-request metadata. This is a bounded correction to the existing transport, not a new task workflow. No tickets, deployment, settings changes or bridge are authorized.

Accept metadata-free discovery/list/call requests using empty client capabilities; retain strict validation when modern metadata is supplied. Accept older Streamable HTTP initialize/ping and initialized acknowledgement, negotiating the existing 2025-03-26 protocol. Reuse the modern immutable classification, read admission and protected write paths for every tool call. Preserve Origin/Host, content negotiation, resource limits, duplicate-key parsing, IDs, tool availability and write guards. Supplied headers must still agree with the request. No sessions or legacy GET stream are added.

The existing latest-only contract is intentionally relaxed by the user's request. No separate spec approval or retrospective approval is claimed. Validate metadata-free modern discovery and legacy handshake through the production router plus negative security/protected-write cases and existing modern tests.

## Implementation record

Implemented in the shared validator and router. Missing `_meta` defaults to empty capabilities and no identity; present metadata and mirrored headers remain checked. The existing initialize handler negotiates 2025-03-26 without advertising unavailable legacy tool-list notifications. Tool calls retain the production classification, bounded reads, structured results and protected write coordinator. Modern subscriptions still require their full metadata contract.

Validation:
- `make lint`: passed, zero violations across 767 files (including source-literal/configuration guards).
- `make test-quick TEST_TARGETS='TransitTests/MCPClientCompatibilityTests TransitTests/MCPClientCompatibilityLoopbackTests TransitTests/MCPModernProtocolTests TransitTests/MCPModernRouterIntegrationTests TransitTests/MCPInitializeHandshakeTests'`: passed.
- The loopback test starts the production router on an OS-assigned 127.0.0.1 port with in-memory test storage, sends plain metadata-free HTTP discovery/list/read/initialize requests via URLSession, receives successful results and an empty 202 initialized acknowledgement, then shuts down that test listener. It uses no bridge.
- Existing modern protocol and routing tests remain green; new negatives cover malformed supplied metadata, conflicting headers, unsupported versions, invalid IDs/params, duplicate keys, unknown tools, hostile origins, missing write keys and mutation notifications.
- `git diff --check`: passed.

The initial sandboxed Xcode invocation failed before compilation because SwiftPM could not write its manifest diagnostics cache. No configured Xcode MCP tools were available. The same focused Makefile invocation succeeded with approved build access; no build settings were changed.

Activation remains outside this change: the running Release app/server was not restarted or deployed, Codex settings were not changed, and no ticket was created. Direct HTTP behavior is verified against the temporary server; the installed Codex client against an activated build remains unverified. Unrelated pre-existing `.kiro/` files were preserved.
