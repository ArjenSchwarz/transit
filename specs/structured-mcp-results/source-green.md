# Task 3: source/parser GREEN draft

Status: task 3 complete after focused GREEN passed at `31bc425` and the final access-only constructor fix passed the separately authorised compile-boundary checks. The RED tests are unchanged.

Implementation:

- Complete UTF-8 validation and iterative object/array assembly into immutable ordered values. The validated input bytes remain the insertable source fragment; numbers retain original decimal/exponent lexemes without Foundation numeric conversion.
- The owner-approved cap counts object/array input containers, accepts 32, and throws `resourceLimit` on 33. This bounds resulting tree equality/destruction as well as parser assembly. Array width is independent.
- Object key identity compares decoded Unicode scalar sequences, allowing canonically equivalent but scalar-distinct names while rejecting escaped/literal duplicate names with identical sequences.
- String escapes and surrogate pairs are validated; invalid bytes/escapes, duplicate keys, malformed numbers and trailing input throw `invalidJSON`.
- Source adaptation uses declared generated/retained/plain origin. Retained syntax/resource failures preserve original text and optional isError as unreadable/unestablished; generated failures throw. Parseable unsupported evidence remains the original JSON with caller-supplied unestablished evidence.
- Original checkpoint callbacks propagate unchanged, including callback errors that happen to share parser error types. Checks run at parser entry, every 256 consumed bytes and completion; no deadline is created or renewed.

Interface adjustment: parser/source facade checkpoint arguments are now `@escaping @Sendable` so the synchronous scanner can own the callback while parsing. No callback is retained by the document, source or any frozen fragment. Presentation and encoder bodies remain placeholders for their later RED/GREEN tasks.

Validation completed: targeted SwiftLint with `--strict --no-cache`, Swift parsing, and standalone Swift 6/default MainActor typechecking of source files plus the unchanged Swift Testing fixtures using Xcode's Testing framework/plugin.

First focused GREEN attempt at `31bc425`: make exited 0, Test Succeeded; xcresult reports all 23 declarations passing, no failures (50 expanded runs passed). Artifacts: `.codex-cache/source-green.log`, `.codex-cache/source-green-summary.json`, `DerivedData/Logs/Test/Test-Transit-2026.10.03_22-00-59-+1000.xcresult`. The pipeline/test host drained and the slot was released.

Parallel review identified an actual construction blocker: the synthesized internal memberwise source initializer could bypass source-kind/text/document invariants. A private initializer now restricts construction to same-file factory paths. Its assignments are identical to the synthesized initializer; runtime behavior is unchanged.

Parent explicitly authorised final access-only verification without another heavy run: full pure Results/Protocol modules plus the unchanged Swift Testing fixtures passed standalone Swift 6/default MainActor typecheck (exit 0). An external-file constructor attempt failed compilation (exit 1) specifically with `MCPResultSource initializer is inaccessible due to private protection level`; `.codex-cache/source-constructor-negative.log` records this expected negative check. Targeted parse/lint also passed. No app test at the access-fix commit is claimed; actual final consumers remain covered by later integration compilation.

Executed focused command at `31bc425`:

```sh
make test-quick TEST_TARGETS='TransitTests/MCPJSONDocumentTests TransitTests/MCPResultSourceTests'
```

No shared MCP files, read publication/stores, coordinator, receipt formats, canonical request/revision algorithms, model normalizers or client settings changed. Common API task 15 remains undelivered.
