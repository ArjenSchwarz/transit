# Minimal isolated client-readiness setup proposal

This is a staged setup proposal for parent review. It does not authorise or execute a client connection, feature override, settings edit, model turn, upgrade or production cutover. Subscription tasks18/19 and fixture/verifier tasks20/21 can proceed independently. Actual client evidence is required for task22/AC6.3. The current subscription RED checkpoint4366824/f40dfb3 and its guarded packet remain unchanged.

## Minimal scope and fixture prerequisites

Use one delivered task21 fixture process on `127.0.0.1`, an OS-assigned ephemeral port excluding3141, and a separate empty working directory. It serves only synthetic read-only records through the approved encoder/validator and has no reference to a real ModelContainer, production listener, durable write coordinator or original user data. Readiness discovery lists only synthetic `get_projects` and `query_tasks`; writes and unrelated tools are unavailable. A conforming fixture client always verifies subscription behavior; actual installed clients need it only when they opt in.

Before proposing execution, the delivered launcher must provide an exact descriptor with bound URL, fixture PID/lifetime, source commit, synthetic marker/expected values, selected read-only tools, evidence destination, and an awaited shutdown procedure. `<PORT>` and `<EMPTY_DIR>` below are descriptor substitutions, not a request to reserve a guessed port or run an unavailable script now. Update this proposal with those actual values before parent approval of the probes. Stop and report if the fixture isolation or modern-only proof is unavailable.

Required installed surfaces: Claude Code and Claude Desktop, plus the actual Codex surfaces named by parent. Installed candidates observed locally are the standalone Codex CLI and the ChatGPT app's bundled Codex CLI/host. Running its bundled executable does not prove the desktop-host surface. Parent must specify whether standalone CLI, desktop-host or both are intended. Run probes serially against the same synthetic fixture with distinct surface/run labels.

## Codex CLI: invocation-only delta

Read-only installed help confirms `--enable`, `-c` TOML overrides and streamable HTTP configuration. Its current `features list` reports `mcp_2026_07_28` under development and false. Thus propose only this feature override and a temporary fixture server map for the approved CLI invocation; no `codex mcp add`, config file rewrite or persistent feature enable. The separate `codex_apps_mcp_2026_07_28` feature is not proposed for this ordinary external server.

```text
/Users/arjen/.local/bin/codex --enable mcp_2026_07_28 \
  -c 'mcp_servers={transit_structured_readiness={url="http://127.0.0.1:<PORT>/mcp",enabled_tools=["get_projects","query_tasks"]}}' \
  -C '<EMPTY_DIR>'
```

