# Implementation: MCP Write Safety

Branch: `T-2380/mcp-write-safety` | Ticket: T-2380

All 18 coding tasks are complete, including phase-review and application-gate fixes. The committed implementation passed macOS and iOS gates. The pre-push working-tree fixes described below passed focused production probes and review; the earlier full-suite results are not a fresh run of those fixes.

Implementation commit: `0e23351`. Separate phase changelog commit: `1bcd6d6`.

## Changes

- Added same-store receipts, durable local payload guards, scoped process locking, and seven-day terminal replay retention.
- Added content revisions and full saved-record outcomes; routed eight protected tools through the write coordinator.
- Split creation allocation from synchronous application, preserving existing UI/Intent service behavior and deferred atomic saves.
- Retained one coordinator for the app lifetime; added restart, notification, batch, cancellation, fallback, and imported-state regression fixtures.
- Migrated legacy callers and parity tests without masking malformed-input checks. Preserved tolerant create metadata behavior and fixed numeric identity collisions.

The phase design-critic's numeric-identity and legacy-test findings were fixed and re-reviewed. No material findings remain from that review.

## Confirmed Verification

- Standalone probes compiling actual production SwiftData models and services: additive migration, process termination around save, atomic status/comment/receipt outcomes, read-only save failures, and ghost cleanup.
- Foundation, guard, service, and coordinator probes: canonical numbers, revisions, all eight commands, exact replay, conflicts, concurrent keys, interrupted outcomes, expiry repair, locking, and pending-edit preservation.
- Numeric red probes reproduced adjacent-double collisions and changed-payload replay; green probes passed adjacent values, finite exponent extremes, and signed-zero equivalence.
- Parity probe passed 36 combinations using production serializers and the test projection.
- `make lint`, source syntax checks, and `git diff --check` passed.
- Focused application checks passed 115 tests with no failures.
- `make test-quick` passed all 1,853 macOS unit tests, including the MCP application/transport suites.
- `run_silent -t 15m make test` completed successfully with all 1,308 iOS unit/UI tests passing. An earlier five-minute wrapper timed out and is not counted as a successful command.

The standalone compiler option `MCP_PROBE_SWIFT_FLAGS=-disable-sandbox` disables Swift's nested macro-plugin sandbox only; commands still run inside the unchanged Codex sandbox.

## Application-Gate Fixes

After the permission restrictions were resolved, full compilation exposed a missing SwiftData import and a test returning a non-Sendable model from a child task. These were corrected without changing production actor ownership. The first runtime gate then exposed 16 contract/fixture failures; fixes restored selector precedence, milestone normalization and diagnostics, summary-query shape, and explicit coordinator fault injection. Intentional safety-input/full-write-response changes received matching assertions.

The prior build-cache and Git-index restrictions are resolved. CloudKit Production schema publication remains a separate release prerequisite in [prerequisites.md](prerequisites.md).

## Evidence

Full logs are retained outside the repository:

- `/tmp/t2380-storage-green.log`, `/tmp/t2380-foundation-green.log`, `/tmp/t2380-services-green.log`
- `/tmp/t2380-contract-green.log`, `/tmp/t2380-lifecycle-coordinator.log`
- `/tmp/t2380-review-fix-green.log`, `/tmp/t2380-parity-probe.log`
- `/tmp/t2380-parity-lint.log`, `/tmp/t2380-parity-syntax.log`
- `/tmp/t2380-foundation-test-quick.log`, `/tmp/t2380-foundation-test-quick-offline.log`, `/tmp/t2380-handler-typecheck.log`
- `/private/tmp/t2380-focused-tests.log`, `/private/tmp/t2380-app-test-retry.log`, `/private/tmp/t2380-ios-tests.log`

Complete test/build reports are retained in `DerivedData/Logs/Test/`, including:

- `Test-Transit-2026.10.03_11-54-30-+1000.xcresult` — focused tests.
- `Test-Transit-2026.10.03_11-56-36-+1000.xcresult` — full macOS suite.
- `Test-Transit-2026.10.03_14-15-51-+1000.xcresult` — completed iOS unit/UI suite.

## Pre-Push Review

Four findings are fixed in the working tree: quadratic guard maintenance, incomplete terminal replay validation, lossy duplicate integer validation, and stale MCP documentation. Guard reconciliation now validates one receipt pass and one keyed guard snapshot before changes. Complete terminal outcomes are required before replay; malformed results preserve their bindings and return uncertainty. Integer/Boolean validation reuses the shared intent helpers.

