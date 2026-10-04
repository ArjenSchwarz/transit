# Protocol RED evidence

Task 12 (`gpzncvw`) fixtures are in `Transit/TransitTests/MCPModernProtocolTests.swift`, containing `MCPModernProtocolTests` and `MCPModernDiscoveryTests`. Task 13 remains blocked by tasks 12 and 3; no GREEN implementation was performed.

The authorised focused command was:

```sh
make test-quick TEST_TARGETS='TransitTests/MCPModernProtocolTests TransitTests/MCPModernDiscoveryTests'
```

Run from the isolated `stream/structured-results-2` worktree. The initial sandbox invocation exited make 2 / xcodebuild 74 during Swift Package resolution because GitHub DNS was unavailable; it compiled and ran no tests. Main authorised one identical invocation with per-command escalation for the normal package/test environment. No settings, package versions or global permissions were changed.

The escalated run compiled app and tests, executed the two focused suites, and exited make 2 / xcodebuild 65. The xcresult summary reports **22 failing test functions, 36 failing runs including parameter cases, zero passes/skips**. Every failure is `Caught error: .notImplemented`; there are no fixture assertion failures or compilation failures. This is the expected RED against the declaration-stage validator/discovery boundaries; the schema/document-based discovery case also waits for the approved source parser delivery.

Local retained evidence (ignored build/cache output):

- `.codex-cache/protocol-red/run.log`: initial environment failure.
- `.codex-cache/protocol-red/escalated-run.log`: actual focused RED output.
- `.codex-cache/protocol-red/summary.json`: xcresult summary.
- `DerivedData/Logs/Test/Test-Transit-2026.10.03_21-33-34-+1000.xcresult`: full test result bundle.

Before the app test run, standalone declaration-module/test typecheck under default MainActor, parse and targeted SwiftLint passed. Duplicate-key raw fixture generation explicitly disables slash escaping so it exercises the intended malformed JSON.

After test exit, read-only escalated process inspection confirmed no xcodebuild, xcbeautify or isolated stream2 test host remained (test host PID 19856). Existing unrelated Transit applications were untouched. Main was notified immediately that the exclusive heavy slot was released; no repeat or broadened run occurred after behavioral RED.

## Supplemental RED after parser delivery

Four new boundary fixtures were committed in `cf900ad`; original declaration-stage fixtures were unchanged. The validator was restored byte-for-byte to `817a80a` before this run (SHA256 `7792780a642a9e39a8a1c8cf36f123e915f43ba083901c225b195b65cfd97eaa`). The drafted source refinement remained unapplied in its retained backup and patch (backup SHA256 `fa27d84dad75e2ed96fe042c7ce8fdaea9472adb3a393bb3d54d563388a9b4cc`).

After the presentation RED runner drained, the separately authorised same focused two-suite command compiled and executed. It exited make 2 / xcodebuild 65 with **24 passing and 2 failing test functions; 38 passing and 2 failing runs, zero skips**. All 22 original test functions passed. Exact supplemental failures:

- `validJSONDepthLimitIsDistinctFromParseFailure`: a syntactically valid 33-container request received `-32700` rather than the required distinct `-32600` resource-limit error. Its exact-32 counterpart passed.
- `outOfRangeAndNonIntegralNumericIDsNeverBecomeDispatchable`: invalid numeric IDs were rejected without dispatch, but the diagnostic lacked the required string-ID advice. The message was `Request ID must be a string or integer`.

The new exact Int.min/max, integral decimal/exponent spellings, giant zero-exponent and independent width/body-bound cases passed. These supplemental fixtures had not run in the original declaration-stage RED; this section records their separate actual evidence rather than retroactively claiming it.

Evidence: `.codex-cache/protocol-supplement/red-run.log`, `.codex-cache/protocol-supplement/red-summary.json`, and `DerivedData/Logs/Test/Test-Transit-2026.10.03_23-15-16-+1000.xcresult`. Read-only process inspection confirmed xcodebuild, xcbeautify, xctest and the stream2 test host (PID 56978) drained. Main was notified immediately and the slot released before lightweight summary extraction/bookkeeping. CPU-heavy typecheck/lint/review jobs paused for the parent's next measurement window; no GREEN run or source fix application was performed under this grant. Task 13 remains in progress.

## Critic supplemental RED: filter and header conformance

Commit `366a1ad` added four focused critic fixtures against byte-unchanged validator `3cfd28a`. The two discovery test methods were moved verbatim into `MCPModernDiscoveryTests.swift` to keep file-length lint clean; all previous 26 test functions remained unchanged. The primary [subscription specification source](https://raw.githubusercontent.com/modelcontextprotocol/modelcontextprotocol/main/docs/specification/2026-07-28/basic/patterns/subscriptions.mdx) defines resourceSubscriptions as string[] and requires unsupported filters omitted from acknowledgment. The [HTTP value encoding rules](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http#value-encoding) require padded names encoded and recognize the sentinel only when both exact markers occur.

After T63's preservation baseline drained, the explicitly granted same focused two-suite command compiled and ran. It exited make 2 / xcodebuild 65 with **27 passing and 3 failing functions; 41 passing and 3 failing runs, zero skips**. All earlier 26 functions passed, including the previous depth and numeric diagnostic cases. The malformed resource-subscription array control passed. Actual new failures were:

- `validUnsupportedResourceSubscriptionsDoNotRejectMixedFilters`: the valid string[] filter was rejected with HTTP400/-32602 and `Notification filters must be Boolean`.
- `paddedPlainNamesRequireEncodingEvenWhenTheyMatchBody`: matching plain padded names were accepted rather than rejected. Encoded padded positives were exercised in the same function.
- `sentinelRequiresBothExactMarkersAndLiteralSentinelIsOuterEncoded`: the safe prefix-only plain name was rejected with HTTP400/-32020 and `Invalid encoded Mcp-Name`. This early throw prevented the later literal-full-sentinel case from executing; no pass evidence is claimed for it yet.

Evidence: `.codex-cache/protocol-supplement/critic-red-run.log`, `.codex-cache/protocol-supplement/critic-red-summary.json`, and `DerivedData/Logs/Test/Test-Transit-2026.10.03_23-58-13-+1000.xcresult`. Read-only process inspection confirmed xcodebuild, xcbeautify, xctest and the isolated test host PID79021 drained; main was notified immediately before summary extraction/bookkeeping. No production fix, GREEN run or additional app job was performed under this grant. Task13 remains in progress.

## Revised GREEN draft after critic RED

After the confirmed critic supplemental RED, the validator draft now validates the three known list-change filters as Boolean and resourceSubscriptions as string[], preserving valid unsupported filters for later acknowledgment omission. The official [SubscriptionFilter JSON Schema](https://raw.githubusercontent.com/modelcontextprotocol/modelcontextprotocol/main/schema/2026-07-28/schema.json) defines only these known properties and does not forbid additional properties; unknown filter values remain their original validated JSON rather than acquiring an invented Boolean restriction. The future stream still acknowledges only its supported requested toolsListChanged filter.

Plain padded Mcp-Name values now reject; names matching both exact sentinel markers decode once, while safe prefix-only names remain plain values. UTF-8 byte equality against the body remains authoritative. All 30 focused fixtures are byte-unchanged from 366a1ad. Pure module/test typecheck, parse and targeted lint pass, using the existing standalone read-only port-constant shim for MCPOriginValidator's settings dependency; these are light checks, not an app GREEN run. The previously unreachable literal-sentinel outer-encoding case remains pending actual execution. Task13 remains in progress and requires the separately granted focused protocol/discovery GREEN plus review.
