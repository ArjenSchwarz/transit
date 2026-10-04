# T-63 requirements approval packet

Read `requirements.md` for the six user stories and 29 testable acceptance criteria. Scope/name and the recorded behavioral decisions are approved; this packet requests final requirements approval before design begins.

## Review synthesis

The design-critic and external Codex/Kiro reviews exposed ambiguous batch delivery, capture/import applicability, refresh outcomes, cursor policy, failure categories, and admission accounting. The revised requirements make each explicit. Final internal critic and peer validation found no remaining requirements wording blocker; successful external raw reports and the finding-by-finding synthesis are included.

The five-second response guarantee is preserved. Source inspection shows transport/response value types already separated from MainActor, so an independent timeout coordinator is a credible design direction; merely returning after MainActor resumes is insufficient. `deadline-feasibility-note.md` explains the evidence and the proof still required during design.

## Choices still proposed

1. **Import recency: 30 seconds.** A completed relevant import within this age is `recent_import`, not proof every remote edit arrived. Unknown evidence stays unknown.
2. **Admission: eight unfinished reads.** Includes queued/running work that outlives its timeout. An occupied capacity yields `READ_BUSY`; this does not promise a transient-memory limit or automatic recovery from permanently blocked work.
3. **Latency diagnostics.** Server diagnostics record phase durations and correlate late completion/discard so the reported 30–50 second incident can be investigated without assuming CloudKit caused it.

Do the requirements look good or do you want additional changes? Approval should explicitly cover the complete EARS document, including these three recommendations. Design, tasks, and implementation are separate gates.

## Design evidence required next

- Independent deadline delivery and complete read-only batch encoding while MainActor is blocked.
- Correct unfinished-work accounting across timeout and service stop/restart.
- Supported coherent multi-entity capture, saved-write visibility, and import evidence applicable to that capture.
- Compatibility with T2382's retained summary/task-query identity and lifecycle.
- Diagnostics that do not delay a bounded response.

No implementation, push, merge, deployment, or Pulsar publication has occurred. The local requirements skill requires final requirements approval before moving to design; the parent conversation owns the approval request.
