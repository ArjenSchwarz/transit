# T-2455: Persist bounded MCP read failure diagnostics

## Investigation and scope

The Oct12 summary/full-read timeout incident and reported one-to-two-day uptime correlation have no confirmed live cause. Oct14 PID81409 was minutes old; current summary/full reads took 0.25–0.39 seconds. An existing isolated prototype reproduced 4.85-second timeouts during synthetic MainActor blocking, retained all eight physical slots until work drained, and published no late results. This demonstrates a mechanism, not the incident's cause.

Confirmed observability defects: phase timings are only reported after work finishes, existing logs are debug level, and neither process age nor oldest unfinished-worker age is recorded. Bounded log queries yielded no retained events. The user approved implementing diagnostics, not changing capture, budgets, admission, deployment or app lifecycle.

## Proportionate design (recorded before final verification)

- Track active phase/start under the existing publication domain. Terminal timeout/busy evidence snapshots only bounded scalars from at most eight entries. Process-start age comes from the current process's Darwin metadata once, then advances monotonically; unavailable age remains null.
- Enqueue snapshots without disk I/O or logger calls under the domain. The existing bounded diagnostic writer queue writes failures independently of MainActor. Under saturation a failure can retire a queued ordinary debug event; dropped events are counted. If every retained event is a failure/active write, further events are counted as dropped. Admission itself remains unchanged.
- Persist only timeout/busy summaries in a fixed-schema rolling cache journal, at most 64 records and 64KiB. Read old input only within the byte cap, retire corrupt/oversized content, atomically replace the journal. Tool names are allowlisted. No task contents, task UUID/display IDs, arguments, result buffers, secrets or operation IDs enter the journal. Notice logs expose only those safe scalars; normal detailed diagnostics remain debug.
- Distinguish deadline, cancellation, lifecycle and admission causes, so a listener stop returning timeout bytes cannot be mistaken for an exhausted deadline.
- Keep original five-second response/4.85-second cutoff, physical slot ownership, late publication fences, receipt semantics and read schemas.

Journal: `URL.cachesDirectory/<bundle identifier>/MCPReadFailures.json`, inside the app's own runtime sandbox. OS may purge caches; disk/log failures must not alter responses. Across relaunches the last bounded records survive when the cache is retained. This is diagnostic evidence, not a durable audit or an automation that polls live data.

## Verification plan

Focused regressions cover timeout while MainActor blocks, active capture phase while synchronous work stalls, busy oldest-worker age, lifecycle reason, capacity/drop behavior and writer isolation, journal rollover/reload/oversized input, and payload redaction. Run the existing coordinator and diagnostics suites plus lint and relevant host guards. No broad UI rerun: this change exposes no UI and the user excluded broad UI reruns. Build/test products and fixtures are isolated; no private store copy or live cloud experiment.

## Implementation / results

Final verification: 21 focused macOS Swift Testing declarations passed (9 coordinator, 5 existing diagnostics, 7 failure-journal tests), zero failures/skips; isolated iOS Debug build passed; make lint passed all host preflights and SwiftLint with zero violations across 749 files; git diff --check passed. The verified /tmp source mirror exactly matched workspace Swift bytes, recorded in evidence/t2455-source-manifest.json.

Four read-only review agents examined reuse, quality, efficiency and spec/tests. They identified two diagnostics gaps: prepared READ_BUSY results mapped to generic failure and skipped journal persistence, and deferred historical batch fallback lost lifecycle reason. Both were corrected. The two focused regressions failed with prior behavior in the temporary red fixture (5 pass/2 fail) and passed unchanged in the final run. These are proven diagnostic defects; neither establishes the live uptime timeout cause.

The initial Documents-based macOS test invocation stalled in XCTest/CoreSymbolication file opening; a one-second sample was preserved. Only its exact isolated host PID93400 was terminated, and the run ended incomplete with exit65. Moving identical verification sources to /tmp resolved the runner delay. Installed Transit PID81409 was untouched. The reported stall cause is not claimed to be a Transit defect. Early compiler/lint repair attempts were not counted as runtime regression evidence.

Full repository and broad UI suites were not run: this authorized change has no UI; focused diagnostics/coordinator gates and cross-platform compilation were used, with no broad UI reruns per user instruction. UI targets were compiled by the shared scheme but no UI tests were executed. No code coverage claim is made. XCResult preserved one priority-inversion warning from the deliberate blocked-writer fixture; no warning was suppressed, and it is not proof of a production bottleneck.

Local evidence lives in the parent workspace's evidence directory: t2455-final-focused.log, t2455-final-summary.json, t2455-review-red.log, t2455-review-red-summary.json, t2455-ios-build.log, t2455-lint.log and the source manifest. Cache/journal failure cannot change response outcome, though it may lose evidence.

The first historical investigation happened before this branch; this report is a retrospective investigation summary and contemporaneous implementation design, not an invented earlier approval/spec.

## Publication status

Implementation committed locally as b8e07d7 on T-2455/bugfix-read-timeout-diagnostics. Automatic approval review denied the requested git push to ArjenSchwarz/transit, stating that the trusted request did not explicitly authorize that exact remote push/draft PR. No push ran, and draft PR creation was not attempted. No alternate or indirect publication was attempted. Explicit approval is pending; T-2455 remains In Progress. The prepared PR body is in the parent workspace evidence/t2455-pr-body.md. All implementation and verification work is complete; publication is the remaining blocker.

### Publication approval resolved

New trusted verbatim user instructions explicitly authorized personal-repository feature pushes and PRs without personal/secret data. The single instructed retry succeeded; remote head 3e5e3846533beade7379dbe3a26188061065a913 was verified. Draft PR #259 was created and attached: https://github.com/ArjenSchwarz/transit/pull/259. No merge, installation, live app restart or deployment occurred. A bounded full read for the ticket-status update returned READ_TIMEOUT after draft creation; it was preserved as failure, not treated as empty results. The patch is not installed in that process.

### Live recurrence during publication

At 2026-10-14T06:15:58Z, listener PID81409 was unchanged, with ps elapsed uptime 53:33, CPU0.0% and RSS25104KiB. The first bounded full read for the ticket's current revision returned READ_TIMEOUT. One full-read retry after backoff also returned a typed READ_TIMEOUT (HTTP/parse elapsed 5.0965s, isError true, no usable revision). The probe cap was two attempts; no further reads or status write were attempted. Evidence is evidence/t2455-publication-status-read.json in the parent workspace. These observations establish that this symptom can occur in a process less than one hour old; a day-or-two uptime threshold is not necessary. They do not establish actor, sync, App Nap, queue, storage or leak causality. The diagnostics patch is not installed in that process. T-2455's Ready for Review tracking update remains blocked by unavailable current read evidence; the GitHub draft itself is published.

## Approved elapsed/cutoff refinement

The degraded live trace identified 5219.201ms synchronous capture with approximately4.7ms queueing and7ms refresh; physical work drained1→0. Terminal selection was5163.039ms against the4850ms cutoff. The parent authorised two additional content-free numeric fields in PR259: per-request admission elapsed and nonnegative cutoff overrun. They use the same original monotonic context and are independent of phase age and oldest-worker age. Refinement verification: 22 focused macOS tests passed, isolated iOS Debug build passed, lint passed with zero violations, and all four targeted review areas were clear. The exact verified Swift-source manifest is in evidence/t2455-elapsed-source-manifest.json. Tests distinguish this request’s clock from oldest-worker age, verify deterministic elapsed/overrun and early clamping, and persist both numeric fields through journal reload. No capture optimization or snapshot-contract change is included.
