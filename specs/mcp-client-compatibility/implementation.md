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


## Durable-session follow-up (2026-11-06)

After activation, the installed Codex 0.167.0 app-server discovered all 17 tools and performed a direct read successfully, but the original durable session still reported `Invalid required per-request metadata`. Native discovery in this engineering task reproduced that exact failure. Source inspection identified the remaining branch: any supplied `_meta` required both modern fields, even when it was an otherwise valid object with one or both fields absent.

A diagnostic-only commit added fixed Boolean field-presence/type labels to that rejection, without client values or traffic logging. The diagnostic build was activated with a recoverable prior bundle. The current task continued to return the old error text, so that result does not establish a fresh request to the diagnostic build. Exact durable request field shapes and a fresh original-session retry remain pending; an absent field is not assumed to have the same meaning as a malformed supplied value.

The follow-up correction defaults absent modern fields even inside an existing metadata object. It preserves validation for every supplied field and metadata key, uses only an explicit version header or the server version for an absent protocol version, and defaults absent capabilities to empty. Complete modern metadata still requires matching mirrored headers. Subscriptions still require both modern metadata fields, valid shapes, and matching headers. Tests cover empty/unrelated/partial objects, wrong types and nulls, malformed nested capabilities, invalid identity/keys, conflicting headers, unsupported versions, and strict subscription admission.

Verification: `make lint` passed with zero violations across 768 files. `make test-quick TEST_TARGETS='TransitTests/MCPPartialMetadataCompatibilityTests TransitTests/MCPClientCompatibilityTests TransitTests/MCPClientCompatibilityLoopbackTests TransitTests/MCPModernProtocolTests TransitTests/MCPModernRouterIntegrationTests TransitTests/MCPInitializeHandshakeTests'` passed all six suites, including isolated HTTP discovery/list/read with partial metadata. `git diff --check` passed. Release activation and fresh durable-session confirmation are reported separately after installation; the installed CLI result alone does not establish original durable-session compatibility.
