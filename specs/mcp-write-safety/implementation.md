# Implementation: MCP Write Safety

Branch: `T-2380/mcp-write-safety` | Ticket: T-2380

All 18 coding tasks are complete, including phase-review and application-gate fixes. The implementation is verified on macOS and iOS, and the final review has no material findings.

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
