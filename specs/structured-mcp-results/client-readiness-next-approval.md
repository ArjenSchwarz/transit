# One bounded client approval request for parent

Local implementation and tests are complete. Actual client actions remain parked. No client settings/feature activation, app-server start, native client connection or model turn has been performed. Historical synthetic endpoint61985 is closed and must not be reused as a live target.

## Requested action

Approve one standalone installed Codex CLI probe against a newly launched, reviewed synthetic fixture, bounded to120seconds after its owned descriptor is ready. Use the committed scripts/mcp-modern-readiness/launch.py with a fresh guarded packet, signed isolated unit-host preflight, hold120 and the exact OS-assigned127.0.0.1 URL published in that descriptor, excluding3141. Verify descriptor synthetic=true, persistentStore=false and the two-read-tool allowlist before connecting. Never connect to an existing Transit endpoint.

Run `/Users/arjen/.local/bin/codex app-server --stdio` with invocation-only `--enable mcp_2026_07_28` and a fixture-only mcp_servers map restricted to get_projects/query_tasks. No persistent config.toml or feature edits. First inspect the effective enabled server/provider inventory, including plugin providers; stop if fixture-only isolation cannot be established.

Negotiate app-server experimentalApi, create an ephemeral thread in a newly created empty directory under the task workspace, inspect `mcpServerStatus/list` for that thread, and make one direct `mcpServer/tool/call` to query_tasks with `{readPolicy:"cached",detailLevel:"full",includeComments:false,limit:100}`. Capture the native parsed structuredContent and bounded negotiation evidence. Do not call turn/start or start an external model turn; stop rather than substitute a model-based fallback if the direct API is unsupported. Close only the owned app-server/fixture processes and newly created probe artifacts, preserving existing client state.

This is a prospective runtime check, not a claim that the schema-defined API will work. Exact runtime descriptor and fresh packet hash must be verified before executing. The local schema export establishes a possible direct no-model path, not negotiated readiness or native desktop behavior.

## Evidence supporting the proposal

Read-only installed CLI help/schema generation succeeded without starting app-server or enabling a feature. Generated ClientRequest defines `mcpServer/tool/call` with threadId/server/tool/arguments; McpServerToolCallResponse exposes structuredContent; ThreadStartParams supports ephemeral/cwd/baseInstructions/developerInstructions, and mcpServerStatus/list can use threadId. Metadata is retained in `.codex-cache/client-native-protocol-inspection/`. This is standalone CLI evidence only; it does not prove `/Applications/ChatGPT.app` bundlecom.openai.codex has the same effective settings.

## Exposure and limits

MCP payloads are synthetic UUIDs/records/revisions/read metadata plus request IDs, client identity/capabilities and the explicit read arguments. Capture no credentials, repository content, arbitrary files or unrelated logs. Ordinary installed-client authentication/feature fetching may contact its service and create normal auth/cache/history files; no model inference is authorised, and temporary invocation configuration does not promise zero ordinary client persistence.

Claude Code and both native desktop hosts remain parked until their supported modern runtime/setup and exact scoped actions are established. This single CLI approval would not close all of AC6.3, authorise another client or permit a production cutover. No external peer-review disclosure is requested.