Current focused coordinator/foundation probes passed, including 21 malformed-terminal cases and exact integer boundaries. Lint, handler/lifecycle syntax checks, and whitespace validation passed. Logs: `/private/tmp/t2380-prepush-focused-final.log` and `/private/tmp/t2380-prepush-validation-final.log`.

The configured structured-test runner map matches Swift only through a root `Package.swift`. This Xcode-only repository has no matching runner, so the pre-push page reports no fresh JUnit or coverage data. The fixes are included in the subsequent commit workflow, whose application gates are recorded separately from that review snapshot.

## Beginner Explanation

### What This Does

A caller gives each logical write a key. Transit remembers the saved result and returns it when that same request is retried, even if the record later changes or disappears. An update also includes a revision from the caller's read; a different current revision rejects the write instead of overwriting intervening edits.

### Why It Matters

A timeout cannot tell a caller whether a save happened. The saved receipt answers that question when storage is readable. A durable local guard keeps the key reserved when the outcome cannot be recovered, preventing a blind repeat.

### Key Concepts

- A receipt stores the saved record and outcome with the write in one local save.
- A revision is a fingerprint of covered local content, not a global edit counter.
- A retry repeats the same key and arguments; a corrected request uses a new key.

## Intermediate Explanation

### Changes Overview

`MCPToolHandler` translates eight protected tools into typed commands for an app-lifetime coordinator. Read services still share the UI's main context. Creation prepares display IDs before insertion; the final validation, mutation, result encoding, and receipt save contain no suspension.

### Implementation Approach

The coordinator reserves a durable guard, confirms an accepted receipt, prepares asynchronous work, saves a baseline, and checks the current record snapshot. Domain changes and terminal response are committed together. Recovery reads durable receipts rather than inferring success from target existence; replay validates the complete stored envelope. Maintenance validates receipts and guards once per pass, then repairs expiry or removes eligible entries without repeated scans.

### Trade-offs

Receipts sync with the domain store, while their namespace and guards remain local. Content hashes detect changes from any local writer without adding counters, but identical restored content has the same token. Baseline saves can persist other pending local work, matching the shared-context behavior.

## Expert Explanation

### Technical Deep Dive

Canonical request identity preserves absent/null, Boolean/number, and original payload differences while ignoring object key order. Revisions hash exact persisted scalar state, assignment UUIDs, and comment snapshots. Terminal replay checks metadata timestamps, entity identity, complete records and revisions, deletion preimages, optional status comments, and rejected/conflict details. All binding validation precedes maintenance writes; unresolved guards never expire through terminal cleanup.

### Architecture Impact

The local advisory lock and MainActor synchronous commit section protect this process/store boundary. One-pass maintenance is linear in retained records and payload size. It avoids a persistent in-memory cache that could become stale, while retaining fail-closed validation before any file or receipt deletion.

### Potential Issues

Preconditions cannot detect CloudKit edits not yet imported, and later sync can still conflict. Replay protection ends at the returned terminal deadline; unresolved outcomes require reconciliation. Schema publication is a separate release prerequisite. No global deduplication, batch atomicity, or automatic force-retry is claimed.

## Completeness Assessment

- Fully implemented: all eight protected writes, scoped keys, replay/recovery, revision checks, structured outcomes, retention, and documented service/API integration. All review findings are resolved.
- Partially available review evidence: focused production probes and validators pass; fresh structured whole-suite and coverage data are unavailable under the configured runner map.
- Missing implementation requirements: none identified. Release still requires the documented CloudKit schema publication; batch mutations and UI conflict rebasing remain separate scope.

## Bounded-Query Integration

After rebasing onto T-2379's bounded task queries, the user approved complete comment-covered revisions for every full read. `includeComments:false` hides comments from the response while still capturing their state; summary reads without comments retain zero-fetch behavior. UUID-keyed serialization memoization captures duplicate batch references once, and continuation pages preserve the original record/revision. The changed guarantee and alternatives are recorded in Decision 6 and the batch-query spec.

Post-rebase verification passed 1,874 macOS tests and 1,308 combined iOS unit/UI tests, plus lint and syntax validation. New integration cases cover list/single/UUID/display batches, omitted comment payloads, fresh comment edits, frozen continuations, and stale-write rejection.
