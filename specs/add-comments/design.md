# Design: Add Comments (T-46)

## Overview

This design adds a `Comment` SwiftData entity and supporting infrastructure to Transit, enabling users and agents to leave timestamped, attributed comments on tasks. The feature touches five layers: data model, service, UI, MCP server, and App Intents.

The design follows Transit's existing patterns: `@Model` entities with optional CloudKit-compatible relationships, `@MainActor @Observable` services with typed errors, platform-specific views with `#if os()`, and MCP tools dispatched through `MCPToolHandler`.

### Requirement Coverage

| Requirement | Design Section |
|---|---|
| [1] Comment Data Model | Data Models |
| [2] User Display Name | Components: SettingsView |
| [3] Adding Comments via UI | Components: CommentsSection |
| [4] Agent Comment Distinction | Components: CommentRowView |
| [5] Deleting Comments | Components: CommentsSection |
| [6] Comment Count on Cards | Components: TaskCardView |
| [7] App Intent | Components: AddCommentIntent |
| [8] MCP: add_comment | Components: MCPToolHandler |
| [9] MCP: update_task_status | Components: MCPToolHandler |
| [10] MCP: query_tasks | Components: MCPToolHandler |
| [11] Comment Service | Components: CommentService |

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  UI Layer                                               │
│  ┌──────────────┐  ┌──────────────┐  ┌───────────────┐  │
│  │ TaskEditView  │  │ TaskCardView │  │ SettingsView  │  │
│  │ + Comments-   │  │ + comment    │  │ + displayName │  │
│  │   Section     │  │   count      │  │   field       │  │
│  └──────┬───────┘  └──────┬───────┘  └───────────────┘  │
│         │                 │                              │
├─────────┴─────────────────┴──────────────────────────────┤
│  Service Layer                                           │
│  ┌────────────────────────────────────────────────────┐  │
│  │  CommentService (@MainActor @Observable)           │  │
│  │  - addComment(to:content:authorName:isAgent:)      │  │
│  │  - deleteComment(_:)                               │  │
│  │  - fetchComments(for:)                             │  │
│  │  - commentCount(for:)                              │  │
│  └────────────────────────┬───────────────────────────┘  │
│                           │                              │
├───────────────────────────┴──────────────────────────────┤
│  Data Layer                                              │
│  ┌──────────┐     ┌─────────────┐     ┌───────────┐     │
│  │ Comment  │────▶│ TransitTask │────▶│  Project   │     │
│  │ (new)    │     │ (modified)  │     │           │     │
│  └──────────┘     └─────────────┘     └───────────┘     │
│                                                          │
├──────────────────────────────────────────────────────────┤
│  Integration Layer (macOS only for MCP)                  │
│  ┌──────────────────┐  ┌──────────────────────────────┐  │
│  │ MCPToolHandler   │  │ AddCommentIntent             │  │
│  │ + add_comment    │  │ (user-facing Shortcut)       │  │
│  │ + update_status  │  └──────────────────────────────┘  │
│  │   (+ comment)    │                                    │
│  │ + query_tasks    │                                    │
│  │   (+ comments)   │                                    │
│  └──────────────────┘                                    │
└──────────────────────────────────────────────────────────┘
```

---

## Data Models

### Comment Entity

New file: `Transit/Transit/Models/Comment.swift`

```swift
import Foundation
import SwiftData

@Model
final class Comment {
    var id: UUID = UUID()
    var content: String = ""
    var authorName: String = ""
    var isAgent: Bool = false
    var creationDate: Date = Date()

    var task: TransitTask?

