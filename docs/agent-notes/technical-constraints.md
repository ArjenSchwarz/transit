# Technical Constraints and Decisions

## SwiftData + CloudKit

- All relationships MUST be optional for CloudKit compatibility. Both `tasks: [Task]?` on Project and `project: Project?` on Task.
- No `@Attribute(.unique)` allowed with CloudKit.
- Delete rules: `.cascade` or `.nullify` only, not `.deny`.
- Post-deployment migration is add-only (no renames, no deletions, no type changes).
- Known issue: `#Predicate` cannot query optional to-many relationships ("to-many key not allowed here"). Workaround: query from the child side or filter in-memory.

## displayId Counter Record

- Cannot be implemented through SwiftData. Requires direct CKRecord operations.
- Uses `CKModifyRecordsOperation` with `.ifServerRecordUnchanged` save policy for optimistic locking.
- On conflict (`CKError.serverRecordChanged`), retry by re-fetching server record and incrementing again.
- Hybrid approach: SwiftData for Project/Task, direct CloudKit for counter.

## App Intents JSON I/O

- App Intents use typed `@Parameter` properties, not raw JSON.
- For CLI usage: single `@Parameter(title: "Input") var input: String` that accepts JSON string from `shortcuts run`.
- Return JSON as a `String` via `ReturnsValue<String>`.
- Error responses should be encoded as JSON in the return string (not thrown as errors) so CLI callers get parseable output.

## Liquid Glass

- Primary modifier: `.glassEffect(_:in:isEnabled:)`.
- There is NO `.materialBackground()` modifier — the design doc incorrectly references this.
- Variants: `.regular`, `.clear`, `.identity`.
- Use `GlassEffectContainer` for grouping multiple glass elements (required for shared sampling and morphing).
- Glass is for the navigation/control layer only, not for content.
- `.buttonStyle(.glass)` for secondary, `.buttonStyle(.glassProminent)` for primary actions.

## Drag and Drop

- Use `.draggable()` + `.dropDestination()` with `Transferable` types.
- Cross-ScrollView drops work, but no autoscroll near edges during drag.
- Consider `Transferable` conformance with `CodableRepresentation(contentType: .json)` for typed transfer data.

## Adaptive Layout

- Use `@Environment(\.horizontalSizeClass)` for iPhone vs iPad layout split.
- Use `@Environment(\.verticalSizeClass)` to detect landscape on iPhone.
- `ViewThatFits` is for content adaptation, not structural layout changes.

## Swift 6 Default MainActor Isolation

- Project uses `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` — every type is `@MainActor` by default.
- `@Model` classes are NOT automatically `@MainActor` — they follow standard isolation rules.
- Color extensions using `UIColor`/`NSColor` become `@MainActor` isolated. Use `Color.resolve(in: EnvironmentValues())` to extract RGB components without platform-specific types.
- `Codable` conformance on enums causes `@MainActor` isolation (because `Encoder`/`Decoder` are main-actor-isolated). Avoid `Codable` on pure data enums unless needed — use `Sendable` + `Equatable` instead.
- Test structs need `@MainActor` annotation to access main-actor-isolated types from the app module.
- `@Model` classes should take raw stored types (e.g., `colorHex: String`) in their init, not SwiftUI types like `Color`. Convert at the view layer.

## CloudKit Sync

- SwiftData handles sync automatically for Project/Task models.
- Manual `CKRecordZoneSubscription` only needed for the counter record or if finer sync control is desired.
- SwiftData uses zone `com.apple.coredata.cloudkit.zone`.
- Push notifications do not work on Simulator — test on physical devices.

## ModelContext: mainContext vs ModelContext(container)

`ModelContext(container)` creates an **independent** context with its own change tracking. `container.mainContext` is the shared main-actor-bound context that `@Query` and `@Environment(\.modelContext)` use (when `.modelContainer(container)` is set on the scene).

Services that accept model objects from views **must** use `container.mainContext` -- otherwise mutations happen on the view's context but `save()` targets the service's separate context, silently losing changes. See T-173 for the full bug.

Rule: Never use `ModelContext(container)` for services that interact with view-provided model objects. Always use `container.mainContext`.

## SwiftData Test Container

Creating multiple `ModelContainer` instances for the same schema in one process causes `loadIssueModelContainer` errors. The app's CloudKit entitlements trigger auto-discovery of `@Model` types at test host launch, conflicting with test containers.

**Solution**: Use a shared `TestModelContainer` singleton that creates one container with:
1. An explicit `Schema([Project.self, TransitTask.self])`
2. A named `ModelConfiguration` with `cloudKitDatabase: .none`
3. `isStoredInMemoryOnly: true`

All three are required. Without `cloudKitDatabase: .none`, it conflicts with the CloudKit-enabled default store. Without the explicit `Schema`, the `cloudKitDatabase: .none` parameter crashes.

Each test gets a fresh `ModelContext` via `TestModelContainer.newContext()` for isolation.

Test files that use SwiftData need `@Suite(.serialized)` to avoid concurrent access issues.

## Test File Imports

With `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, test files must explicitly `import Foundation` to use `Date`, `UUID`, `JSONSerialization`, etc. These aren't automatically available in the test target even though the app module imports them.
