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

## Build & Test
- `make build-macos` / `make build-ios` for building
- `make test-quick` for fast macOS unit tests during development
- `make lint` for SwiftLint (strict mode)
- `.swiftlint.yml` excludes DerivedData (auto-generated files)
