# Prerequisites for structured MCP results

These prerequisites track coordination and installed-client readiness separately from the approved implementation tasks. Testing is owner-approved; each application run still requires the parent's exclusive slot coordination. Live data/client activation remain held.

## Before shared integration or application tests

- [ ] Parent confirms T63's provider-regression fix and explicit common-file ownership handoff at a recorded commit before tasks14–19 edit shared handler/types/router/schema/lifecycle or owner test helpers. Isolated Results/Protocol modules can be prepared after task approval; no task waits on production T2384 completion.
- [ ] Parent coordinates the heavy build/test slot before each application build/test, including RED runs. Task17's selected acceptance is complete and its slot released; T2384 currently owns the slot while task18 subscription RED fixtures are prepared. This is resource coordination, not another implementation approval gate.
- [x] Provide a test-only JSON Schema2020-12 validator before executing task8/9 validation. The previously approved isolated environment `.codex-cache/schema-tests/venv` is available; read-only package inspection on2026-10-03 confirms jsonschema4.25.1, referencing0.36.2 and rpds-py0.27.1. No global package/config change. This satisfies tooling availability only; actual generated-schema validation and repeatable test-only bootstrap remain task8/9 work, not claimed PASS here. Host default Python's earlier missing-jsonschema observation is historical.

## Before installed-client readiness checks (tasks20–22)

- [ ] Parent identifies the actual intended Codex surfaces and authorises connecting each to the isolated synthetic endpoint; also verify Claude Code and Claude Desktop. A version string, embedded modern symbols or a legacy Transit connection does not fulfil AC6.3.
- [ ] If an actual surface requires a modern-runtime feature flag, connector/config edit or upgrade, present the exact evidence/change through parent and obtain explicit authorisation before making it. Current scope authorises no such settings change and no external-model agent probe. Do not add a legacy endpoint to bypass the blocker.
- [ ] Collect actual discovery/list/call plus structured-consumption traces for every intended surface; validate with task21's verifier before marking task22/AC6.3 complete. Subscription traces apply to opted-in installed surfaces; conforming fixture proof is always required. Missing evidence keeps readiness blocked without withholding the task15 common API delivery.

## Before activation

- [ ] Obtain separate owner authorisation for production endpoint cutover after modern readiness passes. No coding task in this plan activates Transit, changes client/server settings, pushes, merges or deploys.

## Current preparation checkpoint after task17

Task17/gpzncw1 is complete at handoff e45bc003. Tasks18–22 remain approved for implementation and preparation. Task18 is in progress; no build/test or isolated listener is running here while T2384 owns the heavy slot. The ten-file modern production handoff includes server/router/notification broadcaster/handler paths. MCPSettings forwarding remains an owner-coordinated T63 edit: preserve its existing availability observer and read lifecycle, and do not create a second broadcaster or observer.

The actual client prerequisite remains separate from subscription implementation. Read-only filesystem inspection confirms standalone Codex and Claude Code executable paths and installed Claude Desktop/ChatGPT app bundles; this establishes installation only. Earlier version/feature/symbol observations in scope.md remain historical observations, not current negotiation evidence. No client was launched, connected, upgraded or reconfigured at this checkpoint.

Parent action before an installed-client probe: identify each intended Codex surface and authorise its connection to the delivered, separate-port synthetic fixture; Claude Code and Claude Desktop are also required. The future verifier must see actual request metadata/headers, discovery, tools/list, tools/call and consumed structured results from each named surface. Opted-in installed surfaces additionally need subscription evidence, while the conforming fixture always does. No exact feature-flag/configuration change is currently proposed: determine such a change from actual runtime evidence, then present it separately before applying it. These prerequisites do not block tasks18–21 or delivered API15. They keep AC6.3 and activation open.
