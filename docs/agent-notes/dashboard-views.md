# Dashboard Views

## Location
`Transit/Transit/Views/Dashboard/`

## Components

### DashboardView
- Root view, displayed on every launch
- Uses `GeometryReader` with `columnMinWidth: 200` to determine layout
- `columnCount == 1` → `SingleColumnView` (iPhone portrait, narrow iPad Split View)
- `columnCount > 1` → `KanbanBoardView` (iPad, Mac, iPhone landscape)
- iPhone landscape: caps at 3 columns, defaults scroll to Planning column
- `@Query` for allTasks and projects — reactive data from SwiftData
- `selectedProjectIDs: Set<UUID>` is ephemeral (resets on launch)
- `buildFilteredColumns()` is a static method for testability
- Toolbar: filter + add in `.primaryAction` group, gear in `.secondaryAction`
- `TransitTask` extended with `@retroactive Identifiable` for `.sheet(item:)`

### TaskCardView
- Glass effect + project color border (1.5pt)
- Shows: project name, task name (strikethrough if abandoned), display ID, type badge
- Abandoned tasks render at 50% opacity
- `.draggable(task.id.uuidString)` for drag-and-drop

### ColumnView
- Header with column name + task count
- Empty state via `EmptyStateView` when no tasks
- Done/Abandoned column: separator divider before first abandoned task
- `onDrop: ((String) -> Bool)?` callback for drag-and-drop
- `.contentShape(.rect)` required for reliable drop hit-testing (Spacers/ScrollViews don't cover full frame without it)
- `isDropTargeted` state with tint background provides visual feedback during drag hover

### KanbanBoardView
- Horizontal `ScrollView` with `.viewAligned` scroll target behavior
- `.scrollTargetLayout()` on HStack for per-column snap alignment
- Column width = available width / visible count
- `initialScrollTarget` for iPhone landscape (scrolls to Planning)
- Note: `.paging` was removed — it jumps full viewport width and breaks drag-and-drop auto-scroll

### SingleColumnView
- Native segmented control (`Picker(.segmented)`) with short labels and counts
- Default segment: `.inProgress` ("Active")
- ZStack overlay on picker: invisible drop targets per segment enable cross-column drag-and-drop
- Picker has `.allowsHitTesting(false)`; overlay handles both taps and drops
- When drag hovers over a segment, `selectedColumn` switches to preview the target column

### FilterPopoverView
- Lists all projects with color dot, name, checkmark
- Toggle project selection in/out of `selectedProjectIDs`
- Clear button appears when filter is active

## Column Filtering & Sorting Logic
Implemented in `DashboardView.buildFilteredColumns()`:
1. Filter by selected projects (empty = show all, but exclude nil project)
2. 48-hour cutoff for terminal tasks (nil completionDate treated as just-completed)
3. Sort: done before abandoned, handoff before regular, then by date desc

## Drag-and-Drop
- TaskCardView is `.draggable()` with UUID string
- ColumnView has `.dropDestination(for: String.self)` with `.contentShape(.rect)` for full-frame hit testing
- Drop resolves UUID → task → applies `column.primaryStatus` via TaskService
- Done/Abandoned column always assigns `.done` (never `.abandoned` via drag)
- SingleColumnView: segmented control segments are drop targets via ZStack overlay
- KanbanBoardView: `.viewAligned` scroll behavior enables column-by-column auto-scroll during drag

### Gotchas
- Always use `.contentShape(.rect)` on views with `.dropDestination` that contain Spacers or ScrollViews
- Avoid `.scrollTargetBehavior(.paging)` with drag-and-drop — use `.viewAligned` instead
- On iPhone portrait, cross-column drag requires the segmented control overlay (no other visible drop targets)
