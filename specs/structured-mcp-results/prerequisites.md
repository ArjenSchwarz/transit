# Prerequisites for structured MCP results

These prerequisites track coordination and installed-client readiness separately from the approved implementation tasks. Testing is owner-approved; each application run still requires the parent's exclusive slot coordination. Live data/client activation remain held.

## Before shared integration or application tests

- [ ] Parent confirms T63's provider-regression fix and explicit common-file ownership handoff at a recorded commit before tasks14–19 edit shared handler/types/router/schema/lifecycle or owner test helpers. Isolated Results/Protocol modules can be prepared after task approval; no task waits on production T2384 completion.
- [ ] Parent coordinates the heavy build/test slot before each application build/test, including RED runs. Task7's corrected GREEN is complete and its slot released; T2382 currently owns the slot while task8 fixtures are prepared. This is resource coordination, not another implementation approval gate.
- [x] Provide a test-only JSON Schema2020-12 validator before executing task8/9 validation. The previously approved isolated environment `.codex-cache/schema-tests/venv` is available; read-only package inspection on2026-10-03 confirms jsonschema4.25.1, referencing0.36.2 and rpds-py0.27.1. No global package/config change. This satisfies tooling availability only; actual generated-schema validation and repeatable test-only bootstrap remain task8/9 work, not claimed PASS here. Host default Python's earlier missing-jsonschema observation is historical.

## Before installed-client readiness checks (tasks20–22)

- [ ] Parent identifies the actual intended Codex surfaces and authorises connecting each to the isolated synthetic endpoint; also verify Claude Code and Claude Desktop. A version string, embedded modern symbols or a legacy Transit connection does not fulfil AC6.3.
- [ ] If an actual surface requires a modern-runtime feature flag, connector/config edit or upgrade, present the exact evidence/change through parent and obtain explicit authorisation before making it. Current scope authorises no such settings change and no external-model agent probe. Do not add a legacy endpoint to bypass the blocker.
- [ ] Collect actual discovery/list/call plus structured-consumption traces for every intended surface; validate with task21's verifier before marking task22/AC6.3 complete. Subscription traces apply to opted-in installed surfaces; conforming fixture proof is always required. Missing evidence keeps readiness blocked without withholding the task15 common API delivery.

## Before activation

- [ ] Obtain separate owner authorisation for production endpoint cutover after modern readiness passes. No coding task in this plan activates Transit, changes client/server settings, pushes, merges or deploys.
