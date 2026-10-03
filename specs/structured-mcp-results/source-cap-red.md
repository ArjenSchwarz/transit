# Task 2 amendment: parser container cap RED

Owner approval `Sentinel_9536d4df532c81919792e70801f128fb` establishes a maximum parser input depth of 32 object/array containers. Root containers count as one; scalars count as zero. Width is independent of depth. Excess depth is a resource limit, not malformed JSON.

The declaration adds `MCPResultBoundaryError.resourceLimit`. New RED fixtures require mixed object/array depth 31 and 32 to be accepted, depth 33 to throw the distinct error, and a 2,000-record array to be admitted. Generated depth-33 source throws; retained depth-33 source keeps exact raw text and optional nil/false/true isError as unreadable/unestablished evidence. Original worker checkpoint failure still propagates instead of being swallowed as retained evidence.

Status: demonstrated RED against declaration-only commit `128823d`, in the parent's next exclusive heavy slot. Build and test launch succeeded; make exited 2 (xcodebuild Error 65). Result summary: 23 declarations, 22 failed and 1 passed; expanded dynamic runs: 49 failed and 1 passed. The independent shrinker passed.

The new depth-31/32 and wide-2,000-record tests caught `.notImplemented`. Parser/source depth-33 tests expected `.resourceLimit` but received `.notImplemented`. Retained depth-33 preservation caught `.notImplemented`; original checkpoint cases expected `.cancelled` but received `.notImplemented`. These are behavioral RED failures, not compiler or fixture failures. Baseline task 2 RED remains independently recorded in `source-red.md`.

The pipeline and test host drained, and the heavy slot was released before lightweight task 3 drafting. No GREEN app test run was included in this grant. Local artifacts are `.codex-cache/source-cap-red.log`, `.codex-cache/source-cap-red-summary.json`, and `DerivedData/Logs/Test/Test-Transit-2026.10.03_21-50-13-+1000.xcresult`.

Executed command:

```sh
make test-quick TEST_TARGETS='TransitTests/MCPJSONDocumentTests TransitTests/MCPResultSourceTests'
```
