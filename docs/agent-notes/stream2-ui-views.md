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
- **Error handling (T-153)**: `save()` is async, awaits `createTask` before dismissing. On failure, shows "Save Failed" alert via `errorMessage` state (same pattern as TaskEditView/ProjectEditView). `isSaving` state disables the save button during the async operation to prevent double-taps. Sheet stays open on failure so user can retry.
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
- **Error handling (T-148)**: `save()` uses `do/catch` with `modelContext.rollback()` on failure. Shows "Save Failed" alert via `errorMessage` state and `showError` binding (same pattern as CommentsSection/ProjectEditView). Editor stays open on failure so user can retry.
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

## CommentRowView
`Views/TaskDetail/CommentRowView.swift`
- Displays a single comment with author avatar, name, relative timestamp, and content
- Agent comments: `cpu` system image avatar with purple tint, purple background (`Color.purple.opacity(0.04)`), "Agent" capsule badge
- User comments: first-letter circle avatar with blue tint
- macOS-only: hover-reveal delete button (`xmark.circle.fill`) via `onHover`
- Content text indented with `.padding(.leading, 26)` to align past the avatar
- Takes `onDelete: (() -> Void)?` closure for delete action

## TaskCardView Comment Badge
`Views/Dashboard/TaskCardView.swift`
- `@Environment(CommentService.self)` injected for comment count queries
- In the badges HStack (after `TypeBadge`), shows `Label("\(count)", systemImage: "bubble.left")` when count > 0
- Uses `commentService.commentCount(for: task.id)` with `try?` to silently handle errors

## macOS TextEditor Styling Pattern

On macOS, TextEditor inside LiquidGlassSection requires explicit background styling. The pattern:
1. `.scrollContentBackground(.hidden)` removes the default NSScrollView background
2. Must add replacement: `.padding(4)`, `.background(Color(.textBackgroundColor))`, `.clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))`, and a subtle border overlay

Applied to: AddTaskSheet (macOS description), TaskEditView (macOS description), CommentsSection (comment input, `#if os(macOS)` conditional). Without this, TextEditor blends invisibly into the glass section background.

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
