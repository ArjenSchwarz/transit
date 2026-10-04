# Client-readiness approval bundle for parent

Prepared scope only; no client probe, feature override, configuration change, model turn or activation has run. Ask once after implementation/fixture delivery and the unresolved target details below are concrete. This is separate from the authorised subscription RED run.

## Verified read-only targets

| Installed target | Exact identity | What is established |
| --- | --- | --- |
| Standalone Codex CLI | `/Users/arjen/.local/bin/codex` → executable under `/Users/arjen/.codex/packages/standalone/releases/` | Installed CLI help supports invocation overrides. `mcp_2026_07_28` is disabled. |
| Codex desktop host | `/Applications/ChatGPT.app`, bundle ID `com.openai.codex` | Installed native desktop app. Its bundled CLI at `Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex` also reports the modern flag disabled; that does not establish the host's effective settings. |
| Claude Code | `/Users/arjen/.local/bin/claude` | Installed help supports disposable `--mcp-config` and `--strict-mcp-config`. |
| Claude Desktop | `/Applications/Claude.app`, bundle ID `com.anthropic.claudefordesktop` | Installed vendor code has a native HTTP MCP host/caller; user-registration path, active negotiation and consumption remain unproved. |

The bundled Codex CLI is a diagnostic executable, not a substitute proof for the desktop host. Parent must name intended Codex surfaces; standalone CLI and native desktop host are distinct candidates. Claude Code and Claude Desktop are required by approved scope.

## Actions requiring approval, once exact values are ready

Use one task21-delivered synthetic read-only fixture, bound to its descriptor's exact ephemeral `http://127.0.0.1:<PORT>/mcp` URL excluding3141, and a new empty working directory. Replace all placeholders with the actual descriptor before asking. No real store or existing Transit listener is connected.

1. **Standalone Codex, if selected:** run an invocation-only `--enable mcp_2026_07_28` plus `-c 'mcp_servers={transit_structured_readiness={url="<URL>",enabled_tools=["get_projects","query_tasks"]}}'`. First inspect the same invocation's `mcp list --json`; establish that its effective enabled providers, including plugin providers, are only the fixture. Stop if this is not established. Then start one synthetic client session in the empty directory. No persistent `config.toml` or feature edits.
2. **Claude Code:** supply one disposable JSON file containing `{"mcpServers":{"transit_structured_readiness":{"type":"http","url":"<URL>"}}}` and start one session with `--bare --mcp-config <FILE> --strict-mcp-config` in the empty directory. Installed help confirms bare mode skips automatically discovered hooks/plugins/memory while accepting explicit MCP configuration; this is invocation-scoped context minimisation, not a permissions override. No `claude mcp add` or normal user/project configuration edit.
3. **Desktop hosts:** do not include a generic host/settings permission. First establish each selected host's exact native temporary entry/feature delta, actual storage path or UI action, reload needs and removal step; then add only that concrete action to this same approval bundle. CLI flags are not assumed to affect the Codex desktop host. Claude Desktop's native loopback registration is still unresolved.
4. **Calls/consumption:** connect, collect actual modern discovery/list traces, and make one synthetic `query_tasks` call with `readPolicy:"cached", detailLevel:"full", includeComments:false, limit:100`; verify native parsed structured consumption. If a model turn is necessary, explicitly include one bounded synthetic-only turn and its exact provider/context exposure in approval. Otherwise no model turn is authorised. Subscription probes apply only to clients that opt in; the conforming fixture always supplies subscription proof.

## Configuration and data exposure

CLI configuration can avoid persistent server/feature changes through invocation overrides and a disposable Claude configuration file. This does not imply clients create no ordinary session/auth/cache/history files; preserve existing configuration and remove only newly created fixture artifacts/entries. Native Desktop/host persistence and temporary registration remain to establish, so no claim that their setup is configuration-free is made.

Local endpoint exposure is the exact probe prompt/arguments, synthetic project/task UUIDs and records/revisions/read metadata, request IDs and native client capabilities/version/identity. Evidence stays in the task workspace. No user record, production store, repository source/spec, arbitrary filesystem content or real mutation belongs to the probe. Normal installed-client authentication/feature fetching may contact its service; do not export credentials or request full unrelated logs.

A model turn would additionally send the synthetic prompt/tool results and that client's native context to its configured model provider. The provider and context isolation must be established before that turn is included in approval; an empty working directory alone does not prove that global instructions/memory/plugins cannot enter model context. Connection/discovery approval does not silently authorise external inference. No external peer review is requested.

## Open details before the single ask

- Delivered fixture descriptor/verifier and exact URL, file paths, prompt/expected result, shutdown action and evidence destination.
- Intended Codex surfaces, effective CLI provider isolation, and native desktop-host configuration deltas.
- Claude Desktop supported native loopback entry. If unavailable, report AC6.3 prerequisite unmet rather than introduce a proxy or legacy endpoint.
- Actual provider/context bounds for any necessary single synthetic model turn.

These are client-readiness prerequisites, not blockers for coding tasks18–21 or the delivered API15. No new client permission is being requested at this preparation checkpoint.
