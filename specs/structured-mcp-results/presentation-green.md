# Task 5: presentation GREEN draft

Status: revised GREEN draft READY for internal fix review and a separately granted focused app test. Original readiness1652913 was withdrawn after critic findings; supplementalRED at fixtures391c159/runtime1652913 verified baseline48passes and4meaningful new failures (evidencee3b37e3). Rune task5/gpzncvp remains in progress. All25declarations/55expanded fixtures remain unchanged. Common API task15 is not delivered.

Owned runtime files are MCPResultAdapter.swift and the new MCPResultInspection.swift, MCPResultClassification.swift and MCPResultLinks.swift under MCP/Results. They inspect the immutable source only, without live models, receipt writes, key acceptance, current-revision synthesis or navigation URLs.

The throwing presentation facade propagates the original worker checkpoint unchanged at entry/completion, member/pointer traversal, link selection and sorting. Callback lifetime is synchronous; no callback is stored in presentation or source and no deadline is renewed.

Documented task/project object positions use public taskId/projectId. Successful selector tasks use /results/index/task; unsuccessful requested identifiers do not establish links. Retained root task arrays and root project arrays are supported. query_milestones root arrays link only saved projectId relationship tokens at /index/projectId; milestoneId is never task/project identity. Project/root-milestone position generation checks the original worker before the first position allocation and every64 entries, replacing unchecked project-array map generation. Relationship tokens have their own pointer. Provider positions validate typed public objects or direct UUID tokens against the same document. Pointer lookup/dedup uses decoded Unicode scalar identity/UTF8 bytes, preserving composed and decomposed distinct keys; arrays sort by numeric source position, objects by exact token bytes, then entity type/UUID.

Classification prefers explicit provider phase, then known retained code. Unestablished, contradictory and unsupported outcome evidence takes precedence; uncertain write outcomes and possible postcommit serialization failures require original-key or maintenance reconciliation. Recognised source retry directions are supplemental follow_source only for established rejection/in_progress evidence and classified known failures. Unknown historical failures and unestablished/uncertain evidence do not infer safe retry. Known established terminal INTERNAL_ERROR/INTERRUPTED_BEFORE_COMMIT rejections follow their original authoritative retry direction: accepted:true records key binding rather than committed entity effects. Supplemental internal_failure categorization cannot erase that source fact; unknown codes remain conservative even when an explicit provider category exists. Complete receipt validity remains the existing provider/receipt owner's responsibility; this adapter adds no acceptance engine or receipt-version validator. Original JSON/text, missing/null, isError, accepted, outcome and retryAction remain untouched.

Light validation passes: targeted swiftc frontend parse; strict no-cache SwiftLint on the four owned runtime files; standalone Swift6/default MainActor typecheck of pure Results/Protocol modules plus read-only MCPTypes.swift and unchanged presentation/property/document test fixtures (scratch copies remove only @testable import). Typecheck command:

```sh
xcrun swiftc -typecheck -swift-version 6 -default-isolation MainActor \
  -F /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Frameworks \
  -load-plugin-library /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib \
  -module-cache-path .codex-cache/presentation-green-typecheck/module-cache \
  Transit/Transit/MCP/MCPTypes.swift Transit/Transit/MCP/Results/*.swift Transit/Transit/MCP/Protocol/*.swift \
  .codex-cache/presentation-green-typecheck/*.swift
```

No app build/test was invoked. Requested next focused command, only after parent grants the heavy slot:

```sh
make test-quick TEST_TARGETS='TransitTests/MCPResultPresentationTests'
```

No shared MCPTypes/server/handler/definitions/Reads/store/coordinator files, configuration, CHANGELOG or test fixtures changed. Metadata ordered-member encoding and compact fallback giant-itemId regression remain later encoder tasks6–7. No heavy slot is held.

Revised source validation passed targeted parse/strict no-cache lint and the same standalone pure-module/unchanged-fixture Swift6/default MainActor typecheck. Runtime repairs are limited to MCPResultClassification.swift and MCPResultLinks.swift. No app test or runtime GREEN is claimed at this revised draft; the next focused command still requires a new parent slot grant.

## Final isolated runtime verification

Reviewed source f4bd03a was integrated with T63 b500543 and protocol b6b616e at fbbe7cb. After a fresh dedicated isolated smoke and shared Debug signed-host/xctestrun preflight, test-without-building passed all25 declarations/55 expanded runs, zero failures/skips, exit0. Fixtures remain unchanged from391c159. Evidence: DerivedData/t2383-shared-fbbe7cb/Presentation.xcresult and .codex-cache/t2383-final-isolated-fbbe7cb/presentation-{summary,tests}.json. Final read-only critic found no integration blocker. Task5 is complete; no additional app run follows slot release.