    init(
        content: String,
        authorName: String,
        isAgent: Bool,
        task: TransitTask
    ) {
        self.id = UUID()
        self.content = content
        self.authorName = authorName
        self.isAgent = isAgent
        self.creationDate = Date.now
        self.task = task
    }
}
```

**Design notes:**
- All fields have default values (CloudKit requirement) — [req 1.1]
- `task` relationship is optional (CloudKit requirement) — [req 1.3]
- `isAgent` is a stored Bool, set at creation time — [Decision 4]
- No raw-value enum storage needed (no enum fields)

### TransitTask Modification

Add inverse relationship to `TransitTask.swift`:

```swift
@Relationship(deleteRule: .cascade, inverse: \Comment.task)
var comments: [Comment]?
```

**Design notes:**
- `.cascade` ensures deleting a task removes its comments — [req 1.2]
- Optional array for CloudKit compatibility — [req 1.3]
- This relationship is NOT used for querying (see CommentService) — [req 11.5]

### Schema Registration

Update `TransitApp.swift` line 29:

```swift
let schema = Schema([Project.self, TransitTask.self, Comment.self])
```

Update `TestModelContainer.swift` line 11:

```swift
let schema = Schema([Project.self, TransitTask.self, Comment.self])
```

Both updates required by [req 1.4].

---

## Components and Interfaces

### CommentService

New file: `Transit/Transit/Services/CommentService.swift`

```swift
@MainActor @Observable
final class CommentService {

    enum Error: Swift.Error, Equatable {
        case emptyContent
        case emptyAuthorName
        case commentNotFound
    }

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Deletes a comment permanently. [req 5.3]
    func deleteComment(_ comment: Comment) throws {
        modelContext.delete(comment)
        try modelContext.save()
    }

    /// Fetches comments for a task, querying from the Comment side. [req 11.5]
    /// Sorted by creationDate ascending, UUID as tiebreaker. [req 3.2]
    func fetchComments(for taskID: UUID) throws -> [Comment] {
        let descriptor = FetchDescriptor<Comment>(
            predicate: #Predicate { $0.task?.id == taskID },
            sortBy: [
                SortDescriptor(\.creationDate, order: .forward),
                SortDescriptor(\.id, order: .forward)
            ]
        )
        return try modelContext.fetch(descriptor)
    }

    /// Returns comment count for a task. Used by dashboard cards. [req 6.1]
    func commentCount(for taskID: UUID) throws -> Int {
        let descriptor = FetchDescriptor<Comment>(
            predicate: #Predicate { $0.task?.id == taskID }
        )
        return try modelContext.fetchCount(descriptor)
    }

    /// Creates a comment on a task. Validates content and authorName are
    /// non-empty after trimming whitespace.
    /// When `save` is false, the caller is responsible for calling
    /// modelContext.save(). Used for atomic operations where multiple
    /// mutations must be saved together (e.g. status update + comment). [req 9.4]
    @discardableResult
    func addComment(
        to task: TransitTask,
        content: String,
        authorName: String,
        isAgent: Bool,
        save: Bool = true
    ) throws -> Comment {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else { throw Error.emptyContent }

        let trimmedAuthor = authorName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAuthor.isEmpty else { throw Error.emptyAuthorName }

        let comment = Comment(
            content: trimmedContent,
            authorName: trimmedAuthor,
            isAgent: isAgent,
            task: task
        )
        modelContext.insert(comment)
        if save {
            try modelContext.save()
        }
        return comment
    }
}
```

**Design notes:**
- `fetchComments(for:)` takes a UUID, not a TransitTask reference — avoids Sendable issues and follows the SwiftData constraint of querying from the child side
- `addComment(save: false)` enables atomic operations where the caller bundles multiple mutations into a single save — used by `TaskService.updateStatus` when a comment is attached [req 9.4]
- `commentCount(for:)` uses `fetchCount` for efficiency — avoids loading full objects for dashboard cards [req 6.1]
- Predicate `$0.task?.id == taskID` queries from the Comment side through the optional relationship, which is supported by `#Predicate`

### CommentsSection (UI)

New file: `Transit/Transit/Views/TaskDetail/CommentsSection.swift`

This view is added to `TaskEditView` on both platforms. It takes a `TransitTask` and manages its own comment loading/creation state.

