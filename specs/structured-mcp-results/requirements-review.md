# Structured MCP results: requirements review

Status: critic and two independent internal peer validations complete; final targeted re-review found no remaining requirements blockers. Requirements approved by parent-verified owner message Sentinel_39b0ca45b1b8819180ac6d9600578f0b. No implementation.

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

Read-only checks: standalone Codex0.160.0 and bundled Codex0.159.2 feature lists show `mcp_2026_07_28` disabled/under development. Primary exact-release source and binary inspection establish code availability, not active negotiation. Claude Code2.1.288 has documented modern SDK/runtime support and cached HTTP negotiation enabled; no live modern connection has been established. User clarified both Claude Code and Claude Desktop. Installed Desktop2.19675.0's ASAR includes modern version selection/discovery/subscription/per-request metadata code in its direct MCP host and main bundle. The official Desktop MCP guide does not specify a revision, and local conventional config/log checks did not reveal Transit negotiation. Embedded support is evidence of available code, not enabled active modern negotiation. Client configs and the running Transit server remain unchanged. Requirement6.3 blocks activation until actual intended clients are validated.

## Peer validation

Mode: internal subagents, following the local peer-review-validator fallback. These are independent internal perspectives, not external Codex/Kiro service disclosures. The design critic ran first; technical correctness/replay/transport and API clarity/maintainability/scope peers ran next. After their edits, critic and both peers validated the final changed criteria with no remaining blockers.

| Peer | Finding / rationale | Final disposition |
| --- | --- | --- |
| Technical correctness | Existing handler dispatches tools/call notifications then discards responses; accepting modern notification transport must not preserve that write path. | 5.3 requires a valid request ID for request-only methods and prohibits notification-shaped execution; unsupported notifications have no effects. |
| API/scope | Subscription participation is opt-in; requiring every installed client to listen could unnecessarily block working tool clients. | 6.3 requires installed discovery/list/call readiness; subscription behavior is proven with a conforming client and installed surfaces that opt in. |
| API/scope | Restrictive output schemas could reject preserved historical unknown or absent/null fields. | 1.3 explicitly accepts those retained historical variants. |

Consensus: preserve source result evidence and distinct supplemental namespace, keep frozen metadata/revisions, keep T-63 worker/publication constraints, and prove intended client modern access. Both peers accepted the critic fixes. The subscription gate was narrowed to the standard's opt-in behavior; no deferred transport or navigation framework was added. There are no unresolved reviewer disagreements.

Resolved clarification through parent: user requires **both Claude Code and Claude Desktop** (Sentinel_e3dcebb74f288191a3d42559f563ab5c). AC6.3 now explicitly names both beside actual intended installed Codex surfaces. This selects the migration readiness checks; it does not authorise settings changes or approve other requirements. No active modern-only negotiation has been claimed from embedded symbols, old-server success or version numbers.

Formatting validation: all 27 acceptance criteria have unique anchors and required Markdown double-space line endings, and all six requirements have user stories. Git's default whitespace check flags those intentional skill-required line endings; a per-command check excluding end-of-line spaces verifies other whitespace errors without changing configuration. No application lint/build/test ran.

## Approval gate

Owner requirements approval verified by parent: 2026-10-03T09:51:37.926279Z, Sentinel_39b0ca45b1b8819180ac6d9600578f0b, “Structured MCP results requirements also approved”. Design is authorised; tasks/implementation remain gated. Earlier pending-approval statements are superseded by this verified evidence.
