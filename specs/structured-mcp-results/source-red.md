# Task 2: source/parser RED evidence

Parent granted the exclusive focused test slot on 2026-10-03. Run from the isolated `stream/structured-results-1` worktree at test commit `498d515`:

```sh
make test-quick TEST_TARGETS='TransitTests/MCPJSONDocumentTests TransitTests/MCPResultSourceTests'
```

The build and test launch succeeded. Make exited 2; its xcodebuild pipeline reported Error 65 and `TEST FAILED`. The result summary reports 16 test declarations: 15 failed and 1 passed. Including dynamic arguments, the device/configuration reports 41 failed runs and 1 passed run; two tests used 28 parameterized runs.

Expected behavioral failures are demonstrated by the result bundle:

- Valid JSON/source cases caught `.notImplemented`, including distinct composed/decomposed keys, exact number/UTF-8 evidence, plain text, malformed retained JSON and unsupported retained payload preservation.
- Invalid JSON/UTF-8 cases expected `.invalidJSON` but received `.notImplemented`.
- Original worker cancellation cases expected `MCPJSONCheckpointFailure.cancelled` but received `.notImplemented`. The repeated checkpoint assertion also showed the placeholder never invoked the worker check.
- The seeded valid-value property recorded seed 0 and minimized the failing case to `[]`.
- The independent shrinker test passed.

There were no compiler failures or test-launch failures. No GREEN implementation was present or started. The test pipeline and its host drained before the slot was released to the next sequential run. Existing unrelated installed Transit app processes were left untouched.

Local ignored evidence:

- `.codex-cache/source-red.log`: complete command output.
- `.codex-cache/source-red-summary.json`: extracted xcresult summary.
- `DerivedData/Logs/Test/Test-Transit-2026.10.03_21-29-37-+1000.xcresult`: result bundle.

Task 2 is complete as a RED task. The same tests remain unchanged for task 3 GREEN. Depth-limit assertions are held pending the separate bounded-tree design refinement; that does not invalidate this demonstrated baseline RED.
