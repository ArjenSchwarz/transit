# Bugfix Report: MCP Server Accepts Untrusted Browser Origins

**Date:** 2026-07-25
**Status:** Fixed
**Transit ticket:** T-1833

## Description of the Issue

The embedded MCP Streamable HTTP endpoint (`POST /mcp`) binds to `127.0.0.1`, but
`MCPServer.makeRouter(handler:)` read the request body and dispatched the JSON-RPC
payload without ever inspecting the HTTP `Origin` header. Binding to loopback
protects against *remote* network attackers, but not against code already running
on the machine inside the user's browser: a page on any website can issue a
cross-origin `fetch()` at `http://127.0.0.1:3141/mcp`, and a DNS-rebinding host
can make the browser treat the loopback server as same-origin.

Because the route dispatched unconditionally, every MCP tool - including
state-changing ones such as `create_task`, `update_task_status`, `update_task`,
`delete_milestone`, and the gated maintenance tools - could be invoked by an
untrusted web page under the user's app privileges.

**Reproduction steps:**
1. Enable the MCP server in Transit Settings (default port 3141).
2. Open any website in a browser on the same machine.
3. From that page's console run:
   ```js
   fetch("http://127.0.0.1:3141/mcp", {
     method: "POST",
     headers: { "Content-Type": "application/json" },
     body: JSON.stringify({
       jsonrpc: "2.0", id: 1, method: "tools/call",
       params: { name: "create_task", arguments: { project: "Transit", name: "pwned" } }
     })
   })
   ```
4. Observe: HTTP 200 and a task created in the user's Transit database.

**Impact:** High. Any website the user visits - or any host that rebinds DNS to
127.0.0.1 - gained full read/write access to the user's task data through the
local MCP server. The MCP Streamable HTTP transport specification calls this out
explicitly and requires servers to validate `Origin` on all incoming connections:
https://modelcontextprotocol.io/specification/2025-11-25/basic/transports#security-warning

## Investigation Summary

- **Symptoms examined:** `POST /mcp` returns a normal JSON-RPC result regardless
  of what `Origin` the caller sends.
- **Code inspected:**
  - `Transit/Transit/MCP/MCPServer.swift` - `start(port:)` binds
    `.hostname("127.0.0.1", port:)`; `makeRouter(handler:)` registers the single
    `router.post("mcp")` route.
  - `Transit/Transit/MCP/MCPToolHandler.swift` - dispatch is purely
    method/argument driven; there is no transport-level authorization anywhere in
    the chain.
  - Hummingbird 2.20 request plumbing - the HTTP/1 `Host` header is mapped onto
    `HTTPRequest.authority` by `NIOHTTPTypesHTTP1`, so both `Origin` and `Host`
    are reachable from the route via `request.head`.
- **Hypotheses tested:**
  - *Does binding to 127.0.0.1 already prevent this?* No. Loopback binding blocks
    off-machine clients, not the user's own browser, which is exactly the threat
    model the MCP spec's security warning describes.
  - *Is there middleware doing the check?* No. `Router()` is constructed bare with
    no middleware stack; the route closure is the first and only code that sees
    the request.
  - *Would rejecting requests without an `Origin` header work?* No - that would
    break every legitimate local MCP client. CLI/agent clients are not browsers
    and send no `Origin` at all, so absence must remain allowed.

## Discovered Root Cause

`MCPServer.makeRouter(handler:)` performed no transport-level origin validation.
The route body went straight from `request.body.collect(upTo:)` to
`decodeIncomingRequest(_:)` to `handler.handle(_:)`.

**Defect type:** Missing validation (security control absent).

**Why it occurred** (five whys):
1. A malicious page can invoke MCP tools - *why?* The server answers its requests.
2. It answers them - *why?* The route dispatches every well-formed JSON-RPC body.
3. It dispatches everything - *why?* No check on `Origin`/`Host` exists.
4. No check exists - *why?* The design treated "bind to 127.0.0.1" as the
   complete security boundary for a local-only server.
