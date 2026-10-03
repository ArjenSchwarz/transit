# Structured MCP results: requirements review

Status: critic complete; internal peer validation in progress; requirements awaiting user approval. No implementation.

## Self-check

Six one-line user stories; anchored EARS criteria, 3-sentence introduction and explicit non-goals. Criteria describe observable outputs and failures; envelope/type placement remains design work. Field parity covers mutation-owned revision-covered fields rather than assuming parent display names cannot change at the same task revision. No supported navigation scheme is invented. Discovery caching, subscription filtering/correlation and physical-worker cancellation accounting are explicit.

## Critic

Read-only internal design-critic agent reviewed the full proposal and code/context. Four findings adopted:

| Finding | Resolution |
| --- | --- |
| Protocol error/status and subscription boundary underspecified | 5.2–5.5 now distinguish requests/notifications, standard metadata/header errors, supported-version list, unknown-method HTTP status, first acknowledgement and filter/subscriptionId behavior. |
| Disconnect could prematurely release physical workers | 6.1 now requires delivery/publication cancellation with slots retained until physical completion. |
| Supplemental fields can collide with historical unknown fields | 1.4 requires a distinct supplemental boundary even for colliding names; exact schema remains a design gate. |
| Failure taxonomy could hide T-63 distinctions | 3.1 names incoherent capture, capacity and invalid/expired cursor; 3.2 retains existing source codes and retry semantics. |

The critic also prompted self-check tightening: 4.1 excludes current related display labels from same-revision mutation equality; 4.3 reports unavailable UUID-associated links rather than specifying deferred URL navigation; 5.4 includes discovery cache fields.

## Client readiness risk

Read-only checks: standalone Codex0.160.0 and bundled Codex0.159.2 feature lists show `mcp_2026_07_28` disabled/under development. Primary exact-release source and binary inspection establish code availability, not active negotiation. Claude Code2.1.288 has documented modern SDK/runtime support and cached HTTP negotiation enabled; no live modern connection has been established. Claude Desktop is not yet verified, and the intended Claude surface was asked through parent. Client configs and the running Transit server remain unchanged. Requirement6.3 blocks activation until actual intended clients are validated.

## Peer validation

Use two independent internal agents after critic: technical correctness/replay/transport and API simplicity/maintainability/scope. No external model services are authorised. Findings and disposition will be recorded before phone delivery/user gate.

## Approval gate

Send reviewed requirements to the user's phone via `/Users/arjen/bin/send-md-to-phone`, then route through parent: **Do the requirements look good or do you want additional changes?** Requirements approval starts design, not implementation.
