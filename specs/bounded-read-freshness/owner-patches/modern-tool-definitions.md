Delegated modern definitions factory

T63 authorizes T2383 to apply modern-tool-definitions.patch exactly on its isolated modern branch. Retained MCPToolDefinitions ownership remains T63; this is the approved factory hunk only. T63 live source intentionally stays unchanged because modern modules are absent here.

Signature: static func modernTools(includingMaintenance: Bool) throws -> [MCPModernToolDescriptor]. It maps tools(includingMaintenance:) once, preserves name/description, parses the existing encoded input schema, and obtains the result descriptor from MCPResultSchemas. Existing arrays, tools/all, input contracts and descriptions remain unchanged. Foundation import is inside the macOS conditional.

Recipient baseline: 76fa6620743307219e31fe7ec3abe1191d466da3; local/recipient/baseline definitions byte equality confirmed. Hashes and source checks are recorded below. Syntax/lint/check application are source preparation only; no typecheck, app compile, runtime GREEN or Task13/15 completion.

Source checks: temporary proposed source strict SwiftLint --no-cache PASS (zero violations), Swift6 frontend syntax parse PASS, recipient read-only git apply --check PASS.

Required recipient tests: extend the existing MCPModernRouterIntegrationTests acceptance with actual definitions parity for maintenance off/on (names, descriptions and semantic input schema equality; independent JSONEncoder dictionary ordering is not a raw-byte parity contract), output schema from actual descriptor, and real modern single-object POST tools/list with outputSchema. No legacy arrays or live writes.

{
  "recipientBase": "76fa6620743307219e31fe7ec3abe1191d466da3",
  "baselineSHA256": "decfde58b4728ace41b4c83f5b32f24a46ef397a001927843d90e279ab53d45a",
  "finalDefinitionsSHA256": "879d1094658ad9840a86ce20839bbae048a4936540c169fa985a1d1df7c132dd",
  "patchSHA256": "36357d3c785fba21796e7443edc0baba08672568a6373495a8d1161a6d0228ea"
}
