# Structured MCP results: requirements

## Introduction

Transit agents need saved records and recovery information they can consume directly from MCP results. This feature defines structured results and migrates Transit's local MCP endpoint to revision `2026-07-28`. It retains saved text payloads and write/cursor evidence while reporting unsupported links and failed reads explicitly.

## Non-goals

- Legacy MCP revisions, initialization/session/GET transport and wire-level JSON-RPC batches.
- URL registration or entity-opening navigation from T-572; App Intents result redesign.
- T-2008/T-2129 bug implementation, portfolio aggregation or new capture/freshness algorithms.
- T-2384 batch execution/dry-run semantics, new receipt/key namespace, receipt migration or revision coverage changes.
- Remote access/OAuth, client settings changes, deployment or implementation in this spec phase.

## Approved parser resource boundary

Owner amendment Sentinel_9536d4df532c81919792e70801f128fb limits each parser input to32 nested JSON object/array containers: a root object/array counts1, scalars count0, and width does not increase nesting. This explicitly qualifies structured interpretation/preservation in1.1–1.3 and2.1: a syntactically valid generated source deeper than32 fails with distinct resourceLimit; a deeper retained source keeps its exact original text and optional isError but has unreadable/unestablished structured evidence, without receipt rewrite or guessed outcome. Raw text remains recoverable even when structured interpretation is unavailable. This is a parser-input limit, not a promise that an emitted modern wrapper has at most32 levels; complete wire envelopes and generated schemas are verified separately. Boundary tests cover31/32/33 and wide arrays.

### 1. Structured record and outcome access

**User Story:** As an agent, I want structured tool results, so that I can consume records and errors without parsing text JSON.

**Acceptance Criteria:**

1. <a name="1.1"></a>WHEN an enabled tool returns a record, collection or operation outcome, Transit SHALL expose its logical JSON payload in `structuredContent` and retain its existing text payload shape; identical logical fields SHALL agree across both representations.  
2. <a name="1.2"></a>WHEN a result includes saved entity data, Transit SHALL expose existing UUID/display identities, normalized saved values and canonical revisions where applicable, retaining absent fields, explicit nulls and unknown fields without replacing them with guessed defaults.  
3. <a name="1.3"></a>Transit SHALL document a versioned structured contract for reads, writes, errors and link availability, and SHALL publish output schemas that accept every advertised structured success/error variant, including retained historical payloads with unknown fields and absent/null distinctions.  
4. <a name="1.4"></a>WHEN a saved write or cursor result is presented, Transit SHALL keep its original text string unchanged and place supplemental classifications/link availability outside the original saved payload, distinguishable even when unknown saved field names collide with the supplemental contract.  

### 2. Saved replay and frozen reads

**User Story:** As an agent, I want structured results to preserve saved evidence, so that retries and continuations cannot change the operation I am verifying.

**Acceptance Criteria:**

1. <a name="2.1"></a>WHEN a valid retained T-2380 terminal receipt is replayed, including one created before this feature, Transit SHALL return the saved outcome/record, original `isError`, canonical revisions, acceptance and retry direction in both result channels even after current entity edits/deletion, without altering the receipt or extending its replay expiry.  
2. <a name="2.2"></a>WHEN an ordinary or reusable snapshot cursor is continued, Transit SHALL return the same frozen logical page, revisions, text and capture metadata for that page throughout its valid retention lifetime.  
3. <a name="2.3"></a>WHERE task comment bodies are omitted, Transit SHALL retain the captured canonical comment-covered `r1` revision.  
4. <a name="2.4"></a>IF saved outcome evidence is malformed, unreadable or unsupported, Transit SHALL report that the outcome cannot be established, require reconciliation for writes, and SHALL NOT fabricate a successful replay, a no-effect rejection or a new-key retry instruction.  
5. <a name="2.5"></a>WHEN a caller retries a lost write response with a new JSON-RPC request ID and the same protected tool/key/arguments, Transit SHALL preserve T-2380 acceptance, retention and replay semantics independently of the protocol version's removed sessions.  

### 3. Error and completeness semantics

**User Story:** As an agent, I want explicit failure and retry information, so that I can distinguish correction, retry and reconciliation.

**Acceptance Criteria:**

1. <a name="3.1"></a>WHEN a tool execution fails, Transit SHALL provide a machine-readable category distinguishing invalid caller input, missing/ambiguous entities, revision or key conflict, storage or incoherent-capture failure, transient admission/deadline or capacity failure, invalid/expired cursor, serialization failure and uncertain write outcome where supported by available evidence; unclassified historical evidence SHALL be explicit.  
2. <a name="3.2"></a>WHEN presenting a tool error, Transit SHALL retain its existing code/message, `isError` and available `accepted`/`outcome`/`retryAction`; a supplemental category SHALL NOT imply a safe retry contrary to that evidence. Protocol-invalid requests SHALL remain JSON-RPC/HTTP failures distinct from tool results.  
3. <a name="3.3"></a>IF any read required for a complete result fails, Transit SHALL return a failed read without successful records, cursor or snapshot publication, and SHALL NOT present failure as an empty collection or complete partial data. Defined per-selector absent outcomes SHALL remain distinguishable from whole-read failure.  
4. <a name="3.4"></a>IF result encoding/delivery fails after a write may have committed, Transit SHALL NOT report proven no effect or advise a fresh-key retry; recovery information SHALL direct the caller to the original protected key and evidence or reconciliation.  
5. <a name="3.5"></a>WHEN consumers request error/recovery information, Transit SHALL document which categories permit an identical-request retry, require input correction, or require reconciliation; unknown outcome/evidence SHALL not imply guaranteed retry safety.  