```swift
struct CommentsSection: View {
    let task: TransitTask

    @Environment(CommentService.self) private var commentService
    @AppStorage("userDisplayName") private var userDisplayName = ""

    @State private var comments: [Comment] = []
    @State private var newCommentText = ""

    private var trimmedDisplayName: String {
        userDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canAddComment: Bool {
        !newCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !trimmedDisplayName.isEmpty
    }

    var body: some View {
        // Platform-specific layout (see below)
    }

    private func loadComments() {
        comments = (try? commentService.fetchComments(for: task.id)) ?? []
    }

    private func addComment() {
        guard canAddComment else { return }
        _ = try? commentService.addComment(
            to: task,
            content: newCommentText,
            authorName: trimmedDisplayName,
            isAgent: false                    // [req 3.5]
        )
        newCommentText = ""                   // [req 3.6]
        loadComments()
    }

    private func deleteComment(_ comment: Comment) {
        try? commentService.deleteComment(comment)
        loadComments()
    }
}
```

**iOS layout** (inside `Form`):

```swift
Section("Comments") {
    if trimmedDisplayName.isEmpty {
        // [req 2.3] - actionable prompt
        Label("Set your name in Settings to add comments",
              systemImage: "person.crop.circle.badge.exclamationmark")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    if comments.isEmpty {
        Text("No comments yet")             // [req 3.9]
            .foregroundStyle(.tertiary)
    } else {
        ForEach(comments) { comment in
            CommentRowView(comment: comment)
        }
        .onDelete { offsets in              // [req 5.1] swipe to delete
            for index in offsets {
                deleteComment(comments[index])
            }
        }
    }

    if !trimmedDisplayName.isEmpty {
        HStack {
            TextField("Add a comment...", text: $newCommentText)
            Button { addComment() } label: {
                Image(systemName: "arrow.up.circle.fill")
            }
            .disabled(!canAddComment)
        }
    }
}
.onAppear { loadComments() }
```

**macOS layout** (inside `LiquidGlassSection`):

```swift
LiquidGlassSection(title: "Comments") {
    VStack(alignment: .leading, spacing: 0) {
        if trimmedDisplayName.isEmpty {
            // [req 2.3]
            Label("Set your name in Settings to add comments",
                  systemImage: "person.crop.circle.badge.exclamationmark")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
        }

        if comments.isEmpty {
            Text("No comments yet")
                .foregroundStyle(.tertiary)
                .padding(.vertical, 8)
        } else {
            ForEach(comments) { comment in
                CommentRowView(comment: comment, onDelete: {
                    deleteComment(comment)    // [req 5.2] hover button
                })
                if comment.id != comments.last?.id {
                    Divider()
                }
            }
        }

        if !trimmedDisplayName.isEmpty {
            Divider().padding(.vertical, 4)
            HStack {
                TextField("Add a comment...", text: $newCommentText)
                    .textFieldStyle(.plain)
                Button { addComment() } label: {
                    Image(systemName: "arrow.up.circle.fill")
                }
                .disabled(!canAddComment)
            }
        }
    }
}
.onAppear { loadComments() }
```

### CommentRowView

New file: `Transit/Transit/Views/TaskDetail/CommentRowView.swift`

Displays a single comment with author distinction [req 4.1–4.4].

```swift
struct CommentRowView: View {
    let comment: Comment
    var onDelete: (() -> Void)? = nil   // macOS hover delete [req 5.2]

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                // Avatar [req 4.3]
                avatar
                    .frame(width: 20, height: 20)

                // Author name
                Text(comment.authorName)
                    .font(.caption)
                    .fontWeight(.semibold)

                // Agent badge [req 4.2]
                if comment.isAgent {
                    Text("Agent")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.purple.opacity(0.7))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.purple.opacity(0.1), in: Capsule())
                }

                Spacer()

                // Timestamp
                Text(comment.creationDate, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                // macOS delete button [req 5.2]
                #if os(macOS)
                if isHovering, let onDelete {
                    Button(action: onDelete) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                #endif
            }

            // Content
            Text(comment.content)
                .font(.callout)
                .padding(.leading, 26) // align with text after avatar
        }
        .padding(.vertical, 6)
        .background(comment.isAgent ? Color.purple.opacity(0.04) : .clear)  // [req 4.2]
        #if os(macOS)
        .onHover { isHovering = $0 }
        #endif
    }

    @ViewBuilder
    private var avatar: some View {
        if comment.isAgent {
            // Robot icon [req 4.3]
            Image(systemName: "cpu")
                .font(.caption2)
                .foregroundStyle(.purple.opacity(0.7))
                .frame(width: 20, height: 20)
                .background(.purple.opacity(0.1), in: Circle())
        } else {
            // First letter circle [req 4.3]
            Text(String(comment.authorName.prefix(1)).uppercased())
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.blue)
                .frame(width: 20, height: 20)
                .background(.blue.opacity(0.1), in: Circle())
        }
    }
}
```

