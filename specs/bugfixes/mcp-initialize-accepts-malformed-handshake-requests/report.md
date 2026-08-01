# Bugfix Report: MCP Initialize Accepts Malformed Handshake Requests

**Date:** 2026-08-02
**Status:** Fixed

## Description of the Issue

Transit returned a successful MCP initialize result without reading the request parameters. Requests that omitted or malformed the protocol version, client capabilities, or client implementation information therefore completed as if they were valid handshakes.

**Reproduction steps:**
1. Send an `initialize` JSON-RPC request with no `params`, array `params`, scalar/null `params`, or malformed required object fields.
2. Observe Transit's MCP response.
3. Before the fix, the server returns a successful initialize result advertising protocol version `2025-03-26`; correct behavior is `-32602 Invalid Params` for method-parameter errors and `-32600 Invalid Request` for scalar/null top-level `params`.

**Impact:** MCP clients could establish a session without negotiating version compatibility, capabilities, or implementation identity, violating the advertised MCP 2025-03-26 lifecycle contract.

## Investigation Summary

The handler dispatch, protocol wire types, existing tests, implementation history, MCP server notes, and MCP 2025-03-26 lifecycle specification were inspected.

- **Symptoms examined:** Parameterless and malformed initialize requests succeed; the response version is hard-coded.
- **Code inspected:** `MCPToolHandler.handle`, `MCPToolHandler.handleInitialize`, `JSONRPCRequest`, MCP initialize result types, test helpers, and existing MCP handler tests.
- **Hypotheses tested:** JSON decoding already enforced handshake parameters (ruled out because `params` is generic `AnyCodable`); another layer negotiated protocol versions (ruled out by repository search); the hard-coded response was sufficient (ruled out because supported requested versions must be echoed).

## Discovered Root Cause

`MCPToolHandler.handle` called `handleInitialize` with only the JSON-RPC id. `handleInitialize` therefore had no access to `request.params`, performed no shape or field validation, and always returned the same hard-coded protocol version.

**Defect type:** Missing input validation and protocol negotiation.

**Why it occurred:** The original initialize implementation was added as a static success response. Its regression test also omitted parameters and encoded the invalid behavior as expected success, so later validation work did not cover the handshake boundary.

**Contributing factors:** Initialize request parameters have no dedicated decoded type and arrive through the permissive `AnyCodable` envelope.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/MCP/MCPToolHandler.swift` - Pass initialize params into the method handler; require an object envelope; validate `protocolVersion`, `capabilities`, and `clientInfo` plus `clientInfo.name`, `clientInfo.version`, and optional `clientInfo.title`; return JSON-RPC `-32602` for malformed method params; and negotiate against the server's supported-version set.
- `Transit/Transit/MCP/MCPServer.swift` - Enforce JSON-RPC's object/array requirement for top-level `params`, returning `-32600 Invalid Request` for scalar or null values before method dispatch.
- `Transit/TransitTests/MCPToolHandlerTests.swift` - Replace the incorrect parameterless success request with a valid supported-version handshake.
- `Transit/TransitTests/MCPInitializeHandshakeTests.swift` - Add focused malformed-handshake and unsupported-version regression coverage.

**Approach rationale:** Method-specific validation stays in `MCPToolHandler`, where all other MCP parameter validation occurs. Small typed-throwing validators keep field-specific errors readable while preserving a single JSON-RPC error mapping. An explicit supported-version set and latest-version constant encode the MCP negotiation rule without changing Transit's advertised version.

**Alternatives considered:**
- Add a dedicated `Decodable` initialize request type at the HTTP decoding layer - rejected because malformed method params are JSON-RPC `Invalid Params`, not malformed request envelopes, and existing method dispatch intentionally carries `params` through `AnyCodable`.
- Return an unsupported-version error - rejected because MCP 2025-03-26 requires the server to respond with another supported version, preferably its latest, when the requested version is unsupported.

## Regression Test

**Test files:** `Transit/TransitTests/MCPInitializeHandshakeTests.swift`, `Transit/TransitTests/MCPToolHandlerTests.swift`
**Test names:** `initializeWithoutParamsReturnsInvalidParams`, `initializeWithNonObjectParamsReturnsInvalidParams`, `initializeWithScalarParamsReturnsInvalidRequest`, `initializeRequiresEveryHandshakeField`, `initializeRejectsWrongRequiredFieldTypes`, `initializeRejectsMalformedClientInfo`, `initializeReturnsServerInfoForSupportedProtocolVersion`, `initializeFallsBackToSupportedProtocolVersion`

**What it verifies:** Required handshake fields and their wire types are enforced; object/array method-parameter mismatches return `-32602`; scalar/null JSON-RPC `params` return `-32600`; valid supported versions are echoed; and unsupported versions fall back to the server's advertised supported version.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/MCP/MCPToolHandler.swift` | Validate initialize parameters and negotiate protocol versions |
| `Transit/Transit/MCP/MCPServer.swift` | Reject scalar/null top-level params as invalid JSON-RPC requests |
| `Transit/TransitTests/MCPToolHandlerTests.swift` | Send a valid handshake from the success test |
| `Transit/TransitTests/MCPInitializeHandshakeTests.swift` | Focused initialize validation and negotiation coverage |
| `docs/agent-notes/mcp-server.md` | Document the enforced handshake contract |
| `CHANGELOG.md` | Record the user-visible protocol fix |
| `specs/bugfixes/mcp-initialize-accepts-malformed-handshake-requests/report.md` | Investigation and resolution record |

## Verification

**Automated:**
- [x] `make test-quick` passes: final `.xcresult` reports 1,595 tests passed, 0 failed; all eight initialize handshake regression tests passed.
- [x] `make lint` passes.
- [ ] `make test` completed, but direct `.xcresult` inspection reports 1,140 tests passed and 6 unrelated UI tests failed: `testClearAll`, `testEditViewPreservesTaskMilestone`, `testSettingsHasBackChevron`, `testSettingsWithNoProjectsShowsCreatePrompt`, `testTappingGearPushesSettingsView`, and `testDataMaintenanceGoldenPath`. The Makefile pipeline returned exit 0 despite the failed result bundle, so the bundle—not the shell status—is authoritative. Another worktree began using the same simulator during this retry; all six failures match the earlier contended run.

**Manual verification:**
- [x] Compared response behavior with the MCP 2025-03-26 lifecycle initialization and version-negotiation requirements.

## Prevention

**Recommendations to avoid similar bugs:**
- Pass method parameters into every method-specific handler and validate required shapes at the boundary.
- Keep at least one negative protocol test beside each successful handshake test.

## Related

- Transit T-1778
- MCP 2025-03-26 lifecycle: https://modelcontextprotocol.io/specification/2025-03-26/basic/lifecycle/
