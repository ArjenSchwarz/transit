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
