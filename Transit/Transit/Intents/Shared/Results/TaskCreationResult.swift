import Foundation

/// Result type returned by AddTaskIntent after successful task creation.
/// Contains all essential task information for Shortcuts automation.
/// [req 2.10, 4.8, 4.9]
struct TaskCreationResult: Codable, Sendable {
    /// The unique identifier of the created task
    let taskId: UUID
    
    /// The permanent display ID (T-42), or nil if only provisional ID was allocated
    let displayId: Int?
    
    /// The task status (always "idea" for newly created tasks)
    let status: String
    
    /// The unique identifier of the project the task belongs to
    let projectId: UUID
    
    /// The name of the project the task belongs to
    let projectName: String
}
