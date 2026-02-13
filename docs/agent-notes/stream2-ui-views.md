# Stream 2 UI Views

## Location
`Transit/Transit/Views/`

## AddTaskSheet
`Views/AddTask/AddTaskSheet.swift`
- Presented as `.sheet` from DashboardView via `showAddTask` state
- Uses `.presentationDetents([.medium])` for iPhone bottom sheet
- Project picker with `ProjectColorDot` + name, type picker, name (required) and description (optional) fields
- No status picker — always creates in `.idea` via `TaskService.createTask()`
- When no projects exist, shows `EmptyStateView` directing to Settings
- Default project selection: first project on appear
- **Platform-specific layout**: iOS uses standard `Form`; macOS uses `ScrollView` > `VStack` with `LiquidGlassSection` containers, `Grid` + `FormRow`

## TaskDetailView
`Views/TaskDetail/TaskDetailView.swift`
- Presented as `.sheet(item: $selectedTask)` from DashboardView
- Read-only display: display ID as nav title, name, type (TypeBadge), status, project (with color dot), description, metadata
- Edit button presents TaskEditView as a nested `.sheet`
- Action section: Abandon button (for non-terminal tasks), Restore button (for abandoned tasks)
- Uses `.presentationDetents([.medium, .large])`
- **Platform-specific layout**: iOS uses standard `Form`; macOS uses `ScrollView` > `VStack` with `LiquidGlassSection` containers, `Grid` + `FormRow` for read-only detail fields. Toolbar and action buttons shared via extracted computed properties.

## TaskEditView
`Views/TaskDetail/TaskEditView.swift`
- Presented as `.sheet` from TaskDetailView's Edit button
- Editable fields: name, description, type picker, project picker, status picker
- Status changes go through `TaskService.updateStatus()` for side effects (completionDate, lastStatusChangeDate)
- MetadataSection in editing mode
- Loads task data into local `@State` on appear, saves back on Save
- **Platform-specific layout**: iOS uses standard `Form`; macOS uses `ScrollView` > `VStack` with `LiquidGlassSection` containers, `Grid` + `FormRow` for right-aligned labels, text fields fill row width, pickers use `.fixedSize()`, and a bottom-right Save button

## SettingsView
`Views/Settings/SettingsView.swift`
- Pushed via `NavigationLink(value: NavigationDestination.settings)` from DashboardView toolbar
- Custom chevron-only back button (hides default back button label)
- Projects section: color swatch (rounded square with initial letter), project name, active task count
- Project rows use `NavigationLink(value: NavigationDestination.projectEdit(project))` — navigation handled by TransitApp's `navigationDestination`
- "+" button in section header presents `ProjectEditView(project: nil)` as a sheet
- General section: About Transit (bundle version), iCloud Sync toggle (`@AppStorage("syncEnabled")`)

## ProjectEditView
`Views/Settings/ProjectEditView.swift`
- Dual-purpose: `project: Project?` — nil for create, non-nil for edit
- Fields: name, description (multiline), git repo URL (optional), ColorPicker
- Save disabled until name and description are non-empty
- Create mode: uses `ProjectService.createProject()`
- Edit mode: directly mutates project properties
- Pushed for edit (via NavigationDestination), presented as sheet for create
- **Platform-specific layout**: iOS uses standard `Form`; macOS uses `ScrollView` > `VStack` with `LiquidGlassSection` containers, `Grid` + `FormRow`, with bottom-right Save button

## DashboardView Integration
- `showAddTask: Bool` state triggers AddTaskSheet via `.sheet`
- `selectedTask: TransitTask?` triggers TaskDetailView via `.sheet(item:)`
- Settings gear navigates via `NavigationLink(value: NavigationDestination.settings)`
- Placeholder views in TransitApp.swift were removed (real implementations live in their own files)

## NavigationDestination
`Models/NavigationDestination.swift`
- `.settings` — pushes SettingsView
- `.projectEdit(Project)` — pushes ProjectEditView for editing
- Handled by `navigationDestination(for:)` in TransitApp.swift
