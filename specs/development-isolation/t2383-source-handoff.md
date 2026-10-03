# T2383 exact source isolation handoff

Prepared against feeb7df8e115edcc0139072c08c0968c3ce157dc (T-2383/structured-mcp-results), descended from 201205bd4e786c7f152d8f99006b37da7da888c7. This component applies only development/test isolation from 9ba4297; it does not import T63 read-service/compiler changes or historical verification results.

App/project/Makefile/SyncManager/Settings inputs were unchanged relative to the 201205bd base. Code-only isolation hunks applied cleanly. TransitApp's existing environment, MCP-start and UI-test helper methods moved to a same-file extension to satisfy this branch's type-length lint limit. The new mode/allocator/storage/sidecar guards are identical to the verified isolation component. Existing handler and server calls remain exactly the branch's own signatures: MCPToolHandler(... persistence: persistence, writeCoordinator: writeCoordinator) and MCPServer(toolHandler: mcpToolHandler). No nonexistent T63 types or speculative constructor arguments were introduced. Results/Protocol modules, MCPToolHandler and MCPServer are unchanged.

Source verification: git apply --check passed on the exact parent checkpoint; make lint passed (418 files, zero violations), including development identity/entitlements/test-scheme/guarded-allocator preflight. No compiler, offline executable, build, app host or test suite ran in this integration checkout. No installed app, live endpoint, live data or production entitlement changes occurred. Previous isolation runtime results are not claimed as verification of T2383.

Consume this component by cherry-picking its sole commit onto feeb7df (or applying its exported patch with --check first). Preserve any later owner changes through narrow conflicts; do not restore complete App/project files from the T63-based branch. App/project conflicts remain owned by the isolation owner.

After parent grants a dedicated slot, the first verification is:

```sh
make test-development-isolation
make test-isolated-host-smoke SMOKE_DERIVED_DATA=DerivedData/t2383-isolation-smoke-fresh
```

The smoke scheme hosts TransitDevelopment with explicit unit-test mode. Its runner verifies the signed bundle and generated xctestrun before the single fixture; app preflight rejects unsafe identity/path/store selection before container creation. A passing branch-local smoke still does not release GREEN ticket suites without the parent's explicit grant.

T63 freshness integration remains a separate owned dependency: this branch does not yet contain MCPReadAppDependencies/MCPReadCoordinator or their handler/server interfaces. When the parent selects and integrates that component, the App owner must add its narrow shared-domain/read-service/coordinator wiring while preserving these isolation guards and T2383 Results/Protocol interfaces. The isolation-only component is safe to verify independently; it does not claim freshness readiness.
