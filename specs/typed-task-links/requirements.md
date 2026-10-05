# Typed task links — requirements

Deferred destination: **T-2402 — Set up isolated CloudKit integration testing**, created and freshly verified by the parent through the installed UI (Transit, Idea/Research). No duplicate live ticket write.

Review status: amended requirements approved by owner `Sentinel_08cb318218788191a85da25d1206979f` at `a64e595c439db6d62e46c85888f37130d53269fa`. Owner `Sentinel_c95239aefa6481919303c2353b8a9e9c` approved the simpler concurrency guarantee; prior requirement/task approvals and decision history are recorded in decision_log.md. CloudKit test isolation/live verification remains deferred to T-2402.

## Introduction

Transit task relationships let agents identify dependencies, associations, attribution and duplicates without parsing prose. Explicit directions, saved observations and protected edits make those relationships usable while records and CloudKit imports change. This feature supplies the common link foundation for later consolidation without performing consolidation itself.

## Non-Goals

- Semantic duplicate matching, survivor selection, content merging, duplicate closure, consolidation preview/apply/undo or provenance from deferred T-2381.
- Regression tri-state/PR-number fields and workflow/eval adoption from T-1732/T-1733; task copying from T-649.
- Additional relation kinds, task hierarchy, native link editing, App Intent mutation parity or automatic prose-to-link migration.
- Atomic validation-to-save protection against independent writers or sync imports; persistence redesign, distributed locks, global CloudKit graph atomicity or guaranteed remote convergence.
- Permanent-delete cleanup or retry-guard resets.
- New snapshot/freshness/protocol engines, summary count definitions, unsupported entity URLs or changes to unrelated tool permissions.
- Provisioning CloudKit test isolation or executing its live Development schema/export/deletion smoke; deferred by the explicit owner amendment above.

### 1. Relationship vocabulary and identity

**User Story:** As a caller, I want explicit task relationships, so that each link has one interpretable meaning.

**Acceptance Criteria:**

1. <a name="1.1"></a>The system SHALL support only `blocks`, `blocked-by`, `relates-to`, `introduced-by` and `duplicate-of` as public link type spellings, with `blocks`/`blocked-by` representing opposite views of one dependency kind. Unsupported types, self-links and malformed UUIDs SHALL be rejected without domain effects.  
2. <a name="1.2"></a>WHEN A blocks B, readback SHALL expose A's `blocks` B and B's `blocked-by` A; WHEN A relates-to B, readback SHALL expose the association from either endpoint; WHEN A is introduced-by B or duplicate-of B, readback SHALL expose that directed relation and explicitly identified incoming edges on B without inventing additional public mutation types.  
3. <a name="1.3"></a>WHEN equivalent inverse dependency spellings or reversed relates-to endpoints identify the same valid logical relation, the system SHALL expose one active occurrence with stable identity; adding an already-present valid relation or removing an already-absent relation SHALL preserve domain content/timestamps while retaining the protected operation outcome. Incompatible add/remove directives for the same occurrence in one request SHALL be rejected; an explicit replacement of a duplicate target SHALL remain valid under 3.2. Imported multiple physical occurrences SHALL follow 5.4 rather than be silently merged.  
4. <a name="1.4"></a>WHEN endpoints are explicitly selected, the system SHALL accept unambiguous task UUIDs in the same store, including across projects, and SHALL reject missing or ambiguous identities rather than choosing a display-ID/name match; link changes SHALL NOT move either task or its milestone.  
5. <a name="1.5"></a>Each exposed logical edge SHALL identify its edge UUID, endpoint task UUIDs, semantic type and direction relative to the observed task; display labels SHALL be separately identified as observed labels and SHALL NOT establish identity.  

### 2. Dependencies and unblocked queries

**User Story:** As an agent, I want to exclude blocked work, so that I do not start work whose prerequisite is unfinished.

**Acceptance Criteria:**

1. <a name="2.1"></a>WHEN deciding whether a task is unblocked, the system SHALL require every direct blocker to resolve unambiguously and have effective status `done` in the selected saved view; `abandoned`, all nonterminal statuses and unrecognized raw statuses SHALL NOT satisfy a blocker, and no blockers SHALL mean unblocked only when dependency evidence is complete.  
2. <a name="2.2"></a>WHEN a new dependency change would create a directed dependency cycle in the locally observed graph, the system SHALL reject the entire domain change; relates-to and attribution cycles SHALL NOT be interpreted as dependency cycles.  
3. <a name="2.3"></a>WHEN imported dependency evidence contains a cycle, its participants SHALL NOT qualify as unblocked; a candidate with missing/ambiguous/invalid direct blocker evidence SHALL also be excluded with diagnostics. A candidate outside that cycle whose own direct blocker evidence is valid and all direct blockers are Done SHALL remain eligible even if one Done blocker has an invalid dependency ancestry; invalidity SHALL NOT propagate recursively beyond the candidate's own cycle membership/direct evidence.  
4. <a name="2.4"></a>WHEN blockers later change status or dependencies are explicitly removed, a new capture SHALL evaluate the new saved state without changing any retained blocker assessment actually captured in an existing cursor/view; unblocked filtering SHALL consider direct dependencies only and SHALL NOT follow duplicate aliases automatically.  