The installed CLI help verifies invocation overrides; the official [MCP configuration documentation](https://learn.chatgpt.com/docs/extend/mcp?surface=cli) verifies the HTTP URL and tool-selection keys. Installed `codex mcp list --help` confirms `--json` reports configured servers. The first proposed post-approval inspection, before a session, is:

```text
/Users/arjen/.local/bin/codex --enable mcp_2026_07_28 \
  -c 'mcp_servers={transit_structured_readiness={url="http://127.0.0.1:<PORT>/mcp",enabled_tools=["get_projects","query_tasks"]}}' \
  mcp list --json
```

Check the resulting enabled server selection is exactly the synthetic entry and descriptor URL. This command itself has not run with overrides. Its help establishes a proposed inspection mechanism, not the actual map-replacement behavior. Verify plugin-supplied providers are included in this inventory or separately disabled/absent using native read-only configuration evidence; a partial server list cannot prove full isolation. If inherited entries remain, or plugin coverage cannot be established before launch, stop and present the exact additional invocation-scoped isolation change through parent. Do not enable broad permissions or apply unrelated flags. Feature presence or enabling it is not modern interoperability evidence.

For an intended ChatGPT desktop-host surface, this CLI command is only a starting reference. Do not change its host flag, connector registry or shared settings by analogy. Obtain that host's actual one-entry native registration/configuration delta and the supported modern override from its runtime before proposing the host action. A standalone or bundled CLI trace cannot substitute for a host trace.

## Claude Code: separate configuration input

Installed help confirms `--mcp-config` accepts a JSON string/file and `--strict-mcp-config` selects only those servers. Current installed help additionally confirms `--bare` skips automatically discovered hooks/plugins/memory and permits explicit MCP configuration; propose that invocation-only context minimisation for this synthetic session. Propose the following JSON as a disposable fixture input outside the repository and normal user configuration:

```json
{"mcpServers":{"transit_structured_readiness":{"type":"http","url":"http://127.0.0.1:<PORT>/mcp"}}}
```

```text
cd '<EMPTY_DIR>'
/Users/arjen/.local/bin/claude \
  --bare --mcp-config '<EXACT_DISPOSABLE_JSON_PATH>' --strict-mcp-config
```

The official [Claude Code MCP runtime documentation](https://code.claude.com/docs/en/mcp#mcp-client-runtimes) identifies the v2 runtime as the modern protocol path and documents strict fixture configuration. Do not change telemetry, cached feature flags or persistent server configuration to force it. Record the actual native negotiation. If the installed session uses an unsupported runtime, retain that evidence and propose its exact minimal correction separately; do not infer success from version or embedded symbols.

## Claude Desktop: exact native delta still to establish

The required target is installed `/Applications/Claude.app`. The proposed endpoint identity is `transit_structured_readiness`, with exactly the descriptor's native loopback HTTP URL and synthetic read-only tool set; it must be separate from any existing Transit entry. Read-only installed vendor-source inspection locates `.vite/build/mcp-runtime/directMcpHost.js` and its actual main-bundle caller: they pass a URL/HTTP transport to a native MCP client, and negotiation setup depends on runtime feature state. This is more specific than SDK-symbol presence but still does not establish the supported local user-registration path, active runtime, or parsed structured-result consumption. No hidden managed-settings field or runtime flag is proposed. The official [local Desktop setup guidance](https://support.claude.com/en/articles/10949351-getting-started-with-local-mcp-servers-on-claude-desktop) documents local extensions, and does not establish this specific loopback HTTP negotiation path.

Continue read-only source/configuration-path inspection to establish the native user-registration mechanism; actual app activation or a settings UI change remains held. Once established, present the precise temporary entry/diff, reload requirement and removal action before applying it. No guessed `claude_desktop_config.json` URL entry, extension install, stdio proxy or cloud tunnel is part of the minimal proposal. If Desktop lacks a native modern connection to the isolated loopback fixture, report that installed-client prerequisite as unavailable and keep AC6.3 open. Coding and API delivery proceed.

## Exact probe and acceptance

The first action proposed for approval is connection/discovery only. Capture actual native `server/discover`, `tools/list` and request metadata/headers at the synthetic fixture. Then, only with separate approval for one bounded synthetic-data client turn if it is necessary, request one `query_tasks` call using synthetic read-only arguments `readPolicy:"cached", detailLevel:"full", includeComments:false, limit:100`. No repository, spec, source, local file content or user record enters the client prompt or returned fixture data. A model turn is a client-consumption probe, not a peer review, and requires its own explicit approval here.

For each named surface retain actual request/response correlation, modern version/header/meta checks, complete discovery/list/call results and schema, plus client-side evidence that it consumed `structuredContent.contractVersion`, `structuredContent.source.kind` and the nested synthetic payload/presentation. A server log showing delivered structured JSON alone does not prove native consumption. A printed version, embedded symbol, successful registration, legacy negotiation or copied fixture-client response also cannot substitute. Where the native client cannot supply consumption evidence, report the limitation rather than certify it. If a surface opts into tools-list subscriptions, additionally capture its native acknowledged filter, first ack, original request-ID correlation and one synthetic availability invalidation; otherwise the conforming fixture supplies that coverage.

The future task21 verifier validates the collected actual evidence and rejects missing surfaces, legacy versions, missing consumption or fabricated subscription claims. No manual fixed Mcp-Method/protocol headers are added to client configuration to disguise a nonconforming runtime.

## Approval and cleanup boundary

Parent first names intended Codex surfaces. After task21 delivers the isolated launcher/verifier and this document has exact descriptor values, parent obtains approval for the exact invocation-only Codex feature/connection, Claude Code disposable configuration/connection, and the separately established Desktop/host entry if available. Any bounded model turn is explicitly included or remains held. No approvals are inferred from this proposal.

After probes, close the synthetic sessions, await fixture shutdown, remove only newly created disposable files/entries, and preserve the captured evidence locally. No persistent endpoint replacement, existing entry deletion, client upgrade or production activation is proposed.

## Observed capability evidence

Read-only commands performed during proposal preparation: standalone `codex features list`, Codex/Claude CLI help, MCP-add help, and `codex mcp list --help` only. The configured-server list with proposed overrides was not run. No add command was executed; no client session, endpoint or model agent was started. Codex help/list succeeded with an incidental PATH-alias permission warning; no retry or permission change was made to repair that warning. Saved relevant help/list output and hashes of the inspected Desktop vendor-source files are in `.codex-cache/client-readiness-setup-proposal/`; these artifacts prove available controls/code paths, not runtime negotiation.

## Verified installed target clarification

Read-only app identity inspection verifies `/Applications/ChatGPT.app` is bundle `com.openai.codex`: the installed Codex desktop host despite its directory/display name. Its supporting executable is `/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex`; a read-only feature list also reports `mcp_2026_07_28` disabled. This is a distinct target from `/Users/arjen/.local/bin/codex`; probing that supporting CLI alone cannot establish host readiness. The concise action/configuration/data-exposure bundle is [client-readiness-approval-bundle.md](client-readiness-approval-bundle.md). Actual model-provider/context isolation remains to establish before proposing a model turn; synthetic endpoint data alone does not bound native global context.
