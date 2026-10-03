# Prerequisites for structured MCP results

These gates require coordination or exact owner authorisation outside the coding task list. They do not authorise implementation or activation now.

## Before shared integration or application tests

- [ ] Parent confirms T63's provider-regression fix and explicit common-file ownership handoff at a recorded commit before tasks14–19 edit shared handler/types/router/schema/lifecycle or owner test helpers. Isolated Results/Protocol modules can be prepared after task approval; no task waits on production T2384 completion.
- [ ] Parent coordinates release of T63's heavy build/test slot before any application build/test, including RED runs. All task statuses remain pending in the spec phase.
- [ ] Before executing task8/9 schema validation, provide a test-only JSON Schema2020-12 validator. Host `python3` currently raises ModuleNotFoundError for jsonschema; use an approved disposable test environment with jsonschema's Draft202012Validator, without global package/config changes. Report missing validation tooling rather than pass schema checks. No package installation occurred during planning.

## Before installed-client readiness checks (tasks20–22)

- [ ] Parent identifies the actual intended Codex surfaces and authorises connecting each to the isolated synthetic endpoint; also verify Claude Code and Claude Desktop. A version string, embedded modern symbols or a legacy Transit connection does not fulfil AC6.3.
- [ ] If an actual surface requires a modern-runtime feature flag, connector/config edit or upgrade, present the exact evidence/change through parent and obtain explicit authorisation before making it. Current scope authorises no such settings change and no external-model agent probe. Do not add a legacy endpoint to bypass the blocker.
- [ ] Collect actual discovery/list/call plus structured-consumption traces for every intended surface; validate with task21's verifier before marking task22/AC6.3 complete. Subscription traces apply to opted-in installed surfaces; conforming fixture proof is always required. Missing evidence keeps readiness blocked without withholding the task15 common API delivery.

## Before activation

- [ ] Obtain separate owner authorisation for production endpoint cutover after modern readiness passes. No coding task in this plan activates Transit, changes client/server settings, pushes, merges or deploys.