### 3. Associations, attribution and duplicate resolution

**User Story:** As a caller, I want distinct relationship semantics, so that association, attribution and canonical identity do not trigger unintended actions.

**Acceptance Criteria:**

1. <a name="3.1"></a>WHEN relates-to or introduced-by is set, the relationship itself SHALL preserve task status, descriptions, assignments and regression classification except for separately requested supported task edits in that same operation; introduced-by SHALL allow multiple explicit task sources and SHALL NOT infer regression=yes/no, dependency completion or a PR number.  
2. <a name="3.2"></a>A task SHALL have at most one active outgoing duplicate-of edge; WHEN a new change would create another target or a duplicate chain cycle, the system SHALL reject the whole domain change, while an explicit same-request removal of the old edge and addition of its replacement SHALL be evaluated against the complete proposed result.  
3. <a name="3.3"></a>WHEN a duplicate chain resolves through unambiguous saved tasks and valid edges, the system SHALL return the direct target, ordered path and terminal canonical task UUID; a task with no outgoing duplicate-of SHALL resolve to itself, and Done/Abandoned targets SHALL remain valid targets without a status change.  
4. <a name="3.4"></a>IF duplicate resolution encounters a missing/ambiguous endpoint, cycle, conflicting multiple targets or unreadable required evidence, the system SHALL distinguish invalid graph from failed evidence acquisition and SHALL NOT claim a canonical task; it SHALL NOT silently flatten, repair or hide the chain.  
5. <a name="3.5"></a>WHEN duplicate-of is added, changed or removed, the system SHALL preserve original tasks, field values, comments and statuses except for separately requested task edits in that same operation; ordinary reads/writes SHALL continue to address the selected original UUID and SHALL NOT be redirected to a canonical task.  

### 4. Protected local link mutation

**User Story:** As an MCP caller, I want guarded link changes, so that retries and concurrent edits do not silently replace relationships.

**Acceptance Criteria:**

1. <a name="4.1"></a>Standalone `create_task` and `update_task` SHALL accept explicit link additions by target UUID and removals of precisely identified saved incident occurrences; omission SHALL leave existing links unchanged, creation SHALL allow additions only, and one request SHALL contain at most 50 link directives. Malformed shapes SHALL reject before key acceptance; validly shaped invalid references/graphs SHALL yield defined domain outcomes. Target UUID alone SHALL NOT authorize removal of an ambiguous/corrupt occurrence; IF exact saved source/edge identity cannot be established, the system SHALL return repair unavailable without effects.  
2. <a name="4.2"></a>A new update, including a semantic no-op, SHALL require the selected source's current task revision; every other existing endpoint whose active incident membership changes SHALL require its current task revision, and creation SHALL require those preconditions for its existing endpoints. Participating Transit writes (standalone and per-item batch executions through the shared MCP write coordinator) SHALL be coordinated, and identity, affected cardinality/cycle invariants and all preconditions SHALL be validated against the complete proposed result and locally saved graph immediately before applying and saving, with explicit removal-only repair governed by 5.4; IF required evidence cannot be established or a precondition differs, the domain change SHALL have no effects and return identifiable conflict/unavailable evidence.  
3. <a name="4.3"></a>WHEN an accepted create/update changes fields and links, all requested task fields, every attributable edge change and the protected terminal saved result SHALL commit together in the originating local store or have no domain effect; this guarantee SHALL NOT extend across a generic batch, another store or later CloudKit synchronization.  
4. <a name="4.4"></a>Link edits SHALL retain T-2380's exact tool/local-store key binding, seven-day terminal replay expiry, immutable saved outcomes, key-reuse conflict and rejected/in_progress/uncertain recovery rules; retained replay SHALL precede current identity/graph/revision validation, including after subsequent edits/removal/deletion.  
5. <a name="4.5"></a>WHEN shared context edits are unsaved, the operation SHALL neither expose, save nor roll back those edits as link handling; a new write unable to establish clean owned changes and saved precondition evidence SHALL stop with an explicit unavailable or uncertain outcome as warranted by acceptance evidence, while safe read-only retained replay SHALL remain possible.  
6. <a name="4.6"></a>A link mutation SHALL obey the existing tool enablement, loopback access and durable-store restrictions; it SHALL introduce no privilege bypass, automatic repair, force-write, key reset or task deletion path. IF result delivery fails after possible commitment, the response/recovery evidence SHALL require original-key retry or reconciliation rather than claim no effect.  

