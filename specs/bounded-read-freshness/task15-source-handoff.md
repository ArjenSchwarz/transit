# Task15 source handoff

Historical source-preparation checkpoint at fa58dc0. Subsequent integrated GREEN is complete: see [task15-green-acceptance.md](task15-green-acceptance.md) and [Task16 acceptance](task16-green-acceptance.md). The readiness limitations below describe this earlier source-only checkpoint.

- Source: `fa58dc0d67aee5dd30e228f30b74ae89c8484953`, parent `48266589abad1133f8443aa99673c65a3f69c517`.
- Worktree: `/Users/arjen/Documents/Codex/2026-10-03/task/transit-t63`, branch `T-63/bounded-read-freshness`.
- Earlier actual RED: `ffde7266813f7a80c7efac7f1487a611b4d656d8`; see [Task14 acceptance](task14-red-handoff.md).

The bounded sink counts active plus queued scalar records and drops excess records. Its dedicated writer runs outside the sink and publication locks. Entries retain the original operation ID, tool, generation, admission, external deadline and internal cutoff through terminal selection, late discard and physical finalization. Measurements cover worker scheduling, the MainActor handoff, refresh policy/wait, saved capture, transformation, actual final RPC encoding and historical component assembly. Modern production still rejects wire arrays. Tool descriptions explain saved capture metadata, policy, import-evidence limits, frozen replay and explicit backoff. Capture identity, freshness evidence, pagination and publication behavior are preserved.

Implementation was delegated under the local make-it-so skill. Coordinator design-critic review identified and resolved the initial OSLog compiler expression, misplaced terminal bookkeeping, missing actor queue measurement, omitted log deadline context and ordinary/reusable query wording. Root independently verified all thirteen source hashes and nine artifact hashes. Original diagnostic/caller suites are byte-identical; transferred Handler/App and the ordinary snapshot store are unchanged.

## Verification readiness

Targeted strict SwiftLint (thirteen paths, no cache), Swift frontend syntax parsing and diff checks passed. Independent standalone OSLog typechecking passed using a private module cache; syntax parsing is not full actor/macro/type checking. No app/project build or runtime tests ran for this GREEN source. No T63 heavy job or retained test host is active; T2384 owns the shared heavy slot.

Next selected suites are `TransitTests/MCPReadDiagnosticsTests` and `TransitTests/MCPReadCallerContractTests`: ten declarations/thirteen expanded bodies, with their original assertions. Parent must grant the slot before guarded Xcode27 build/preflight/exact inventory and serial execution. Preserve finalized results, real counts, normal exit/drain evidence and source pins. Source readiness is not runtime acceptance.

Evidence is local: `/Users/arjen/Documents/Codex/2026-10-03/task/t63-review-evidence/task15-source-preparation/manifest.json` and `/Users/arjen/Documents/Codex/2026-10-03/task/t63-review-evidence/task15-root-review/review.json`.

## Owner application and remaining contract gap

Owned app dependencies install the bounded application sink. Production coordinators need two narrow owner patches: `handler-diagnostics.patch` supplies `readService?.diagnostics ?? .disabled` when the handler constructs its coordinator; `app-diagnostics.patch` supplies `reads.diagnostics` to the explicit app coordinator. They do not change admission, publication, preferences or lifecycle. Exact pre/post hashes and distinct local/recipient revisions are in `owner-patches.json`; both read-only application checks passed. Parent routes the handler patch to T2383 and the app patch to containment ownership. Neither file was directly edited.

A pre-existing error-contract gap remains: `MCPReadService.prepareFailure` selects `READ_FAILED` for project/milestone failures but emits only their message text. Machine categories still appear in failure metadata; no successful capture metadata is invented. Task15 does not silently alter this wire shape. Before integrated acceptance, a focused actual RED/GREEN repair must assert project/milestone storage, serialization and incoherence error codes as well as metadata categories. The exact defect is documented in `read-failed-wire-defect.md` beside the source manifest.

## Settings seam delivery

Separate sole-file commit `48266589abad1133f8443aa99673c65a3f69c517` adds the internal MainActor `subscriptionBroadcaster` getter returning the existing private broadcaster. Pre/post hashes are `c2fe9f43e2283c792a98691d349da34ff7fe5dcb3545e5fb23e2c5a40d1cf062` and `13cc27828c387fe4e62ce987ae593912ae61ae57d0e6096c3a6117f4dfcd3238`. Preferences, observer, storage and legacy APIs are unchanged. Independent exact-byte review, Swift parsing and diff checks passed. Patch and evidence: `/Users/arjen/Documents/Codex/2026-10-03/task/t63-review-evidence/settings-subscription-seam/`.

Keep this getter outside T2383's pinned Task18 RED until the permitted bundle. Later legacy Settings cleanup waits for T2383's exact registration symbols and coordinated common caller/test migration; no replacement stream engine or second observer was introduced.

No push, merge, deployment, live settings, publishing or routine phone upload occurred. Full platform validation and full pre-push-review including parent-controlled Pulsar publication remain later gates.
