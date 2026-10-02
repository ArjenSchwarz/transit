---
references:
    - specs/mcp-project-creation/requirements.md
    - specs/mcp-project-creation/design.md
    - specs/mcp-project-creation/decision_log.md
---
# MCP Project Creation

- [x] 1. Write create_project contract and rejection tests <!-- id:95wcxxa -->
  - Cover required/schema fields, malformed strings/colors, duplicate/read failures, returned metadata and subsequent task creation; extend fallback rejection coverage.
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.3](requirements.md#1.3), [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [3.1](requirements.md#3.1), [3.2](requirements.md#3.2)

- [x] 2. Implement core schema, dispatch and project creation handler <!-- id:95wcxxb -->
  - Reuse ProjectService and project metadata formatter; preserve get_projects milestones.
  - Blocked-by: 95wcxxa (Write create_project contract and rejection tests)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.3](requirements.md#1.3), [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [3.1](requirements.md#3.1), [3.2](requirements.md#3.2)

- [x] 3. Reproduce Xcode 27 blockers with existing dependency and actor-store tests <!-- id:95wcxxc -->
  - Clean baseline macOS tests establish red compilation for AsyncAlgorithms and actor-backed CounterStore fixtures.
  - Stream: 1
  - Requirements: [4.1](requirements.md#4.1), [4.2](requirements.md#4.2)

- [x] 4. Update dependency pin and counter isolation for Xcode 27 <!-- id:95wcxxd -->
  - Keep unrelated dependencies and deployment targets unchanged; validate existing actor allocation tests, macOS/iOS builds and simulator UI suite.
  - Blocked-by: 95wcxxc (Reproduce Xcode 27 blockers with existing dependency and actor-store tests)
  - Stream: 1
  - Requirements: [4.1](requirements.md#4.1), [4.2](requirements.md#4.2)

- [x] 5. Run requested pre-push-review workflow <!-- id:95wcxxe -->
  - Blocked-by: 95wcxxd (Update dependency pin and counter isolation for Xcode 27)
  - Stream: 1
