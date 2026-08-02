# Bugfix Report: MCP GET Endpoint Returns 404 Instead of 405

**Date:** 2026-08-02
**Status:** Fixed
**Transit ticket:** T-1835

## Description of the Issue

Transit advertises the MCP Streamable HTTP transport version `2025-03-26`, but
its Hummingbird router registers only `POST /mcp`. A client probing the MCP
endpoint with `GET /mcp` therefore reaches Hummingbird's unmatched-route
fallback and receives `404 Not Found`.

For Streamable HTTP, GET is the endpoint's optional server-to-client SSE
operation. When Transit does not offer an SSE listening stream, the MCP
endpoint must respond with `405 Method Not Allowed`, ideally including
`Allow: POST`, so a client can distinguish an unsupported endpoint method from
an unknown path.

**Reproduction steps:**
1. Enable the MCP server in Transit Settings.
2. Send `GET http://127.0.0.1:3141/mcp`.
3. Observe `404 Not Found` instead of `405 Method Not Allowed`.

**Impact:** MCP clients probing the advertised endpoint cannot distinguish an
unsupported SSE listening stream from a missing MCP endpoint. POST-based MCP
operation is unaffected.

## Investigation Summary

The investigation followed the systematic debugging workflow:

- **Symptoms examined:** The ticket reports `GET /mcp` returning 404. A
  route-level regression test reproduces that response on the real Hummingbird
  router.
- **Code inspected:** `Transit/Transit/MCP/MCPServer.swift` registers the
  single `POST /mcp` route; the POST closure performs origin validation,
  request decoding, and JSON-RPC dispatch. Existing lifecycle, origin, and
  batch tests establish the route test harness and unchanged behavior.
- **Hypotheses tested:** This is not a lifecycle or binding problem: the
  router can be exercised without starting a listener. It is not a JSON-RPC
  decoding problem: GET has no route match and never reaches the POST body
  handling. The supplied ticket identifies Hummingbird's
  `NotFoundResponder` as the source of the 404.

## Discovered Root Cause

`MCPServer.makeRouter(handler:)` registers `POST /mcp` but does not register a
GET handler for the same path. Hummingbird consequently treats the valid MCP
endpoint path as an unknown route for GET and returns its default 404 response.

**Defect type:** Missing route / protocol contract mismatch.

**Why it occurred:** The initial Streamable HTTP implementation modeled
Transit as POST-only and omitted the explicit method response required when no
SSE listening stream is offered.

**Contributing factors:** Hummingbird's unmatched-route fallback does not
encode the MCP endpoint's method semantics, so the distinction must be made by
the application router.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/MCP/MCPServer.swift:196-217` - registers an explicit
  `GET /mcp` route. It repeats the existing origin/authority validation and
  returns HTTP 405 with `Allow: POST` when the request is from an allowed
  local client. The existing POST route and its body/JSON-RPC dispatch path
  are unchanged.
- `Transit/TransitTests/MCPServerRouteTests.swift` - adds route-level tests
  for the 405 status, `Allow: POST` header, unchanged POST success, GET origin
  rejection, and unrelated-path 404 behavior.
- `docs/agent-notes/mcp-server.md` and
  `specs/mcp-server/implementation.md` - clarify that GET is explicitly
  handled as an unsupported SSE operation while POST remains the data path.

**Approach rationale:** The fix is deliberately at the Hummingbird router
boundary. Registering GET on the exact `/mcp` path lets Hummingbird distinguish
an unsupported method from an unknown path, while the `Allow` header tells MCP
clients that POST is the supported operation. Repeating origin validation
before returning 405 preserves the transport security policy for every MCP
request. No lifecycle or POST handler code needs to change.

**Alternatives considered:**
- **Leave GET unmatched and rely on Hummingbird's 404** - rejected because it
  violates the advertised Streamable HTTP `2025-03-26` endpoint contract and
  prevents clients from distinguishing method support from route absence.
- **Add a global method-not-allowed middleware** - rejected because the
  behavior is specific to the MCP endpoint and a route-local handler is the
  smallest change with no unrelated-path effects.
- **Return 405 without origin validation** - rejected because MCP origin
  validation applies to incoming transport requests; the new route must not
  create a browser-origin bypass.


## Regression Test

**Test file:** `Transit/TransitTests/MCPServerRouteTests.swift`

**Test names:**
- `getMcpReturnsMethodNotAllowedWithPostAllowHeader`
- `postMcpStillDispatchesNormally`
- `getMcpStillValidatesUntrustedOrigins`
- `getOnUnrelatedPathRemainsNotFound`

**What it verifies:** The real Hummingbird router returns 405 and `Allow: POST`
for GET on `/mcp`, keeps POST dispatch working, retains origin and host rejection
on the new route, confirms unsupported HEAD/OPTIONS use the framework's 404
fallback, and continues returning 404 for an unrelated path.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/MCP/MCPServer.swift` | Explicit GET `/mcp` method response with origin validation. |
| `Transit/TransitTests/MCPServerRouteTests.swift` | New route-level regression coverage. |
| `docs/agent-notes/mcp-server.md` | MCP transport behavior and endpoint documentation. |
| `specs/mcp-server/implementation.md` | MCP implementation architecture documentation. |
| `specs/bugfixes/mcp-get-endpoint-returns-404-instead-of-405/report.md` | Investigation and resolution record. |
| `CHANGELOG.md` | Unreleased fixed-entry for T-1835. |

## Verification

**Automated:**
- [x] Regression tests fail before the fix, reproducing the incorrect 404 and missing endpoint method response.
- [x] `make test-quick` passes after the fix, including all existing macOS unit tests and the seven T-1835 route tests.
- [x] `make lint` passes in strict mode.
- [x] `make build-macos` passes for the affected macOS target.

**Manual verification:**
- [x] Route-level request dispatch confirms `GET /mcp` returns 405 with
  `Allow: POST`.
- [x] Route-level request dispatch confirms a normal `POST /mcp` ping still
  returns HTTP 200.
- [x] Route-level request dispatch confirms `GET /not-mcp` remains 404 without
  an `Allow` header.


## Prevention

- Register explicit handlers for every HTTP method required by an advertised
  transport contract; do not rely on an unmatched-route fallback for method
  semantics.
- Keep route-level tests for both supported and intentionally unsupported
  methods, including the `Allow` header and an unrelated-path 404 control.

## Related

- Transit ticket T-1835
- MCP Streamable HTTP transport contract for `2025-03-26`:
  https://modelcontextprotocol.io/specification/2025-03-26/basic/transports#listening-for-messages-from-the-server