### TaskEditView Modification

Add `CommentsSection` after the metadata section on both platforms.

**iOS** — add after `MetadataSection`:

```swift
CommentsSection(task: task)
```

**macOS** — add after the Metadata `LiquidGlassSection`:

```swift
CommentsSection(task: task)
```

The `CommentsSection` handles its own `LiquidGlassSection` / `Section` wrapping internally based on platform.

### TaskCardView Modification

Add comment count badge to the badges row [req 6.1–6.3].

```swift
// In the badges HStack, after TypeBadge:
if let count = try? commentService.commentCount(for: task.id), count > 0 {
    Label("\(count)", systemImage: "bubble.left")
        .font(.caption2)
        .foregroundStyle(.secondary)
}
```

This requires adding `@Environment(CommentService.self)` to `TaskCardView`.

**Performance note:** `fetchCount` doesn't load full objects. For a single-user app with dozens of tasks, this is adequate. If performance becomes an issue, a denormalized count field could be added later.

### SettingsView Modification

Add `@AppStorage("userDisplayName")` and a "Your Name" field [req 2.1–2.4].

**iOS** — in `iOSGeneralSection`, before "About Transit":

```swift
TextField("Your Name", text: $userDisplayName)
```

**macOS** — in `macOSGeneralSection`, before "Version" `FormRow`:

```swift
FormRow("Your Name", labelWidth: Self.labelWidth) {
    TextField("", text: $userDisplayName)
        .frame(maxWidth: 200)
}
```

### TransitApp Modification

Create `CommentService` and inject it into the environment.

```swift
// After TaskService/ProjectService creation:
let commentService = CommentService(modelContext: context)
self.commentService = commentService

// In body, add to environment chain:
.environment(commentService)
```

Also pass `CommentService` to `MCPToolHandler`:

```swift
let mcpToolHandler = MCPToolHandler(
    taskService: taskService,
    projectService: projectService,
    commentService: commentService
)
```

### TaskService Modification

Extend `updateStatus` with optional comment parameters for atomic status+comment operations [req 9.4]:

```swift
/// Updates task status. When comment parameters are provided,
/// creates a comment atomically in the same save operation.
@discardableResult
func updateStatus(
    task: TransitTask,
    to newStatus: TaskStatus,
    comment: String? = nil,
    commentAuthor: String? = nil,
    commentService: CommentService? = nil
) throws -> TransitTask {
    StatusEngine.applyTransition(task: task, to: newStatus)

    if let comment, !comment.isEmpty,
       let commentAuthor, let commentService {
        try commentService.addComment(
            to: task,
            content: comment,
            authorName: commentAuthor,
            isAgent: true,
            save: false   // defer save
        )
    }

    try modelContext.save()  // single save for both mutations
    return task
}
```

**Design notes:**
- When called without comment parameters, behaviour is identical to the existing implementation [req 9.5]
- The `save: false` parameter on `addComment` defers persistence until `TaskService` calls `modelContext.save()`, ensuring atomicity [req 9.4]
- `commentService` is passed as a parameter rather than stored, since only the MCP path needs it

### MCPToolHandler Modifications

