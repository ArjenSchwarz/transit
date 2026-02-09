# Project Structure

## Xcode Project
- **Project**: `Transit/Transit.xcodeproj`
- **Scheme**: `Transit`
- **File System Sync**: Enabled — Xcode auto-discovers files from disk, no need to update pbxproj
- **Bundle ID**: `me.nore.ig.Transit`
- **CloudKit container**: `iCloud.me.nore.ig.Transit`

## Targets
1. **Transit** — main app (iOS 26 / macOS 26)
2. **TransitTests** — unit tests using Swift Testing framework
3. **TransitUITests** — UI tests using XCTest

## Source Layout
```
Transit/Transit/
├── TransitApp.swift           # @main entry point
├── Models/                    # SwiftData models (Project, TransitTask)
├── Services/                  # Domain services (TaskService, ProjectService, etc.)
├── Views/
│   ├── Dashboard/             # DashboardView, KanbanBoardView, etc.
│   ├── TaskDetail/            # TaskDetailView, TaskEditView
│   ├── AddTask/               # AddTaskSheet
│   ├── Settings/              # SettingsView, ProjectEditView
│   └── Shared/                # Reusable components
├── Intents/                   # App Intents for CLI integration
└── Extensions/                # Color+Codable, Date+TransitHelpers
```

## Services (Domain Layer)

- **StatusEngine** (`Services/StatusEngine.swift`) — Pure logic for task status transitions. All status changes go through `initializeNewTask` or `applyTransition`. Manages `completionDate` and `lastStatusChangeDate` side effects.
- **DisplayIDAllocator** (`Services/DisplayIDAllocator.swift`) — CloudKit-backed counter for sequential display IDs (T-1, T-2...). Uses optimistic locking with `CKModifyRecordsOperation`. Falls back to provisional IDs when offline. Marked `@unchecked Sendable` since it does async CloudKit work off MainActor.
- **TaskService** (`Services/TaskService.swift`) — Coordinates task creation, status changes, and lookups. Uses StatusEngine for transitions and DisplayIDAllocator for IDs. `@MainActor @Observable`.
- **ProjectService** (`Services/ProjectService.swift`) — Project creation, lookup (by ID or case-insensitive name), and active task counting. Returns `Result<Project, ProjectLookupError>` for find operations. `@MainActor @Observable`.

## Error Types

- **ProjectLookupError** (in `ProjectService.swift`) — `.notFound`, `.ambiguous`, `.noIdentifier`. Will be translated to IntentError codes in stream 3.
- **IntentError** (in `Intents/IntentError.swift`) — JSON-formatted error responses for App Intents. Pre-existing.

## Build & Test
- `make build-macos` / `make build-ios` for building
- `make test-quick` for fast macOS unit tests during development
- `make lint` for SwiftLint (strict mode)
- `.swiftlint.yml` excludes DerivedData (auto-generated files)

## Test Infrastructure

- **TestModelContainer** (`TransitTests/TestModelContainer.swift`) — Shared in-memory ModelContainer for SwiftData tests. Uses `Schema` + `cloudKitDatabase: .none` to avoid conflicts with the app's CloudKit entitlements. Tests get fresh `ModelContext` instances via `newContext()`.
- Test suites using SwiftData should use `@Suite(.serialized)` trait.
