# Shared UI Components

## Location
`Transit/Transit/Views/Shared/`

## Components

### EmptyStateView
- Takes a `message: String` parameter
- Uses `ContentUnavailableView` with a tray icon
- Used for: empty dashboard, empty columns, no projects, empty settings

### ProjectColorDot
- Takes a `color: Color` parameter
- 12x12 rounded rectangle (cornerRadius 4) filled with the color
- Used in: task cards, settings project rows, project picker

### TypeBadge
- Takes a `type: TaskType` parameter
- Capsule-shaped badge with tinted background (15% opacity) and colored text
- Uses `TaskType.tintColor` computed property (added to `TaskType.swift`)
- Colors: bug=red, feature=blue, chore=orange, research=purple, documentation=green

### MetadataSection
- Takes `@Binding var metadata: [String: String]` and `isEditing: Bool`
- Read mode: shows key-value pairs via `LabeledContent`, or "No metadata" when empty
- Edit mode: editable values, delete buttons, and an `AddMetadataRow` for adding new pairs
- `AddMetadataRow` is a `private` struct in the same file
- Platform-adaptive: on iOS wraps content in `Section("Metadata")` for Form/List; on macOS outputs bare content (caller wraps in `LiquidGlassSection`)

### FormRow (macOS only)
- Generic `GridRow`-based component: right-aligned label + content column
- Takes `label: String`, `labelWidth: CGFloat`, and `@ViewBuilder content`
- Used inside `Grid` containers for macOS Liquid Glass form layouts

### LiquidGlassSection (macOS only)
- `VStack` with headline title + `.background { RoundedRectangle.glassEffect(.regular, in:) }` on content
- Used to group form sections with a glass container background
- Glass is structural only — not applied to individual rows
- Note: `glassBackgroundEffect(displayMode:)` is visionOS-only and does NOT compile on macOS

## TaskType.tintColor
Added directly in `Transit/Transit/Models/TaskType.swift`. Required changing `import Foundation` to `import SwiftUI` since `Color` is a SwiftUI type.