**New `add_comment` tool** [req 8.1–8.6]:

```swift
case "add_comment":
    result = handleAddComment(arguments)
```

```swift
private func handleAddComment(_ args: [String: Any]) -> MCPToolResult {
    // 1. Validate required args: content, authorName
    // 2. Resolve task by displayId or taskId
    // 3. Call commentService.addComment(to:content:authorName:isAgent: true)
    // 4. Return JSON with comment id, authorName, content, creationDate
}
```

**Modified `update_task_status`** [req 9.1–9.6]:

The MCP handler extracts optional `comment` and `authorName` from arguments and passes them through to `TaskService.updateStatus`:

```swift
// Extract optional comment fields
let commentText = args["comment"] as? String
let commentAuthor = args["authorName"] as? String

// Validate: authorName required when comment is present [req 9.3]
if let commentText, !commentText.isEmpty {
    guard let commentAuthor, !commentAuthor.isEmpty else {
        return errorResult("authorName is required when comment is provided")
    }
}

// Single call handles status + optional comment atomically
try taskService.updateStatus(
    task: task, to: newStatus,
    comment: commentText,
    commentAuthor: commentAuthor,
    commentService: commentService
)
```

**Atomicity note:** `TaskService.updateStatus` is extended with optional `comment`, `commentAuthor`, and `commentService` parameters. When a comment is provided, the method calls `StatusEngine.applyTransition`, then `commentService.addComment(save: false)`, then a single `modelContext.save()` — all in one transaction [req 9.4]. When no comment is provided, the existing behaviour is unchanged [req 9.5].

**Modified `query_tasks`** [req 10.1–10.4]:

In `taskToDict`, add comments array:

```swift
// In taskToDict (always included, not just detailed):
let comments = (try? commentService.fetchComments(for: task.id)) ?? []
dict["comments"] = comments.map { comment -> [String: Any] in
    var c: [String: Any] = [
        "id": comment.id.uuidString,
        "authorName": comment.authorName,
        "content": comment.content,
        "isAgent": comment.isAgent,
        "creationDate": formatter.string(from: comment.creationDate)
    ]
    return c
}
```

**Updated tool definitions** in `MCPToolDefinitions`:

```swift
// Add to MCPToolDefinitions.all:
static let all: [MCPToolDefinition] = [
    createTask, updateTaskStatus, queryTasks, addComment
]

// New tool definition:
static let addComment = MCPToolDefinition(
    name: "add_comment",
    description: "Add a comment to a task. Identify the task by displayId or taskId.",
    inputSchema: .object(
        properties: [
            "displayId": .integer("Task display ID (e.g. 42 for T-42)"),
            "taskId": .string("Task UUID"),
            "content": .string("Comment text (required)"),
            "authorName": .string("Author name (required)")
        ],
        required: ["content", "authorName"]
    )
)

// Update updateTaskStatus properties to include comment/authorName:
static let updateTaskStatus = MCPToolDefinition(
    name: "update_task_status",
    description: updateTaskStatusDescription,
    inputSchema: .object(
        properties: [
            "displayId": .integer("Task display ID (e.g. 42 for T-42)"),
            "taskId": .string("Task UUID"),
            "status": .stringEnum("Target status (required)",
                                  values: TaskStatus.allCases.map(\.rawValue)),
            "comment": .string("Optional comment to add with status change"),
            "authorName": .string("Author name (required when comment is provided)")
        ],
        required: ["status"]
    )
)
```

### AddCommentIntent (User-Facing Shortcut)

New file: `Transit/Transit/Intents/AddCommentIntent.swift`

