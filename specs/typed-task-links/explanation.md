# Typed links — design self-validation

Current contract: owner `Sentinel_c95239aefa6481919303c2353b8a9e9c` approved participating Transit writes with pre-save validation and outside-writer conflict reporting (decision_log.md ADR 4). The historical all-independent-writer/import validation-to-save fence and persistence-redesign completion gate below are superseded. Original tests, failures and approvals remain historical evidence; owned same-store domain/receipt saving and T-2402 deferral remain unchanged.

## Beginner level

### What this does

A link records a fact between two saved tasks. Dependencies answer whether direct prerequisites are Done; duplicate links point along a chain to its last task. Names are labels, while UUIDs identify tasks. If an identity is missing or ambiguous, Transit shows the problem rather than guessing.

### Why it matters

Agents can select work and understand duplicates without parsing prose. A guarded edit checks the saved version of every task whose visible link set changes. It saves the task, links and retry result together locally. Unsaved drafts stay private and can make a fresh write unavailable.

### Key concepts

An occurrence is one specific saved link. Removing it deletes that link; adding the same relationship later creates a new occurrence. Short-lived removal evidence helps recognize an exact retry. Expiring that evidence does not bring back the deleted link. A revision is a fingerprint of saved task fields, comments and active incident links; a snapshot is one frozen observation used throughout a read.

## Intermediate level

### Changes overview

Two scalar SwiftData entities hold immutable active occurrences and bounded repair evidence in the existing store. A value graph service drives normalization, dependency SCCs, duplicate walks, exact removal planning and native readback. Existing snapshot hashing, T-63 saved capture, T-2384 clean-context write policy and T-2383 result encoding gain explicit graph integration.

### Implementation approach

Normalize dependencies to blocker→blocked and associations by UUID ordering. Compare all physical identity matches. Delete the exact occurrence and insert its removal evidence in the same task/terminal-receipt save. Replay retained outcomes before looking up current tasks. After asynchronous preparation, validate the complete proposed graph and endpoint tokens again at a proven saved local commit boundary.

### Trade-offs

Endpoint task revisions avoid a second graph concurrency token but allow unrelated endpoint edits to conflict. Platform occurrence deletion avoids a custom sync tombstone protocol; the small separate evidence entity is necessary to retain bounded exact-removal recognition without tying expiry to the active graph. Refusing dirty-context writes preserves drafts at the cost of requiring the user to save or cancel first. Complete cycle evidence can cause bounded read failure on large graphs instead of partial unblocked claims.

## Expert level

### Technical details

Hash canonical incident occurrence tuples plus an explicit graph contract/empty array under existing r1 syntax. Physical multiplicity must remain visible; labels/status/derived paths and removal retention are not source-owned covered content. Link-only imports participate in the capture fence. UUID-key indexes retain all physical matches and SCC traversal stays iterative/budgeted. Reusable project/status snapshots cannot be live-enriched with graph data.

### Architecture impact

Schema/snapshot call-site parity is mandatory across app, tests and probes. Shared read/coordinator files remain foundation-owned until handoff. Receipt bytes are historical evidence and cannot be reminted at upgrade. Native relationship navigation must validate destination uniqueness both on click and at UUID window resolution.

### Potential issues

MainActor serialization alone does not exclude peer-context/store imports. A generation check followed by save is not independently proven atomic; the early implementation gate must establish the foundation's saved boundary or leave graph writes unavailable. SwiftData additive migration and remote deletion behavior require disk/development-sync evidence, not an inference from local tests. Repair evidence expiry cannot substitute for framework history retention or globally prevent delayed conflicting imports.

## Validation findings

### Gaps and logic checks

The initial single-row retirement proposal coupled active state to evidence expiry. The current design uses physical active-occurrence deletion and separate evidence, so cleanup cannot reactivate a link. Repair evidence expiry can end evidence-based conflict warnings and change derived assessments of an already imported active row; it neither reinserts a row nor proves remote correctness. Thirty days lacked a personal-tool use case; the approved seven-day repair horizon aligns receipts. The commit-boundary and migration assumptions cannot be proven in spec-only work and have early verification/fail-closed paths.

### Questions

The owner approved seven-day exact-removal recognition with design checkpoint `56e9ad5` (`Sentinel_775be6f4fc6c8191a9d7ccf1d0c04557`). Design review must challenge whether the selected commit fence can meet the approved local invariant without a second write engine.

### Recommendations applied

Keep removal evidence separate from platform deletion/history; reject unknown post-expiry selectors; include empty incidence in every current task token; recheck ambiguity during native navigation; sequence migration/commit-boundary validation before dependent feature work.
