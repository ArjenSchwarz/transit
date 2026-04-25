---
references:
    - specs/duplicate-displayid-cleanup/requirements.md
    - specs/duplicate-displayid-cleanup/design.md
    - specs/duplicate-displayid-cleanup/decision_log.md
---
# Duplicate Display ID Cleanup

## Core

- [x] 1. Write tests for CounterStore.advanceCounter(toAtLeast:retryLimit:) extension <!-- id:4zgmwak -->
  - New test file: Transit/TransitTests/CounterStoreAdvanceTests.swift
  - Use the in-memory CounterStore stub already used by DisplayIDAllocatorTests; extend it with injectable conflict/failure behaviour
  - Cases: no-op when nextDisplayID already >= target; advances on behind counter; retries and succeeds on transient conflict; throws retriesExhausted after retryLimit conflicts; reads the post-conflict snapshot and short-circuits when another writer already moved the counter past target
  - Stream: 1
  - Requirements: [2.4](requirements.md#2.4)
  - References: specs/duplicate-displayid-cleanup/design.md#components-and-interfaces

- [x] 2. Implement CounterStore.advanceCounter(toAtLeast:retryLimit:) default extension <!-- id:4zgmwal -->
  - Extend protocol CounterStore in Transit/Transit/Services/DisplayIDAllocator.swift with default impl per design's 'Counter store extension' section
  - Internal loop: loadCounter; if nextDisplayID >= target return; else saveCounter with expectedChangeTag; on Error.conflict continue; after retryLimit throw Error.retriesExhausted
  - CloudKitCounterStore does not override — default impl reuses existing saveCounter CAS
  - Blocked-by: 4zgmwak (Write tests for CounterStore.advanceCounter(toAtLeast:retryLimit:) extension)
  - Stream: 1
  - Requirements: [2.4](requirements.md#2.4)
  - References: specs/duplicate-displayid-cleanup/design.md#components-and-interfaces

- [x] 3. Write tests for DisplayIDMaintenanceTypes JSON encoding <!-- id:4zgmwam -->
  - New test file: Transit/TransitTests/DisplayIDMaintenanceTypesTests.swift
  - Cases: DuplicateReport round-trip (tasks + milestones + empty); recordRef shape incl. projectName '(no project)' when nil; winner-first ordering within groups; groups ordered by ascending displayId; ReassignmentResult 'ok' variant with full counterAdvance keys (task, milestone); 'busy' variant with groups: [] and counterAdvance: null; FailureCode raw strings match the design table exactly (allocation-failed, save-failed, stale-id, comment-failed, counter-advance-failed)
  - Stream: 1
  - Requirements: [1.6](requirements.md#1.6), [1.8](requirements.md#1.8), [2.7](requirements.md#2.7), [6.3](requirements.md#6.3), [8.2](requirements.md#8.2)
  - References: specs/duplicate-displayid-cleanup/design.md#json-shapes-shared-across-mcp-and-intent, specs/duplicate-displayid-cleanup/design.md#error-handling

- [x] 4. Implement DisplayIDMaintenanceTypes (structs + FailureCode + Codable encoders) <!-- id:4zgmwan -->
  - New file: Transit/Transit/Services/DisplayIDMaintenanceTypes.swift
  - Types: DuplicateReport, DuplicateGroup, RecordRef (with role), ReassignmentResult, GroupResult, ReassignmentEntry, CounterAdvanceResult, FailureCode enum (String-raw-valued)
  - JSON shape must match design exactly; counterAdvance key always present (nullable); recordRef.role always emitted alongside winner-first ordering
  - Use ISO-8601 date-only formatting for recordRef.creationDate (use ISO8601DateFormatter with .withFullDate or equivalent)
  - Blocked-by: 4zgmwam (Write tests for DisplayIDMaintenanceTypes JSON encoding)
  - Stream: 1
  - Requirements: [1.6](requirements.md#1.6), [1.8](requirements.md#1.8), [2.7](requirements.md#2.7), [6.3](requirements.md#6.3), [8.2](requirements.md#8.2)
  - References: specs/duplicate-displayid-cleanup/design.md#json-shapes-shared-across-mcp-and-intent

- [x] 5. Write tests for DisplayIDMaintenanceService.scanDuplicates <!-- id:4zgmwao -->
  - New test file: Transit/TransitTests/DisplayIDMaintenanceServiceScanTests.swift
  - @Suite(.serialized) using TestModelContainer.newContext()
  - Cases: two tasks sharing id reported once; two milestones sharing id reported once; provisional (nil) records excluded; task T-5 + milestone M-5 NOT reported as duplicate; oldest creationDate wins; UUID-ascending tiebreaker when creationDate equal; project==nil yields projectName '(no project)'; empty input yields empty groups; groups ordered by ascending displayId; winner-first ordering within each group
  - Blocked-by: 4zgmwan (Implement DisplayIDMaintenanceTypes (structs + FailureCode + Codable encoders)), structs, structs, structs, structs, structs, structs, structs, structs
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.3](requirements.md#1.3), [1.4](requirements.md#1.4), [1.5](requirements.md#1.5), [1.6](requirements.md#1.6), [1.7](requirements.md#1.7), [1.8](requirements.md#1.8)
  - References: specs/duplicate-displayid-cleanup/design.md#displayidmaintenanceservice

- [x] 6. Implement DisplayIDMaintenanceService.scanDuplicates <!-- id:4zgmwap -->
  - New file: Transit/Transit/Services/DisplayIDMaintenanceService.swift
  - @MainActor @Observable; init signature per design
  - Two FetchDescriptor reads (tasks, milestones); client-side group-by on permanentDisplayId; exclude nil; winner = min by (creationDate, id.uuidString); report groups sorted by displayId asc with winner first
  - Blocked-by: 4zgmwao (Write tests for DisplayIDMaintenanceService.scanDuplicates)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.3](requirements.md#1.3), [1.4](requirements.md#1.4), [1.5](requirements.md#1.5), [1.6](requirements.md#1.6), [1.7](requirements.md#1.7), [1.8](requirements.md#1.8)
  - References: specs/duplicate-displayid-cleanup/design.md#displayidmaintenanceservice

- [x] 7. Write tests for DisplayIDMaintenanceService.reassignDuplicates (all paths + concurrency) <!-- id:4zgmwaq -->
  - New test file: Transit/TransitTests/DisplayIDMaintenanceServiceReassignTests.swift
  - Happy path: winner unchanged; losers get fresh IDs > max; counter advanced to max(sampledMax, currentCounter)+1 BEFORE allocation; audit comment appended to reassigned tasks with authorName 'Transit Maintenance' and body containing 'T-<old>', 'T-<new>', injected ISO-8601 date
  - Milestone reassignments create NO comment
  - Counter-advance at start: counter fence is raised before allocator.allocateNextID() is first called (verify order via stub allocator)
  - Stale-id: set loser.permanentDisplayId to a different value via a separate ModelContext; run uses modelContext.refresh(loser, mergeChanges: true) and records 'stale-id' without writing
  - Failures: allocation-failed (allocator throws); save-failed (save callback throws) restores pre-run ID via safeRollback; comment-failed populates commentWarning but keeps ID reassigned; counter-advance-failed recorded as per-type run-level warning and aborts that type's reassignment only
  - Zero-duplicate run: groups empty; counter-advance still attempted
  - All-fail run: counter still advanced
  - Single-flight: second concurrent call returns status 'busy' with empty groups and counterAdvance nil
  - Concurrency invariant (AC 7.2): interleave reassign with promoteProvisionalTasks on disjoint records using Task.yield; post-condition — no duplicate IDs and no lost IDs
  - Blocked-by: 4zgmwap (Implement DisplayIDMaintenanceService.scanDuplicates)
  - Stream: 1
  - Requirements: [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [2.3](requirements.md#2.3), [2.4](requirements.md#2.4), [2.5](requirements.md#2.5), [2.6](requirements.md#2.6), [2.7](requirements.md#2.7), [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3), [3.4](requirements.md#3.4), [7.1](requirements.md#7.1), [7.2](requirements.md#7.2), [7.3](requirements.md#7.3), [8.1](requirements.md#8.1), [8.2](requirements.md#8.2), [8.3](requirements.md#8.3), [8.4](requirements.md#8.4)
  - References: specs/duplicate-displayid-cleanup/design.md#displayidmaintenanceservicereassignduplicates-flow, specs/duplicate-displayid-cleanup/design.md#error-handling

- [x] 8. Implement DisplayIDMaintenanceService.reassignDuplicates <!-- id:4zgmwar -->
  - Flow per design section 'DisplayIDMaintenanceService.reassignDuplicates flow': single-flight Bool guard with defer reset; internal scanDuplicates call; counter-advance BEFORE loser allocation (per-type, independent); per-loser refresh→verify→allocate→save→comment; audit comment via CommentService.addComment with save: { try $0.save() } as a separate save
  - safeRollback on ID save failure; commentWarning on comment save failure; break inner loser loop on group-level failure (allocation-failed / save-failed / stale-id)
  - counter-advance-failed: record per-type warning, skip loser loop for that type, continue with the other type
  - Audit template: 'Display ID changed from T-<old> to T-<new> during duplicate cleanup on <YYYY-MM-DD>.' for tasks only
  - Blocked-by: 4zgmwaq (Write tests for DisplayIDMaintenanceService.reassignDuplicates (all paths + concurrency))
  - Stream: 1
  - Requirements: [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [2.3](requirements.md#2.3), [2.4](requirements.md#2.4), [2.5](requirements.md#2.5), [2.6](requirements.md#2.6), [2.7](requirements.md#2.7), [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3), [3.4](requirements.md#3.4), [7.1](requirements.md#7.1), [7.3](requirements.md#7.3), [8.1](requirements.md#8.1), [8.2](requirements.md#8.2), [8.3](requirements.md#8.3), [8.4](requirements.md#8.4)
  - References: specs/duplicate-displayid-cleanup/design.md#displayidmaintenanceservicereassignduplicates-flow

## MCP

- [ ] 9. Extend MCPSettings with maintenanceToolsEnabled <!-- id:4zgmwas -->
  - Modify Transit/Transit/MCP/MCPSettings.swift (file is already #if os(macOS))
  - Add var maintenanceToolsEnabled: Bool with didSet UserDefaults write, key 'mcpMaintenanceToolsEnabled'
  - Default off (UserDefaults.bool returns false for missing key)
  - Config/types change — no TDD pair required per skill rules
  - Stream: 2
  - Requirements: [5.5](requirements.md#5.5), [5.6](requirements.md#5.6)
  - References: specs/duplicate-displayid-cleanup/design.md#mcpsettings-addition

- [ ] 10. Split MCPToolDefinitions into coreTools + maintenanceTools and add tools(includingMaintenance:) helper <!-- id:4zgmwat -->
  - Modify Transit/Transit/MCP/MCPToolDefinitions.swift
  - Keep existing 10 tools as 'coreTools'; add 'maintenanceTools' with two definitions: scan_duplicate_display_ids (no required params), reassign_duplicate_display_ids (no required params)
  - Add 'static func tools(includingMaintenance: Bool) -> [MCPToolDefinition]'
  - Do not remove the existing 'all' alias in the same commit if other code paths depend on it; migrate callers in task 12
  - Config/types change — no TDD pair required
  - Stream: 2
  - Requirements: [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.5](requirements.md#5.5)
  - References: specs/duplicate-displayid-cleanup/design.md#mcptooldefinitions-split

- [ ] 11. Write tests for MCPToolHandler maintenance gating and dispatch <!-- id:4zgmwau -->
  - Extend existing MCP handler test suites (e.g. MCPToolHandlerTests.swift) or add MCPMaintenanceHandlerTests.swift under Transit/TransitTests
  - Gating off: tools/list excludes both maintenance tools; tools/call for either returns methodNotFound with message 'Tool ... is disabled. Enable maintenance tools in Transit Settings.'
  - Gating on: tools/list includes both; tools/call for scan returns DuplicateReport JSON wrapped in {content:[{type:'text', text}], isError:false}; tools/call for reassign returns ReassignmentResult JSON
  - Toggle flip: after setting mcpSettings.maintenanceToolsEnabled = true, next tools/list includes the maintenance tools without restart
  - Error path: dispatch handler propagates isError:true wrapping when the service returns status 'busy' (if chosen) or on JSON encoding failure
  - Blocked-by: 4zgmwar (Implement DisplayIDMaintenanceService.reassignDuplicates), 4zgmwas (Extend MCPSettings with maintenanceToolsEnabled), 4zgmwat (Split MCPToolDefinitions into coreTools + maintenanceTools and add tools(includingMaintenance:) helper)
  - Stream: 2
  - Requirements: [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [5.4](requirements.md#5.4), [5.5](requirements.md#5.5), [5.6](requirements.md#5.6)
  - References: specs/duplicate-displayid-cleanup/design.md#mcptoolhandler-changes

- [ ] 12. Update MCPToolHandler: new init signature, maintenance gating, scan/reassign dispatch; update MCPTestHelpers <!-- id:4zgmwav -->
  - Modify Transit/Transit/MCP/MCPToolHandler.swift: add maintenanceService + settings to init; handleToolsList uses MCPToolDefinitions.tools(includingMaintenance: settings.maintenanceToolsEnabled); handleToolCall dispatch adds scan_duplicate_display_ids and reassign_duplicate_display_ids cases, each preceded by a gate check that returns methodNotFound with the disabled-message text when the flag is off
  - Dispatch handlers invoke the service and wrap JSON via the existing MCPToolResult/content[text] convention
  - Update Transit/TransitTests/MCPTestHelpers.swift to accept and supply a default maintenanceService + MCPSettings for existing test call sites; update any other MCPToolHandler(...) constructions under TransitTests to match
  - Blocked-by: 4zgmwau (Write tests for MCPToolHandler maintenance gating and dispatch)
  - Stream: 2
  - Requirements: [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [5.4](requirements.md#5.4), [5.5](requirements.md#5.5), [5.6](requirements.md#5.6)
  - References: specs/duplicate-displayid-cleanup/design.md#mcptoolhandler-changes

## Intents

- [ ] 13. Write tests for ScanDuplicateDisplayIDsIntent and ReassignDuplicateDisplayIDsIntent <!-- id:4zgmwaw -->
  - New test file: Transit/TransitTests/DisplayIDMaintenanceIntentsTests.swift
  - Scan intent: invokes service, returns JSON string; shape matches the same scenario encoded via MCP path (same top-level keys and value types per AC 6.3)
  - Reassign intent: invokes service, returns JSON string; status 'ok' on success; error payloads (JSON) instead of thrown errors (matches existing Transit intent convention)
  - Explicitly assert JSON key/value-type parity vs MCP output for the same pre-seeded duplicate scenario
  - Blocked-by: 4zgmwar (Implement DisplayIDMaintenanceService.reassignDuplicates)
  - Stream: 3
  - Requirements: [6.1](requirements.md#6.1), [6.2](requirements.md#6.2), [6.3](requirements.md#6.3), [6.4](requirements.md#6.4)
  - References: specs/duplicate-displayid-cleanup/design.md#json-shapes-shared-across-mcp-and-intent

- [ ] 14. Implement ScanDuplicateDisplayIDsIntent and ReassignDuplicateDisplayIDsIntent <!-- id:4zgmwax -->
  - New files: Transit/Transit/Intents/ScanDuplicateDisplayIDsIntent.swift and Transit/Transit/Intents/ReassignDuplicateDisplayIDsIntent.swift
  - Use @Dependency var maintenanceService: DisplayIDMaintenanceService (registered in TransitApp in task 18)
  - Return ReturnsValue<String> with JSONEncoder-encoded payload from DisplayIDMaintenanceTypes; reuse the same encoder path as MCP
  - Follow IntentHelpers error-payload convention: catch internal errors and return a JSON error string instead of throwing
  - Blocked-by: 4zgmwaw (Write tests for ScanDuplicateDisplayIDsIntent and ReassignDuplicateDisplayIDsIntent)
  - Stream: 3
  - Requirements: [6.1](requirements.md#6.1), [6.2](requirements.md#6.2), [6.3](requirements.md#6.3), [6.4](requirements.md#6.4)
  - References: specs/duplicate-displayid-cleanup/design.md#components-and-interfaces

## UI

- [ ] 15. Write UI test for Data Maintenance golden path (scan, confirm alert, result) <!-- id:4zgmway -->
  - New UI test in Transit/TransitUITests covering: open Settings → Data Maintenance → tap Scan → (with seeded duplicates via TRANSIT_UI_TEST_SCENARIO) report shows ≥1 group → tap Reassign Losers → alert appears with destructive-styled confirm button → tap confirm → result view shows per-group outcome
  - Add a new UITestScenario case that seeds two tasks sharing a permanentDisplayId so the report is non-empty
  - Use accessibility identifiers (do not match by text) for Scan button, Reassign Losers button, alert primary button, and result list
  - Blocked-by: 4zgmwar (Implement DisplayIDMaintenanceService.reassignDuplicates)
  - Stream: 4
  - Requirements: [4.2](requirements.md#4.2), [4.3](requirements.md#4.3), [4.4](requirements.md#4.4), [4.5](requirements.md#4.5), [4.6](requirements.md#4.6), [4.7](requirements.md#4.7)
  - References: specs/duplicate-displayid-cleanup/design.md#datamaintenanceview-state-machine, specs/duplicate-displayid-cleanup/design.md#testing-strategy

- [ ] 16. Implement DataMaintenanceView with state machine and confirmation alert <!-- id:4zgmwaz -->
  - New file: Transit/Transit/Views/Settings/DataMaintenanceView.swift
  - Single @State enum with cases .idle, .scanning, .scanned(DuplicateReport), .reassigning, .done(ReassignmentResult)
  - Consume maintenance service via @Environment(DisplayIDMaintenanceService.self)
  - Report list shows winner/loser marker per RecordRef; Reassign Losers disabled/hidden when report has zero groups
  - Confirmation uses .alert with a Button(role: .destructive) primary action
  - Buttons disabled during .scanning and .reassigning
  - Accessibility identifiers for UI test hooks: 'dataMaintenance.scanButton', 'dataMaintenance.reassignButton', 'dataMaintenance.confirmButton', 'dataMaintenance.resultList'
  - Blocked-by: 4zgmway (Write UI test for Data Maintenance golden path (scan, confirm alert, result)), confirm, confirm, confirm, confirm, confirm, confirm, confirm, confirm
  - Stream: 4
  - Requirements: [4.2](requirements.md#4.2), [4.3](requirements.md#4.3), [4.4](requirements.md#4.4), [4.5](requirements.md#4.5), [4.6](requirements.md#4.6), [4.7](requirements.md#4.7)
  - References: specs/duplicate-displayid-cleanup/design.md#datamaintenanceview-state-machine

- [ ] 17. Wire NavigationDestination case, iOS/macOS SettingsView entries, and MCP toggle row <!-- id:4zgmwb0 -->
  - Add .dataMaintenance case to NavigationDestination enum (the declaration used by SettingsView — locate via grep for existing cases like .acknowledgments)
  - iOS SettingsView: new 'Data Maintenance' Section with NavigationLink(value: NavigationDestination.dataMaintenance) { Label } and navigationDestination { DataMaintenanceView() }
  - macOS SettingsView: add .dataMaintenance case to SettingsCategory enum (title 'Data Maintenance', icon e.g. 'wrench.and.screwdriver'); add settingsDetailWrapper { DataMaintenanceView() } case in settingsDetailContent
  - macOS MCP section: add Toggle('Expose maintenance tools', isOn: $mcpSettings.maintenanceToolsEnabled) row within the existing macOSMCPSection
  - Wiring/config — no TDD pair required
  - Blocked-by: 4zgmwas (Extend MCPSettings with maintenanceToolsEnabled), 4zgmwaz (Implement DataMaintenanceView with state machine and confirmation alert)
  - Stream: 4
  - Requirements: [4.1](requirements.md#4.1), [5.6](requirements.md#5.6)
  - References: specs/duplicate-displayid-cleanup/design.md#architecture

## Wiring

- [ ] 18. Wire DisplayIDMaintenanceService and updated MCPToolHandler in TransitApp <!-- id:4zgmwb1 -->
  - Modify Transit/Transit/TransitApp.swift: construct DisplayIDMaintenanceService passing both allocators and their counter stores (may require exposing the CounterStore used by each DisplayIDAllocator — add a public accessor on the allocator if needed), commentService, container.mainContext
  - Register maintenanceService via AppDependencyManager.shared.add(dependency:) for App Intents
  - Expose service as .environment(maintenanceService) on the root NavigationStack and within withCoreEnvironments (macOS Settings window and Task Detail window) so DataMaintenanceView can consume it
  - Pass MCPSettings and maintenanceService to MCPToolHandler init (macOS-only block)
  - No new tests required for wiring; existing test suites must continue to pass — update any broken call sites
  - Blocked-by: 4zgmwar (Implement DisplayIDMaintenanceService.reassignDuplicates), 4zgmwav (Update MCPToolHandler: new init signature, maintenance gating, scan/reassign dispatch; update MCPTestHelpers), 4zgmwax (Implement ScanDuplicateDisplayIDsIntent and ReassignDuplicateDisplayIDsIntent), 4zgmwb0 (Wire NavigationDestination case, iOS/macOS SettingsView entries, and MCP toggle row)
  - Stream: 1
  - Requirements: [4.1](requirements.md#4.1), [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [6.1](requirements.md#6.1), [6.2](requirements.md#6.2), [7.3](requirements.md#7.3)
  - References: specs/duplicate-displayid-cleanup/design.md#architecture