### 4. Saved normalization and supported links

**User Story:** As an agent, I want normalized values and supported entity links, so that verification matches storage and navigation does not guess destinations.

**Acceptance Criteria:**

1. <a name="4.1"></a>WHEN a mutation reports success, its mutation-owned, revision-covered fields SHALL match a full readback at the same covered revision after documented field-specific normalization, including whitespace/newline treatment and absent/null distinctions; related display labels outside revision coverage SHALL be distinguished from saved mutation fields; this feature SHALL NOT introduce new normalization or remint revisions.  
2. <a name="4.2"></a>WHEN a result identifies a task or project, Transit SHALL explicitly report that navigable links are unavailable when no supported entity-opening scheme exists, and SHALL NOT emit a guessed navigable URI.  
3. <a name="4.3"></a>WHEN link availability accompanies an identified record, it SHALL refer to that record's UUID and entity type rather than relying on a possibly colliding display ID; this feature SHALL return unavailable status for task/project navigation until its supporting feature is implemented.  
4. <a name="4.4"></a>WHEN terminal write evidence is replayed, supplemental link availability SHALL remain deterministic for that saved result rather than changing with a current-model reread.  

### 5. Latest-only MCP lifecycle and HTTP

**User Story:** As a local MCP client, I want the current protocol contract, so that discovery, tools and change notifications interoperate predictably.

**Acceptance Criteria:**

1. <a name="5.1"></a>Transit SHALL support only MCP `2026-07-28`, implement `server/discover` with its supported version/capabilities/identity, and report unsupported versions with an actionable supported-version error.  
2. <a name="5.2"></a>WHEN a modern request arrives, Transit SHALL validate required per-request protocol/capability metadata and matching protocol/method/name HTTP headers before tool effects or store capture; missing, malformed, conflicting or unsupported values SHALL be rejected without dispatch using the standard HTTP/JSON-RPC status and error codes, including HTTP 400 for required-metadata/header failures and a supported-version list for unsupported versions. Notification validation SHALL follow the applicable notification rules rather than imposing request-only metadata/header requirements.  
3. <a name="5.3"></a>Transit SHALL accept a single JSON-RPC request or notification per HTTP POST; request arrays, legacy initialization and GET listening SHALL be rejected without tool dispatch or mutation. Request-only methods, including `tools/call`, SHALL require a valid request ID and SHALL NOT execute when presented as notifications; unsupported client notifications SHALL be rejected without tool effects. Transit SHALL neither issue nor require protocol session IDs. An unknown RPC method SHALL return the defined HTTP 404/method-not-found error without tool dispatch.  
4. <a name="5.4"></a>WHEN a modern ordinary RPC result is returned, it SHALL include the required `resultType:"complete"`; discovery and tool-list responses SHALL include valid cache metadata and deterministic tool order matching current availability. Successful notifications SHALL use the protocol's acknowledgement behavior without a JSON-RPC result.  
5. <a name="5.5"></a>WHEN a client opts into `toolsListChanged` through `subscriptions/listen`, Transit SHALL send `notifications/subscriptions/acknowledged` as the first stream message and notify that stream after tool availability changes with the originating subscription ID and acknowledged filter; unrequested notification types SHALL NOT be emitted, and disconnect or server teardown SHALL release its stream registration without requiring a session ID.  
6. <a name="5.6"></a>Transit SHALL preserve loopback-only listening and Origin/Host rejection before dispatch; this migration SHALL not expand remote access or require new authorization credentials.  

### 6. Read limits and migration readiness

**User Story:** As an agent operator, I want protocol migration to preserve bounded reads and verified client access, so that the upgraded endpoint remains usable.

**Acceptance Criteria:**

1. <a name="6.1"></a>WHEN a T-63 covered read runs, Transit SHALL make its complete encoded response available within the approved five-second budget or select the defined timeout, preserve the eight-unfinished-physical-read admission limit across listener restart, and SHALL NOT expose cursor/snapshot success whose publication failed. HTTP response-stream cancellation SHALL suppress further delivery and late publication while unfinished physical reads retain their slots until physical completion.  
2. <a name="6.2"></a>WHEN structured/text duplication or modern envelope encoding exhausts a read deadline or ordinary/reusable retention capacity, Transit SHALL return the defined timeout/capacity failure without publishing partial data or altering existing five-minute/eight-snapshot/16-MiB retention contracts.  
3. <a name="6.3"></a>BEFORE migration is activated, the actual installed Codex surfaces intended for use, Claude Code and Claude Desktop SHALL each demonstrate modern discovery and tool list/call consumption against an isolated latest-only endpoint; subscription behavior SHALL be validated by a conforming test client and by installed surfaces that opt into it. Unavailable modern mode SHALL be reported as a blocking prerequisite rather than assumed from version or embedded code.  

## Approval

Approved by the owner on 2026-10-03 at 09:51:37.926279Z: “Structured MCP results requirements also approved” (parent-verified Sentinel_39b0ca45b1b8819180ac6d9600578f0b). This authorises design; design and task approvals remain separate gates. No implementation is authorised.
