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
├── Intents/                   # App Intents for CLI and Shortcuts integration
│   ├── Visual/                # Shortcuts-friendly visual intents (AddTask, FindTasks)
│   └── Shared/                # Entities, Enums, Results, Utilities
└── Extensions/                # Color+Codable, Date+TransitHelpers
```

## Services (Domain Layer)

- **StatusEngine** (`Services/StatusEngine.swift`) — Pure logic for task status transitions. All status changes go through `initializeNewTask` or `applyTransition`. Manages `completionDate` and `lastStatusChangeDate` side effects.
- **DisplayIDAllocator** (`Services/DisplayIDAllocator.swift`) — CloudKit-backed counter for sequential display IDs (T-1, T-2...). Uses optimistic locking with `CKModifyRecordsOperation`. Falls back to provisional IDs when offline. Marked `@unchecked Sendable` since it does async CloudKit work off MainActor.
- **TaskService** (`Services/TaskService.swift`) — Coordinates task creation, status changes, and lookups. Uses StatusEngine for transitions and DisplayIDAllocator for IDs. `@MainActor @Observable`.
- **ProjectService** (`Services/ProjectService.swift`) — Project creation, lookup (by ID or case-insensitive name), and active task counting. Returns `Result<Project, ProjectLookupError>` for find operations. `@MainActor @Observable`.
- **ConnectivityMonitor** (`Services/ConnectivityMonitor.swift`) — NWPathMonitor wrapper that tracks connectivity state and fires `onRestore` callback when connectivity transitions from unsatisfied to satisfied. `@Observable @unchecked Sendable` since NWPathMonitor callbacks come from a background queue.
- **SyncManager** (`Services/SyncManager.swift`) — Manages CloudKit sync enabled/disabled preference via UserDefaults (key: `syncEnabled`, shared with SettingsView's `@AppStorage`). Provides `makeModelConfiguration(schema:)` factory that creates the appropriate `ModelConfiguration` based on the sync preference. Sync toggle takes effect on next app launch since `ModelContainer` must be recreated. `@Observable`.

## Navigation

- **NavigationDestination** (`Models/NavigationDestination.swift`) — `Hashable` enum with `.settings` and `.projectEdit(Project)` cases. Used by DashboardView's settings gear and SettingsView's project rows.
- Root `NavigationStack` is in `TransitApp.swift` with `navigationDestination(for: NavigationDestination.self)`.
- Settings is pushed (not sheet), per req 12.1.

## App Entry Point (TransitApp.swift)

- Creates `SyncManager` first, then uses it to build `ModelConfiguration` (CloudKit-enabled or not based on preference).
- Stores `DisplayIDAllocator` as a property for promotion triggers.
- `ConnectivityMonitor` is started in `init()` with `onRestore` wired to `displayIDAllocator.promoteProvisionalTasks`.
- `ScenePhaseModifier` (private ViewModifier) observes `@Environment(\.scenePhase)` from within a View context (required by SwiftUI — cannot observe scenePhase in the App struct's Scene). Triggers promotion on `.task` (app launch) and `.onChange(of: scenePhase)` when returning to `.active`.
- `SyncManager` and `ConnectivityMonitor` are injected into the environment.

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
