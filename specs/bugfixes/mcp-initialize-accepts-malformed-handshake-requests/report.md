# Bugfix Report: MCP Initialize Accepts Malformed Handshake Requests

**Date:** 2026-08-02
**Status:** In Progress

## Description of the Issue

Transit returned a successful MCP initialize result without reading the request parameters. Requests that omitted or malformed the protocol version, client capabilities, or client implementation information therefore completed as if they were valid handshakes.

**Reproduction steps:**
1. Send an `initialize` JSON-RPC request with no `params`, non-object `params`, or malformed required fields.
2. Observe Transit's MCP response.
3. The server returns a successful initialize result advertising protocol version `2025-03-26` instead of a JSON-RPC `-32602 Invalid Params` error.

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

_To be completed after implementation._

**Approach rationale:** Pending implementation verification.

**Alternatives considered:**
- Add a dedicated `Decodable` initialize request type at the HTTP decoding layer — rejected for now because method-specific parameter validation belongs in the handler and existing requests intentionally use `AnyCodable`.

## Regression Test

**Test file:** `Transit/TransitTests/MCPToolHandlerTests.swift`
**Test names:** `initializeWithoutParamsReturnsInvalidParams`, `initializeWithNonObjectParamsReturnsInvalidParams`, `initializeRequiresEveryHandshakeField`, `initializeRejectsWrongRequiredFieldTypes`, `initializeRejectsMalformedClientInfo`, `initializeReturnsServerInfoForSupportedProtocolVersion`, `initializeFallsBackToSupportedProtocolVersion`

**What it verifies:** Required handshake fields and their wire types are enforced, valid supported versions are echoed, and unsupported versions fall back to the server's advertised supported version.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/MCP/MCPToolHandler.swift` | Pending initialize validation and version negotiation |
| `Transit/TransitTests/MCPToolHandlerTests.swift` | Focused initialize handshake regression coverage |
| `specs/bugfixes/mcp-initialize-accepts-malformed-handshake-requests/report.md` | Investigation and resolution record |

## Verification

**Automated:**
- [ ] Regression test passes
- [ ] Full test suite passes
- [ ] Linters/validators pass

**Manual verification:**
- Compare response behavior with the MCP 2025-03-26 lifecycle initialization and version-negotiation requirements.

## Prevention

**Recommendations to avoid similar bugs:**
- Pass method parameters into every method-specific handler and validate required shapes at the boundary.
- Keep at least one negative protocol test beside each successful handshake test.

## Related

- Transit T-1778
- MCP 2025-03-26 lifecycle: https://modelcontextprotocol.io/specification/2025-03-26/basic/lifecycle/