```swift
import AppIntents
import Foundation

struct AddCommentIntent: AppIntent {
    nonisolated(unsafe) static var title: LocalizedStringResource =
        "Transit: Add Comment"

    nonisolated(unsafe) static var description = IntentDescription(
        "Add a comment to a Transit task.",
        categoryName: "Tasks"
    )

    nonisolated(unsafe) static var openAppWhenRun: Bool = true

    @Parameter(title: "Task", description: "Display ID (e.g. 42) or UUID")
    var taskIdentifier: String

    @Parameter(title: "Comment")
    var commentText: String

    @Parameter(title: "Author Name")
    var authorName: String

    @Parameter(title: "Agent Comment", default: true)
    var isAgent: Bool

    @Dependency
    private var taskService: TaskService

    @Dependency
    private var commentService: CommentService

    @MainActor
    func perform() async throws -> some IntentResult {
        // Resolve task
        let task: TransitTask
        if let displayId = Int(taskIdentifier) {
            task = try taskService.findByDisplayID(displayId)
        } else if let uuid = UUID(uuidString: taskIdentifier) {
            task = try taskService.findByID(uuid)
        } else {
            throw IntentError.taskNotFound(
                hint: "Invalid task identifier: \(taskIdentifier)"
            )
        }

        // Validate and create comment [req 7.5]
        let trimmed = commentText
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw IntentError.invalidInput(hint: "Comment text is empty")
        }
        let trimmedAuthor = authorName
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAuthor.isEmpty else {
            throw IntentError.invalidInput(hint: "Author name is empty")
        }

        // isAgent defaults to true for Shortcut/automation [req 7.3]
        // but can be toggled by the user
        try commentService.addComment(
            to: task,
            content: trimmed,
            authorName: trimmedAuthor,
            isAgent: isAgent
        )

        return .result()
    }
}
```

**Design notes:**
- Uses typed `@Parameter` instead of JSON string [Decision 5]
- Throws native errors instead of JSON-encoded error responses — appropriate for user-facing Shortcuts [req 7.4]
- `isAgent` defaults to `true` (automation use case) but can be toggled by the user in the Shortcut [req 7.3]
- Register with `AppDependencyManager` for `CommentService` in `TransitApp.init`

### AppDependencyManager Registration

In `TransitApp.init()`, after existing dependency registrations:

```swift
AppDependencyManager.shared.add(dependency: commentService)
```

---

## Error Handling

### CommentService.Error

| Case | Trigger | Used By |
|---|---|---|
| `emptyContent` | Content is empty/whitespace after trimming | UI, MCP, Intent |
| `emptyAuthorName` | Author name is empty/whitespace after trimming | UI, MCP, Intent |
| `commentNotFound` | Comment UUID not found in store | Future use (delete by ID) |

### MCP Error Responses

MCP tools return `errorResult(message)` strings. New error messages:

| Scenario | Message |
|---|---|
| Missing content | `"Missing required argument: content"` |
| Missing authorName (on add_comment) | `"Missing required argument: authorName"` |
| Missing authorName (on update with comment) | `"authorName is required when comment is provided"` |
| Task not found | Reuses existing `"No task with displayId X"` pattern |
| Empty content after trim | `"Comment content cannot be empty"` |

### App Intent Errors

The `AddCommentIntent` throws `IntentError` cases. These are the existing typed errors from `IntentError.swift` — no new error types needed:

- `.taskNotFound(hint:)` — task identifier doesn't resolve
- `.invalidInput(hint:)` — empty content or author name

---

## Testing Strategy

### CommentServiceTests

New file: `Transit/TransitTests/CommentServiceTests.swift`

Uses Swift Testing framework with `@Suite(.serialized)` and `TestModelContainer.newContext()`.

**Tests covering service requirements [req 11.1–11.5]:**

| Test | Requirement |
|---|---|
| `addComment_createsWithCorrectFields` | 11.2 |
| `addComment_emptyContent_throws` | 11.3 |
| `addComment_whitespaceOnlyContent_throws` | 11.3 |
| `addComment_emptyAuthorName_throws` | 11.3 |
| `addComment_trimmedContent_isSaved` | 11.3 |
| `deleteComment_removesFromStore` | 11.2 |
| `fetchComments_orderedByCreationDate` | 11.5, 3.2 |
| `fetchComments_emptyForTaskWithNoComments` | 3.9 |
| `fetchComments_queriesFromCommentSide` | 11.5 |
| `commentCount_returnsCorrectCount` | 6.1 |
| `commentCount_returnsZeroForNoComments` | 6.2 |
| `addComment_savesFalse_doesNotPersistUntilExplicitSave` | 9.4 |
| `cascadeDelete_removesCommentsWhenTaskDeleted` | 1.2 |
| `isAgent_preservedOnCreation` | 4.1 |

