# Task 5: presentation GREEN draft

Status: READY for internal review and a separately granted focused app test. Rune task 5/gpzncvp remains in progress. This draft follows meaningful RED task4 at 99f8cbc (20 declarations/48 expanded failures); its fixtures remain unchanged. Common API delivery task15 is not complete.

Owned runtime files are MCPResultAdapter.swift and the new MCPResultInspection.swift, MCPResultClassification.swift and MCPResultLinks.swift under MCP/Results. They inspect the immutable source only, without live models, receipt writes, key acceptance, current-revision synthesis or navigation URLs.

The throwing presentation facade propagates the original worker checkpoint unchanged at entry/completion, member/pointer traversal, link selection and sorting. Callback lifetime is synchronous; no callback is stored in presentation or source and no deadline is renewed.

Documented task/project object positions use public taskId/projectId. Successful selector tasks use /results/index/task; unsuccessful requested identifiers do not establish links. Retained root task arrays and root project arrays are supported. Relationship tokens have their own pointer. Provider positions validate typed public objects or direct UUID tokens against the same document. Pointer lookup/dedup uses decoded Unicode scalar identity/UTF8 bytes, preserving composed and decomposed distinct keys; arrays sort by numeric source position, objects by exact token bytes, then entity type/UUID.

Classification prefers explicit provider phase, then known retained code. Unestablished, contradictory and unsupported outcome evidence takes precedence; uncertain write outcomes and possible postcommit serialization failures require original-key or maintenance reconciliation. Recognised source retry directions are supplemental follow_source only for established rejection/in_progress evidence and classified known failures. Unknown historical/internal failures do not infer safe retry. Complete receipt validity remains the existing provider/receipt owner's responsibility; this adapter adds no acceptance engine or receipt-version validator. Original JSON/text, missing/null, isError, accepted, outcome and retryAction remain untouched.

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