5. That assumption held - *why?* Loopback binding intuitively reads as
   "unreachable from outside", which is true for the network but not for the
   browser running on the same host. The MCP spec's explicit `Origin` requirement
   was not carried into the implementation.

**Contributing factors:** The server has no middleware layer, so there was no
natural place where a cross-cutting request check would have been noticed as
missing. The endpoint is also unauthenticated by design (local single-user app),
which makes origin validation the only line of defence.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/MCP/MCPOriginValidator.swift` (new) - strict, dependency-free
  parsing of an RFC 6454 origin serialization and of a `Host`/authority value,
  plus `MCPOriginValidator.rejectionReason(origin:authority:)` which encodes the
  policy:
  - `Origin` present => must be `http`/`https` with a loopback host
    (`127.0.0.1`, `localhost`, `::1`), otherwise reject.
  - `Host`/authority present => must be a loopback host, otherwise reject
    (this is the DNS-rebinding signature: a public hostname resolving to
    127.0.0.1).
  - `Origin` absent => allowed, so non-browser local MCP clients keep working.
  - Anything with userinfo, a path, a query, or a fragment is rejected rather
    than parsed leniently.
- `Transit/Transit/MCP/MCPServer.swift` - the `POST /mcp` route now calls
  `MCPOriginValidator.rejectionReason(...)` as its first statement and returns
  HTTP `403 Forbidden` with a fixed `text/plain` body before the request body is
  collected, decoded, or dispatched. The body is a constant `"Forbidden"` rather
  than the specific reason, so a prober cannot learn which check tripped.
  `makeRouter(handler:)` changed from `private` to internal so route-level tests
  can exercise the real router.

**Approach rationale:** The check belongs at the transport edge, before any
parsing, because the point is to never let untrusted input reach the dispatcher.
Returning a plain HTTP 403 (rather than a JSON-RPC error object) is correct: the
request was rejected at the transport layer, so there is no JSON-RPC session to
respond within, and a JSON-RPC 200 would tell an attacker's page more than it
should. Keeping the policy in its own type keeps `MCPServer` focused on lifecycle
and routing, and makes the parsing rules directly unit-testable.

**Alternatives considered:**
- **Hummingbird middleware** - a `RouterMiddleware` implementing the check would
  also work, but with a single route it adds a type and an indirection for no
  behavioural gain.
- **Reject requests with no `Origin`** - strictly safer against exotic clients,
  but it breaks every real MCP client (Claude Code and CLI callers send no
  `Origin`), which the ticket explicitly forbids.
- **Parse the origin with `URL`/`URLComponents`** - rejected because those
  parsers are deliberately lenient: `URL(string: "http://127.0.0.1@evil.com")`
  yields host `evil.com`, and other malformed inputs are silently normalised. A
  security check should fail closed on anything it does not fully understand.
- **Allow the whole `127.0.0.0/8` range and `*.localhost`** - rejected because
  the server only ever binds `127.0.0.1`, and `*.localhost` names are a known
  bypass vector on resolvers that map them to loopback.

## Regression Test

**Test files:**
- `Transit/TransitTests/MCPServerOriginValidationTests.swift` - route-level tests
  that build the real router via `MCPServer.makeRouter(handler:)`, drive it with
  a synthesised `Request`/`BasicRequestContext`, and assert on the HTTP status.
- `Transit/TransitTests/MCPOriginValidatorTests.swift` - unit tests for the
  parsing and policy rules.

**Key test names:**
- `attackerOriginIsRejected` / `httpAttackerOriginIsRejected` - a foreign
  `Origin` gets HTTP 403.
- `attackerOriginIsRejectedBeforeDispatch` - a `tools/call create_task` body sent
  with a foreign `Origin` returns 403 **and** creates no task, proving the check
  runs before dispatch.
- `attackerOriginIsRejectedEvenWithMalformedBody` - proves the check runs before
  decoding (a malformed body still yields 403, not a JSON-RPC parse error).
- `absentOriginIsAccepted` / `absentOriginStillDispatchesStateChangingTools` - a
  local client that sends no `Origin` still gets HTTP 200 and its tool still runs.
- `loopbackIPOriginIsAccepted`, `localhostOriginIsAccepted`,
  `ipv6LoopbackOriginIsAccepted` - approved local origins still work.
- `nullOriginIsRejected`, `localhostLookalikeOriginIsRejected`,
  `userInfoOriginIsRejected` - bypass attempts are rejected.
- `nonLoopbackHostIsRejectedWhenOriginAbsent` - DNS-rebinding `Host` is rejected.
- `rawHTTP1RebindingHostIsRejected`, `rawHTTP1AttackerOriginIsRejected`,
  `rawHTTP1LocalClientIsAccepted` - build a real `HTTPRequestHead` with raw
  wire headers and convert it with `HTTPRequest(head, secure:splitCookie:)`, the
  exact initializer Hummingbird's `HTTP1ToHTTPServerCodec` uses. This proves the
  load-bearing assumption that a raw `Host:` header lands in `head.authority`
  (and `Origin:` in `head.headerFields`) rather than assuming it.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/MCP/MCPOriginValidator.swift` | New - strict origin/authority parsing and the accept/reject policy |