### TaskServiceTests (additions)

Add to existing `Transit/TransitTests/TaskServiceTests.swift`:

| Test | Requirement |
|---|---|
| `updateStatus_withComment_createsCommentAtomically` | 9.4 |
| `updateStatus_withComment_setsIsAgentTrue` | 9.2 |
| `updateStatus_withoutComment_behavesAsExisting` | 9.5 |

### MCPToolHandlerTests

Add to existing `Transit/TransitTests/MCPToolHandlerTests.swift`:

**Tests covering MCP requirements [req 8–10]:**

| Test | Requirement |
|---|---|
| `addComment_validInput_createsComment` | 8.1, 8.3 |
| `addComment_missingContent_returnsError` | 8.5 |
| `addComment_missingAuthorName_returnsError` | 8.5 |
| `addComment_taskNotFound_returnsError` | 8.4 |
| `addComment_setsIsAgentTrue` | 8.3 |
| `updateStatus_withComment_passesCommentToTaskService` | 9.2 |
| `updateStatus_withComment_requiresAuthorName` | 9.3 |
| `updateStatus_withoutComment_behavesAsExisting` | 9.5 |
| `queryTasks_includesCommentsArray` | 10.1 |
| `queryTasks_commentsOrderedChronologically` | 10.3 |
| `queryTasks_noComments_emptyArray` | 10.4 |

### AddCommentIntentTests

New file: `Transit/TransitTests/AddCommentIntentTests.swift`

| Test | Requirement |
|---|---|
| `perform_validInput_createsComment` | 7.3 |
| `perform_taskNotFound_throwsError` | 7.4 |
| `perform_emptyContent_throwsError` | 7.5 |
| `perform_emptyAuthorName_throwsError` | 7.5 |
| `perform_defaultsIsAgentTrue` | 7.3 |
| `perform_isAgentFalse_whenToggled` | 7.3 |
| `perform_acceptsDisplayIdString` | 7.1 |
| `perform_acceptsUUIDString` | 7.1 |

---

## Files Summary

### New Files

| File | Purpose |
|---|---|
| `Transit/Transit/Models/Comment.swift` | Comment entity |
| `Transit/Transit/Services/CommentService.swift` | Comment business logic |
| `Transit/Transit/Views/TaskDetail/CommentsSection.swift` | Comments UI section |
| `Transit/Transit/Views/TaskDetail/CommentRowView.swift` | Single comment display |
| `Transit/Transit/Intents/AddCommentIntent.swift` | User-facing Shortcut |
| `Transit/TransitTests/CommentServiceTests.swift` | Service unit tests |
| `Transit/TransitTests/AddCommentIntentTests.swift` | Intent unit tests |

### Modified Files

| File | Change |
|---|---|
| `Transit/Transit/Models/TransitTask.swift` | Add `comments` relationship |
| `Transit/Transit/Services/TaskService.swift` | Extend `updateStatus` with optional comment params |
| `Transit/Transit/TransitApp.swift` | Schema + CommentService + MCPToolHandler init |
| `Transit/Transit/Views/TaskDetail/TaskEditView.swift` | Add CommentsSection |
| `Transit/Transit/Views/Settings/SettingsView.swift` | Add "Your Name" field |
| `Transit/Transit/Views/Dashboard/TaskCardView.swift` | Add comment count badge |
| `Transit/Transit/MCP/MCPToolHandler.swift` | add_comment, update_status, query_tasks |
| `Transit/TransitTests/TestModelContainer.swift` | Schema update |
| `Transit/TransitTests/MCPToolHandlerTests.swift` | New MCP comment tests |
