# MCP Project Creation — T-2377

MCP clients need a way to create a project before adding its tasks. This feature exposes project creation through the existing local MCP endpoint and returns the identity clients need for subsequent operations.

### 1. MCP contract

**User Story:** As an MCP client, I want to create projects with explicit fields, so that I can establish projects without the app UI.

**Acceptance Criteria:**

1. <a name="1.1"></a>WHEN a client lists MCP tools, Transit SHALL expose `create_project` as a core tool.  
2. <a name="1.2"></a>WHEN creating a project, Transit SHALL require a string `name` and a string `colorHex` in `RRGGBB` or `#RRGGBB` format (ASCII hex, case insensitive).  
3. <a name="1.3"></a>WHEN optional `description` or `gitRepo` is supplied, Transit SHALL require strings, preserving their contents. Omitted description defaults to an empty string; omitted gitRepo is absent.  

### 2. Rejection and persistence

**User Story:** As an MCP client, I want rejected requests to leave no new project, so that failures do not create partial data.

**Acceptance Criteria:**

1. <a name="2.1"></a>WHEN the trimmed name is empty or conflicts case-insensitively with an existing project, Transit SHALL return an explicit tool error without creating a project.  
2. <a name="2.2"></a>WHEN validation or storage fails, Transit SHALL return an MCP tool error; fallback storage SHALL reject creation under the existing mutation policy.  

### 3. Project metadata and reuse

**User Story:** As an MCP client, I want the stored project metadata and UUID, so that I can create its tasks and discover it again.

**Acceptance Criteria:**

1. <a name="3.1"></a>WHEN creation succeeds, Transit SHALL return `projectId`, stored `name`, `description`, `colorHex`, `activeTaskCount` (zero), and `gitRepo` when supplied.  
2. <a name="3.2"></a>WHEN clients use the returned projectId with `create_task`, Transit SHALL create the task in that project; `get_projects` SHALL include the created project.  

### 4. Xcode 27 compatibility

**User Story:** As a developer, I want Transit to build and test with Xcode 27 / Swift 6.4, so that I can implement and validate projects on the current toolchain.

**Acceptance Criteria:**

1. <a name="4.1"></a>Transit SHALL build for macOS and iOS Simulator using Xcode 27 / Swift 6.4 with source-controlled dependency resolution and no cache patches.  
2. <a name="4.2"></a>Transit SHALL execute its macOS unit tests and iOS Simulator unit/UI tests on Xcode 27, including actor-backed display-ID stores and MCP project creation.  

## Non-goals

No App Intent, UI change, schema migration, project update/delete tools, URL validation, arbitrary project metadata dictionary, deployment, or merge. gitRepo follows the existing free-form project field.