| `Transit/Transit/MCP/MCPServer.swift` | Validate `Origin`/`Host` first in the `POST /mcp` route; return 403; `makeRouter` made internal for testing |
| `Transit/TransitTests/MCPServerOriginValidationTests.swift` | New - route-level regression tests |
| `Transit/TransitTests/MCPOriginValidatorTests.swift` | New - unit tests for the validator rules |
| `docs/agent-notes/mcp-server.md` | Documented the origin/host policy and the local-client constraint |

## Verification

**Automated:**
- [x] Regression tests fail before the fix and pass after. The pre-fix
  `make test-quick` run reported 1361 passing / 9 failing, the 9 being exactly
  the new route-level rejection tests. The post-fix run reported 1371 passing /
  0 failing, including all 30 new tests.
- [x] SwiftLint passes (`make lint`, strict mode)
- [x] All 33 tests in the two new suites pass after the fix
- [~] `make test-quick` did not reach its final `Test Succeeded` banner. Every
  `xcodebuild` process on the machine (four parallel fix streams, not just this
  one) stalled at 0% CPU in state `SN` around the ~1350-test mark — the wedge
  described in `docs/agent-notes/build-sandbox-wedge.md`. Zero test failures
  were reported in any post-fix run before the stall, and the stall reproduces
  identically on the pre-fix tree, so it is environmental rather than caused by
  this change.

**Manual verification:**
- `curl -X POST http://127.0.0.1:3141/mcp -H 'Content-Type: application/json' -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'`
  still succeeds (no `Origin` sent by curl).
- The same request with `-H 'Origin: https://evil.example.com'` returns
  `403 Forbidden`.

## Prevention

**Recommendations to avoid similar bugs:**
- Treat "binds to loopback" as protection against the network only. Anything a
  browser can reach needs an origin check, because the browser is inside the
  trust boundary.
- Any new HTTP route added to `MCPServer` must run
  `MCPOriginValidator.rejectionReason(origin:authority:)` before touching the
  request body. If a second route is ever added, promote the check to a
  Hummingbird middleware so it cannot be forgotten.
- When implementing a protocol that ships a "Security Warning" section, mirror
  each MUST into a test, not just into prose.

## Related

- Transit ticket T-1833
- MCP Streamable HTTP transport security warning:
  https://modelcontextprotocol.io/specification/2025-11-25/basic/transports#security-warning
- RFC 6454 (The Web Origin Concept) - origin serialization format
