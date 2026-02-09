# Transit Project Structure

This document describes the organization of the Transit Xcode project.

## Directory Layout

```
Transit/Transit/
├── TransitApp.swift              # @main entry point, ModelContainer setup
├── Models/                       # SwiftData models and enums
├── Services/                     # Domain services (business logic)
├── Views/                        # SwiftUI views
│   ├── Dashboard/               # Kanban board and column views
│   ├── TaskDetail/              # Task detail and edit views
│   ├── AddTask/                 # Task creation sheet
│   ├── Settings/                # Settings and project management
│   └── Shared/                  # Reusable UI components
├── Intents/                     # App Intents for CLI integration
├── Extensions/                  # Swift extensions and helpers
└── Assets.xcassets/             # Images and colors

Transit/TransitTests/            # Unit tests
Transit/TransitUITests/          # UI tests
```

## Layer Architecture

- **UI Layer**: SwiftUI views using `@Query` for reactive data
- **Domain Layer**: Services (`TaskService`, `ProjectService`, `StatusEngine`, `DisplayIDAllocator`)
- **Data Layer**: SwiftData with CloudKit sync
- **App Intents Layer**: JSON-based CLI integration

## Test Organization

- **TransitTests**: Unit tests for models, services, and business logic
- **TransitUITests**: End-to-end UI tests

## Build Commands

See the Makefile in the project root for available build and test commands.