### 5. Saved revisions, removals and synced invalid states

**User Story:** As a maintainer, I want truthful graph and revision evidence, so that removal and synchronization cannot silently change the meaning of a saved record.

**Acceptance Criteria:**

1. <a name="5.1"></a>Current task revisions SHALL remain `r1:[0-9a-f]{64}` content tokens and cover existing fields/comments plus normalized active incident occurrence identity/type/endpoints; current saved results SHALL identify their graph-covered revision contract. The coverage transition SHALL include an explicit empty incident set, so pre-feature tokens SHALL NOT authorize new fresh writes, including status/property updates; those requests SHALL return the existing no-effect revision conflict and current graph-covered record/revision. Target labels/status, removal-retention metadata, blocker assessment and transitive canonical path SHALL be separately identified observation evidence.  
2. <a name="5.2"></a>WHEN a specific occurrence is removed, subsequent local saved readback SHALL exclude it from active relations and preserve its removed identity under a documented bounded retention policy; an explicit later re-add SHALL create a distinct active occurrence identity rather than revive the removed occurrence. An already-absent removal SHALL create no additional domain removal record or timestamp/token change. Removal-evidence expiry SHALL NOT change active-link/task content tokens or imply safe uncertain-write retry; removing a link SHALL NOT delete either task or its comments.  
3. <a name="5.3"></a>WHEN an endpoint is deleted or cannot be resolved after sync, surviving tasks SHALL report the dangling/ambiguous relation without silently retargeting or treating it as a satisfied blocker/canonical target. Explicit removal SHALL use exact saved source/occurrence evidence and require no nonexistent endpoint revision; IF exact repair identity cannot be established or any existing affected endpoint UUID is ambiguous, it SHALL return repair unavailable without choosing a physical record. Removal of one identified occurrence SHALL NOT remove other equivalent physical occurrences implicitly.  
4. <a name="5.4"></a>WHEN imported changes create multiple equivalent physical occurrences, cardinality/cycle/endpoint faults or conflicting active/removal evidence, the system SHALL preserve and identify each available conflicting occurrence rather than arbitrarily choose a valid logical identity, blocker or canonical target. Explicit removal-only repair SHALL be allowed to reduce precisely identified invalid evidence without requiring all corruption to be repaired in one request; invalid evidence outside the affected change SHALL NOT prevent such removal, and no unrelated addition or automatic cleanup SHALL accompany it.  
5. <a name="5.5"></a>Caller documentation and readback SHALL state that validation/revisions describe locally imported saved evidence and protection applies to participating Transit writes. Independent writers or sync imports MAY change that evidence between validation and save and temporarily leave inconsistent links that MAY remain until explicit repair; subsequent saved readback SHALL derive current blocker/canonical assessments and detect/report available missing/ambiguous/invalid endpoint, identity, cycle, cardinality and active/removal conflicts under 2.3, 3.4, 5.3 and 5.4, without automatic repair or a claim of global remove-wins semantics. A valid endpoint status change SHALL update its assessment rather than be labeled a historical race conflict.  
6. <a name="5.6"></a>WHEN schema/revision coverage is introduced, preexisting tasks SHALL remain readable with no links, original task history and unrelated fields unchanged. Retained historical receipts/pages SHALL retain their original bytes/revisions/meaning; exact protected receipt replay SHALL precede fresh-write coverage validation. Old captured/receipt evidence SHALL be explicitly distinguishable as lacking graph coverage rather than reminted or relabeled, while T-2384/T-2383 validators SHALL retain their approved r1 token format.  

### 6. Relationship queries and frozen observations

**User Story:** As an agent, I want filtered and coherent relationship readback, so that I can select work without independently joining changing records.

**Acceptance Criteria:**

