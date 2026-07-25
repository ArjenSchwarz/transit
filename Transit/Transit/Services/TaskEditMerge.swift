import Foundation

/// A field of a task that `TaskEditView` can edit.
///
/// Declaration order is the order fields are listed to the user when they
/// conflict, so keep it aligned with the form layout.
nonisolated enum TaskEditField: EditableField {
    case name
    case description
    case type
    case priority
    case status
    case project
    case milestone
    case metadata

    /// Human-facing label used when telling the user which fields conflict.
    var displayName: String {
        switch self {
        case .name: "Name"
        case .description: "Description"
        case .type: "Type"
        case .priority: "Priority"
        case .status: "Status"
        case .project: "Project"
        case .milestone: "Milestone"
        case .metadata: "Metadata"
        }
    }
}

// MARK: - Snapshot

/// A value copy of every field `TaskEditView` can edit.
///
/// Taken three times per save: once when the editor loads (the baseline), once
/// from the form's `@State` (what the user is submitting), and once from the
/// task itself at save time (what is stored right now).
nonisolated struct TaskEditSnapshot: EditSnapshot {
    var name: String
    var description: String
    var type: TaskType
    var priority: TaskPriority
    var status: TaskStatus
    var projectID: UUID?
    var milestoneID: UUID?
    var metadata: [String: String]

    /// Reads the task's stored values.
    init(task: TransitTask) {
        self.init(
            name: task.name,
            description: task.taskDescription ?? "",
            type: task.type,
            priority: task.priority,
            status: task.status,
            projectID: task.project?.id,
            milestoneID: task.milestone?.id,
            metadata: task.metadata
        )
    }

    /// Strings are normalised the way the form normalises its input, so loading
    /// a task and saving it again without typing reports no change even when the
    /// stored value carries whitespace the form would have trimmed.
    init(
        name: String,
        description: String,
        type: TaskType,
        priority: TaskPriority,
        status: TaskStatus,
        projectID: UUID?,
        milestoneID: UUID?,
        metadata: [String: String]
    ) {
        self.name = name.trimmedForFormInput()
        self.description = description.trimmedForFormInput()
        self.type = type
        self.priority = priority
        self.status = status
        self.projectID = projectID
        self.milestoneID = milestoneID
        self.metadata = metadata
    }

    /// Whether this snapshot and `other` hold different values for `field`.
    func differs(from other: TaskEditSnapshot, in field: TaskEditField) -> Bool {
        switch field {
        case .name: name != other.name
        case .description: description != other.description
        case .type: type != other.type
        case .priority: priority != other.priority
        case .status: status != other.status
        case .project: projectID != other.projectID
        case .milestone: milestoneID != other.milestoneID
        case .metadata: metadata != other.metadata
        }
    }
}

// MARK: - Merge

/// Three-way comparison deciding what a task-editor save should write.
///
/// The comparison itself lives in `EditMerge`, shared with the project and
/// milestone editors so all three resolve concurrent writes identically
/// (T-1817).
typealias TaskEditMerge = EditMerge<TaskEditSnapshot>

// MARK: - Applier

/// Writes the fields a `TaskEditMerge` marks as changed, routing every mutation
/// through the services so validation and status side effects still run.
///
/// Nothing is persisted here — every call passes `save: false` so the caller can
/// commit the whole edit with a single `modelContext.save()` and roll it back as
/// a unit on failure.
struct TaskEditApplier {
    let taskService: TaskService
    let milestoneService: MilestoneService

    func apply(
        _ merge: TaskEditMerge,
        edited: TaskEditSnapshot,
        to task: TransitTask,
        project: Project?,
        milestone: Milestone?
    ) throws {
        // Moving project clears the milestone (Decision 6), so it goes first.
        if merge.changed(.project), let project, task.project?.id != project.id {
            try taskService.changeProject(task: task, to: project, save: false)
        }

        // Unchanged fields are passed as nil, which `updateTask` reads as
        // "leave this alone" — that is what keeps a concurrent writer's value.
        let descriptionChanged = merge.changed(.description)
        try taskService.updateTask(
            task,
            name: merge.changed(.name) ? edited.name : nil,
            description: descriptionChanged && !edited.description.isEmpty ? edited.description : nil,
            // Disambiguates "user emptied the field" from "no change requested"
            // so an existing description can still be removed (T-854).
            clearDescription: descriptionChanged && edited.description.isEmpty,
            type: merge.changed(.type) ? edited.type : nil,
            metadata: merge.changed(.metadata) ? edited.metadata : nil,
            priority: merge.changed(.priority) ? edited.priority : nil,
            save: false
        )

        if merge.changed(.milestone) {
            try milestoneService.setMilestone(milestone, on: task, save: false)
        }

        if merge.changed(.status), edited.status != task.status {
            try taskService.updateStatus(task: task, to: edited.status, save: false)
        }
    }
}
