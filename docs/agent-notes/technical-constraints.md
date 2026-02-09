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

## CloudKit Sync

- SwiftData handles sync automatically for Project/Task models.
- Manual `CKRecordZoneSubscription` only needed for the counter record or if finer sync control is desired.
- SwiftData uses zone `com.apple.coredata.cloudkit.zone`.
- Push notifications do not work on Simulator — test on physical devices.