1. <a name="6.1"></a>Ordinary `query_tasks` SHALL support link presence/type and opposite-endpoint UUID filters plus unblocked selection, combined with existing selectors/filters. `blocks`/`blocked-by` SHALL match the candidate's named dependency view; relates-to SHALL match either orientation; introduced-by/duplicate-of SHALL support explicit outgoing or incoming direction, default outgoing. Incoming duplicate-of SHALL find direct target tasks, which may themselves be duplicates, and SHALL NOT imply transitive incoming matching; outgoing duplicate-of SHALL find duplicates. Unsupported/conflicting options SHALL reject without changing unrelated ordering/status/count semantics.  
2. <a name="6.2"></a>Full task detail SHALL expose incident links, explicit invalid-edge diagnostics, direct duplicate/canonical resolution and blocker assessment where established; queries omitting link bodies SHALL retain the authoritative covered revision, and omission SHALL NOT be interpreted as an empty link set.  
3. <a name="6.3"></a>Every relationship-aware query SHALL use one immutable saved local observation for selected tasks, endpoint identities/statuses, edges and required comments; unsaved insert/edit/delete state SHALL NOT appear. A required fetch/capture failure SHALL be a failed read rather than an empty relation, no blockers or successful partial canonical resolution.  
4. <a name="6.4"></a>New ordinary captured queries SHALL identify graph-evidence coverage and support relationship filters/readback within their declared task scope; cross-project closure SHALL support evaluation without making closure tasks selectable or changing portfolio totals. Retained graph-aware pages SHALL preserve original edges, assessments, revisions, metadata and expiry after edits/imports. T-2382 reusable queries SHALL retain their approved project/status options and exclusion of comment bodies; graph filters against them SHALL return the existing unsupported-option error. Views lacking graph evidence SHALL explicitly report unavailable graph coverage rather than live-enrich or imply no links. Added retained evidence SHALL remain within unchanged five-minute/eight-view/16-MiB lifecycle/accounting limits.  
5. <a name="6.5"></a>Relationship capture/filter/traversal and result encoding SHALL fit T-63's five-second covered-read budget and eight-unfinished-physical-read limit; deadline or capacity failure SHALL return the defined typed failure without partial success or late cursor/snapshot publication. Graph traversal SHALL stop on repeated identities and budget/capacity exhaustion.  
6. <a name="6.6"></a>Results SHALL retain T-63/T-2382 original `snapshotId`, `asOf` and freshness meaning, and T-2383 latest-only structured/text parity and failure categories; a recent import SHALL NOT imply complete remote graph convergence, and missing supported navigation SHALL remain explicit rather than produce guessed URLs.  

### 7. Native visibility and compatibility

**User Story:** As a user, I want to see recorded relationships, so that agent-managed links do not remain hidden in my tasks.

**Acceptance Criteria:**

1. <a name="7.1"></a>WHEN native task details show a saved task, they SHALL show recorded incident link types, target identities/labels and explicit unresolved/canonical diagnostics using existing task-detail and navigation patterns; labels SHALL NOT be taken from unsaved endpoint drafts, and no inline link editor or consolidation action SHALL be added.  
2. <a name="7.2"></a>WHEN a resolved relationship target is selected in native task details, navigation SHALL open that exact task UUID through existing in-app navigation; missing/ambiguous targets SHALL remain a diagnostic rather than open an arbitrary task.  
3. <a name="7.3"></a>Existing create/update/status/comment behavior without link arguments SHALL retain field semantics, permissions and retry guarantees, with current graph-covered revisions required for fresh preconditioned writes under 5.1. T-2384 batches SHALL initially reject link directives as unsupported shape before any item/key acceptance, retain their approved fields and ordered per-item/advisory-preview semantics, and SHALL NOT gain incidental multi-endpoint link changes, implicit revision chaining, whole-batch graph atomicity or consolidation undo.  
4. <a name="7.4"></a>Published schemas and caller guidance SHALL document type/direction normalization, cardinalities, preconditions, no-op/repair/removal behavior, blocker/canonical rules, saved-only scope and link/revision compatibility; accepted historic receipt shapes and omission of graph evidence SHALL be explicit.  

### 8. Verifiable behavior

**User Story:** As a maintainer, I want edge-case coverage, so that graph changes cannot bypass write or read safety.

**Acceptance Criteria:**

1. <a name="8.1"></a>Automated verification SHALL exercise all type directions/inverses, reversed association deduplication, self/duplicate/colliding UUIDs, cross-project links, add/remove/retarget/no-op/cardinality behavior, dependency and duplicate cycles, multiple attribution sources, Done versus Abandoned blockers, canonical chains and invalid-graph repair.  
2. <a name="8.2"></a>Automated verification SHALL exercise coordinated participating writes, immediate saved validation, all-or-none source/edge/removal/terminal-receipt saving, revision races and documented independent-writer limits, retained replay before graph lookup, exact-key mismatch, restart/save/delivery failure and uncertainty, dirty UI contexts and independently observed saved readback, without weakening T-2380 guarantees.  
3. <a name="8.3"></a>Automated verification SHALL exercise migration, endpoint deletion/dangling links, explicit removal/re-add and imported invalid/removal conflicts, scoped closure evidence, omitted bodies/revision coverage, frozen cursors/reusable views, deadlines/capacity/late publication and native exact-UUID navigation; no test SHALL claim CloudKit-wide convergence from local evidence.  
