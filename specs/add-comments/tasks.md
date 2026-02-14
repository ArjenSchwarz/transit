---
references:
    - requirements.md
    - design.md
    - decision_log.md
---
# Add Comments (T-46)

## Foundation

- [x] 1. Create Comment entity and update data model <!-- id:8s2zs08 -->
  - Create Transit/Transit/Models/Comment.swift with @Model class (id, content, authorName, isAgent, creationDate, task)
  - Add @Relationship(deleteRule: .cascade, inverse: \Comment.task) var comments: [Comment]? to TransitTask.swift
  - Update schema in TransitApp.swift and TestModelContainer.swift to include Comment.self
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.3](requirements.md#1.3), [1.4](requirements.md#1.4)
  - References: Transit/Transit/Models/Comment.swift, Transit/Transit/Models/TransitTask.swift, Transit/Transit/TransitApp.swift, Transit/TransitTests/TestModelContainer.swift

- [x] 2. Implement CommentService <!-- id:8s2zs09 -->
  - Create Transit/Transit/Services/CommentService.swift with @MainActor @Observable
  - Implement addComment(to:content:authorName:isAgent:save:) with whitespace validation and save: Bool = true parameter
  - Implement deleteComment(_:), fetchComments(for:), commentCount(for:)
  - Use FetchDescriptor with predicate on task UUID (query from Comment side)
  - Typed Error enum: emptyContent, emptyAuthorName, commentNotFound
  - Blocked-by: 8s2zs08 (Create Comment entity and update data model)
  - Stream: 1
  - Requirements: [11.1](requirements.md#11.1), [11.2](requirements.md#11.2), [11.3](requirements.md#11.3), [11.4](requirements.md#11.4), [11.5](requirements.md#11.5)
  - References: Transit/Transit/Services/CommentService.swift, Transit/Transit/Services/TaskService.swift

- [x] 3. Write CommentService tests <!-- id:8s2zs0a -->
  - Create Transit/TransitTests/CommentServiceTests.swift with @Suite(.serialized)
  - Test addComment creates with correct fields, validates empty content/author, trims whitespace
  - Test deleteComment removes from store
  - Test fetchComments ordered by creationDate + UUID tiebreaker
  - Test commentCount returns correct count and zero for no comments
  - Test addComment(save: false) does not persist until explicit save
  - Test cascade delete removes comments when task deleted
  - Test isAgent preserved on creation
  - Blocked-by: 8s2zs09 (Implement CommentService)
  - Stream: 1
  - Requirements: [11.2](requirements.md#11.2), [11.3](requirements.md#11.3), [11.5](requirements.md#11.5), [1.2](requirements.md#1.2), [3.2](requirements.md#3.2), [3.9](requirements.md#3.9), [4.1](requirements.md#4.1), [6.1](requirements.md#6.1), [6.2](requirements.md#6.2), [9.4](requirements.md#9.4)
  - References: Transit/TransitTests/CommentServiceTests.swift

## Service Extension

- [x] 4. Extend TaskService.updateStatus with optional comment parameters <!-- id:8s2zs0b -->
  - Add optional comment: String?, commentAuthor: String?, commentService: CommentService? parameters to updateStatus
  - When comment is provided, call commentService.addComment(save: false) before modelContext.save()
  - Without comment parameters, behaviour is identical to existing implementation
  - Blocked-by: 8s2zs09 (Implement CommentService)
  - Stream: 1
  - Requirements: [9.4](requirements.md#9.4), [9.5](requirements.md#9.5)
  - References: Transit/Transit/Services/TaskService.swift

- [x] 5. Write TaskService comment tests <!-- id:8s2zs0c -->
  - Add tests to Transit/TransitTests/TaskServiceTests.swift
  - Test updateStatus with comment creates comment atomically
  - Test comment has isAgent = true
  - Test updateStatus without comment behaves as existing
  - Blocked-by: 8s2zs0b (Extend TaskService.updateStatus with optional comment parameters)
  - Stream: 1
  - Requirements: [9.2](requirements.md#9.2), [9.4](requirements.md#9.4), [9.5](requirements.md#9.5)
  - References: Transit/TransitTests/TaskServiceTests.swift

## UI

- [x] 6. Add Your Name field to SettingsView <!-- id:8s2zs0d -->
  - Add @AppStorage("userDisplayName") to SettingsView
  - iOS: TextField in iOSGeneralSection before About Transit
  - macOS: FormRow in macOSGeneralSection before Version row
  - Default value: empty string
  - Stream: 2
  - Requirements: [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [2.4](requirements.md#2.4)
  - References: Transit/Transit/Views/Settings/SettingsView.swift

- [x] 7. Create CommentRowView <!-- id:8s2zs0e -->
  - Create Transit/Transit/Views/TaskDetail/CommentRowView.swift
  - Show author name, relative timestamp, content
  - Agent comments: robot icon avatar, purple tint background, Agent badge
  - User comments: first-letter circle avatar
  - macOS: hover delete button with onHover
  - Blocked-by: 8s2zs08 (Create Comment entity and update data model)
  - Stream: 2
  - Requirements: [3.3](requirements.md#3.3), [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [4.3](requirements.md#4.3), [4.4](requirements.md#4.4), [5.2](requirements.md#5.2)
  - References: Transit/Transit/Views/TaskDetail/CommentRowView.swift

- [x] 8. Create CommentsSection and integrate into TaskEditView <!-- id:8s2zs0f -->
  - Create Transit/Transit/Views/TaskDetail/CommentsSection.swift
  - iOS: Section(Comments) inside Form with .onDelete for swipe
  - macOS: LiquidGlassSection(title: Comments) with VStack
  - Empty state: No comments yet when no comments
  - Display name empty: show actionable message directing to Settings
  - Text input with send button, clear on send
  - Add CommentsSection(task: task) to TaskEditView after metadata section on both platforms
  - Blocked-by: 8s2zs09 (Implement CommentService), 8s2zs0d (Add Your Name field to SettingsView), 8s2zs0e (Create CommentRowView)
  - Stream: 2
  - Requirements: [2.3](requirements.md#2.3), [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.4](requirements.md#3.4), [3.5](requirements.md#3.5), [3.6](requirements.md#3.6), [3.7](requirements.md#3.7), [3.8](requirements.md#3.8), [3.9](requirements.md#3.9), [5.1](requirements.md#5.1), [5.4](requirements.md#5.4)
  - References: Transit/Transit/Views/TaskDetail/CommentsSection.swift, Transit/Transit/Views/TaskDetail/TaskEditView.swift

- [x] 9. Add comment count badge to TaskCardView <!-- id:8s2zs0g -->
  - Add @Environment(CommentService.self) to TaskCardView
  - In badges HStack, show bubble.left icon with count when > 0
  - Use commentService.commentCount(for:) with fetchCount for efficiency
  - Blocked-by: 8s2zs09 (Implement CommentService)
  - Stream: 2
  - Requirements: [6.1](requirements.md#6.1), [6.2](requirements.md#6.2), [6.3](requirements.md#6.3)
  - References: Transit/Transit/Views/Dashboard/TaskCardView.swift

## Integration

- [x] 10. Implement MCP add_comment tool <!-- id:8s2zs0h -->
  - Add handleAddComment to MCPToolHandler
  - Add case add_comment to handleToolCall dispatch
  - Validate content and authorName, resolve task by displayId or taskId
  - Call commentService.addComment with isAgent: true
  - Return JSON with comment id, authorName, content, creationDate
  - Add addComment tool definition to MCPToolDefinitions.all
  - Blocked-by: 8s2zs09 (Implement CommentService)
  - Stream: 3
  - Requirements: [8.1](requirements.md#8.1), [8.2](requirements.md#8.2), [8.3](requirements.md#8.3), [8.4](requirements.md#8.4), [8.5](requirements.md#8.5), [8.6](requirements.md#8.6)
  - References: Transit/Transit/MCP/MCPToolHandler.swift, Transit/Transit/MCP/MCPTypes.swift

- [x] 11. Modify MCP update_task_status for optional comment <!-- id:8s2zs0i -->
  - Extract optional comment and authorName from arguments
  - Validate authorName required when comment present
  - Pass comment params to taskService.updateStatus for atomic save
  - Update updateTaskStatus tool definition with comment/authorName properties
  - Include comment details in response when created
  - Blocked-by: 8s2zs0b (Extend TaskService.updateStatus with optional comment parameters)
  - Stream: 3
  - Requirements: [9.1](requirements.md#9.1), [9.2](requirements.md#9.2), [9.3](requirements.md#9.3), [9.4](requirements.md#9.4), [9.5](requirements.md#9.5), [9.6](requirements.md#9.6)
  - References: Transit/Transit/MCP/MCPToolHandler.swift

- [x] 12. Modify MCP query_tasks to include comments <!-- id:8s2zs0j -->
  - In taskToDict, add comments array via commentService.fetchComments
  - Each comment includes id, authorName, content, isAgent, creationDate
  - Comments ordered chronologically (oldest first)
  - Empty array for tasks with no comments
  - Blocked-by: 8s2zs09 (Implement CommentService)
  - Stream: 3
  - Requirements: [10.1](requirements.md#10.1), [10.2](requirements.md#10.2), [10.3](requirements.md#10.3), [10.4](requirements.md#10.4)
  - References: Transit/Transit/MCP/MCPToolHandler.swift

- [x] 13. Write MCP comment tests <!-- id:8s2zs0k -->
  - Add tests to Transit/TransitTests/MCPToolHandlerTests.swift
  - Test add_comment: valid input, missing content/author, task not found, isAgent=true
  - Test update_task_status: with comment passes to TaskService, requires authorName, without comment unchanged
  - Test query_tasks: includes comments array, ordered chronologically, empty array for no comments
  - Blocked-by: 8s2zs0h (Implement MCP add_comment tool), 8s2zs0i (Modify MCP update_task_status for optional comment), 8s2zs0j (Modify MCP query_tasks to include comments)
  - Stream: 3
  - Requirements: [8.1](requirements.md#8.1), [8.3](requirements.md#8.3), [8.4](requirements.md#8.4), [8.5](requirements.md#8.5), [9.2](requirements.md#9.2), [9.3](requirements.md#9.3), [9.5](requirements.md#9.5), [10.1](requirements.md#10.1), [10.3](requirements.md#10.3), [10.4](requirements.md#10.4)
  - References: Transit/TransitTests/MCPToolHandlerTests.swift

- [x] 14. Create AddCommentIntent <!-- id:8s2zs0l -->
  - Create Transit/Transit/Intents/AddCommentIntent.swift
  - Typed @Parameter: taskIdentifier (String), commentText (String), authorName (String), isAgent (Bool, default: true)
  - Resolve task by display ID or UUID
  - Validate non-empty content and author after trimming
  - Throw IntentError for task not found and invalid input
  - openAppWhenRun = true
  - Blocked-by: 8s2zs09 (Implement CommentService)
  - Stream: 3
  - Requirements: [7.1](requirements.md#7.1), [7.2](requirements.md#7.2), [7.3](requirements.md#7.3), [7.4](requirements.md#7.4), [7.5](requirements.md#7.5)
  - References: Transit/Transit/Intents/AddCommentIntent.swift, Transit/Transit/Intents/CreateTaskIntent.swift

- [x] 15. Write AddCommentIntent tests <!-- id:8s2zs0m -->
  - Create Transit/TransitTests/AddCommentIntentTests.swift
  - Test valid input creates comment
  - Test task not found throws error
  - Test empty content/author throws error
  - Test isAgent defaults to true
  - Test isAgent false when toggled
  - Test accepts display ID and UUID string
  - Blocked-by: 8s2zs0l (Create AddCommentIntent)
  - Stream: 3
  - Requirements: [7.1](requirements.md#7.1), [7.3](requirements.md#7.3), [7.4](requirements.md#7.4), [7.5](requirements.md#7.5)
  - References: Transit/TransitTests/AddCommentIntentTests.swift

## Wiring

- [x] 16. Wire CommentService in TransitApp and register dependencies <!-- id:8s2zs0n -->
  - Create CommentService in TransitApp.init after TaskService/ProjectService
  - Inject into environment chain: .environment(commentService)
  - Pass to MCPToolHandler init: commentService parameter
  - Register with AppDependencyManager.shared.add(dependency: commentService)
  - Blocked-by: 8s2zs09 (Implement CommentService), 8s2zs0h (Implement MCP add_comment tool), 8s2zs0l (Create AddCommentIntent)
  - Stream: 1
  - Requirements: [11.1](requirements.md#11.1), [1.4](requirements.md#1.4)
  - References: Transit/Transit/TransitApp.swift

- [x] 17. Build verification and lint <!-- id:8s2zs0o -->
  - Run make build to verify both iOS and macOS compile
  - Run make test-quick for unit tests
  - Run make lint and fix any issues
  - Blocked-by: 8s2zs08 (Create Comment entity and update data model), 8s2zs09 (Implement CommentService), 8s2zs0a (Write CommentService tests), 8s2zs0b (Extend TaskService.updateStatus with optional comment parameters), 8s2zs0c (Write TaskService comment tests), 8s2zs0d (Add Your Name field to SettingsView), 8s2zs0e (Create CommentRowView), 8s2zs0f (Create CommentsSection and integrate into TaskEditView), 8s2zs0g (Add comment count badge to TaskCardView), 8s2zs0h (Implement MCP add_comment tool), 8s2zs0i (Modify MCP update_task_status for optional comment), 8s2zs0j (Modify MCP query_tasks to include comments), 8s2zs0k (Write MCP comment tests), 8s2zs0l (Create AddCommentIntent), 8s2zs0m (Write AddCommentIntent tests), 8s2zs0n (Wire CommentService in TransitApp and register dependencies)
  - Stream: 1
