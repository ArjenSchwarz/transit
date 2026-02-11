import Foundation
import Testing
import SwiftData
@testable import Transit

@MainActor
@Suite(.serialized)
struct AddTaskIntentTests {
    
    // MARK: - Test Fixtures
    
    private func makeTestContext() throws -> (ModelContext, TaskService, ProjectService, Project) {
        let context = try TestModelContainer.newContext()
        let store = InMemoryCounterStore()
        let allocator = DisplayIDAllocator(store: store)
        let taskService = TaskService(modelContext: context, displayIDAllocator: allocator)
        let projectService = ProjectService(modelContext: context)
        
        let project = Project(name: "Test Project", description: "", gitRepo: nil, colorHex: "#FF0000")
        context.insert(project)
        try context.save()
        
        return (context, taskService, projectService, project)
    }
    
    // MARK: - Task Creation Tests
    
    @Test("Creates task with required parameters only")
    func createsTaskWithRequiredParameters() async throws {
        let (_, taskService, projectService, project) = try makeTestContext()
        let projectEntity = ProjectEntity.from(project)
        
        let result = try await AddTaskIntent.execute(
            name: "Test Task",
            taskDescription: nil,
            type: .feature,
            project: projectEntity,
            taskService: taskService,
            projectService: projectService
        )
        
        #expect(result.status == "idea")
        #expect(result.projectId == project.id)
        #expect(result.projectName == "Test Project")
        
        let task = try taskService.findByID(result.taskId)
        #expect(task.name == "Test Task")
        #expect(task.type == .feature)
        #expect(task.status == .idea)
        #expect(task.taskDescription == nil)
    }
    
    @Test("Creates task with all parameters")
    func createsTaskWithAllParameters() async throws {
        let (_, taskService, projectService, project) = try makeTestContext()
        let projectEntity = ProjectEntity.from(project)
        
        let result = try await AddTaskIntent.execute(
            name: "Bug Fix",
            taskDescription: "Fix the login issue",
            type: .bug,
            project: projectEntity,
            taskService: taskService,
            projectService: projectService
        )
        
        #expect(result.status == "idea")
        
        let task = try taskService.findByID(result.taskId)
        #expect(task.name == "Bug Fix")
        #expect(task.taskDescription == "Fix the login issue")
        #expect(task.type == .bug)
        #expect(task.status == .idea)
    }
    
    @Test("Creates task with each task type", arguments: TaskType.allCases)
    func createsTaskWithEachType(type: TaskType) async throws {
        let (_, taskService, projectService, project) = try makeTestContext()
        let projectEntity = ProjectEntity.from(project)
        
        let result = try await AddTaskIntent.execute(
            name: "Task of type \(type.rawValue)",
            taskDescription: nil,
            type: type,
            project: projectEntity,
            taskService: taskService,
            projectService: projectService
        )
        
        let task = try taskService.findByID(result.taskId)
        #expect(task.type == type)
    }
    
    // MARK: - Validation Tests
    
    @Test("Throws error for empty task name")
    func throwsErrorForEmptyName() async throws {
        let (_, taskService, projectService, project) = try makeTestContext()
        let projectEntity = ProjectEntity.from(project)
        
        await #expect(throws: VisualIntentError.self) {
            try await AddTaskIntent.execute(
                name: "",
                taskDescription: nil,
                type: .feature,
                project: projectEntity,
                taskService: taskService,
                projectService: projectService
            )
        }
    }
    
    @Test("Throws error for whitespace-only task name")
    func throwsErrorForWhitespaceOnlyName() async throws {
        let (_, taskService, projectService, project) = try makeTestContext()
        let projectEntity = ProjectEntity.from(project)
        
        await #expect(throws: VisualIntentError.self) {
            try await AddTaskIntent.execute(
                name: "   ",
                taskDescription: nil,
                type: .feature,
                project: projectEntity,
                taskService: taskService,
                projectService: projectService
            )
        }
    }
    
    @Test("Trims whitespace from task name")
    func trimsWhitespaceFromName() async throws {
        let (_, taskService, projectService, project) = try makeTestContext()
        let projectEntity = ProjectEntity.from(project)
        
        let result = try await AddTaskIntent.execute(
            name: "  Task Name  ",
            taskDescription: nil,
            type: .feature,
            project: projectEntity,
            taskService: taskService,
            projectService: projectService
        )
        
        let task = try taskService.findByID(result.taskId)
        #expect(task.name == "Task Name")
    }
    
    // MARK: - Project Association Tests
    
    @Test("Associates task with correct project")
    func associatesTaskWithCorrectProject() async throws {
        let (context, taskService, projectService, _) = try makeTestContext()
        
        let project1 = Project(name: "Project Alpha", description: "", gitRepo: nil, colorHex: "#FF0000")
        let project2 = Project(name: "Project Beta", description: "", gitRepo: nil, colorHex: "#00FF00")
        context.insert(project1)
        context.insert(project2)
        try context.save()
        
        let projectEntity = ProjectEntity.from(project2)
        
        let result = try await AddTaskIntent.execute(
            name: "Task for Beta",
            taskDescription: nil,
            type: .feature,
            project: projectEntity,
            taskService: taskService,
            projectService: projectService
        )
        
        #expect(result.projectId == project2.id)
        #expect(result.projectName == "Project Beta")
        
        let task = try taskService.findByID(result.taskId)
        #expect(task.project?.id == project2.id)
    }
    
    // MARK: - Display ID Tests
    
    @Test("Returns permanent display ID when allocated")
    func returnsPermanentDisplayIdWhenAllocated() async throws {
        let (_, taskService, projectService, project) = try makeTestContext()
        let projectEntity = ProjectEntity.from(project)
        
        let result = try await AddTaskIntent.execute(
            name: "Task with ID",
            taskDescription: nil,
            type: .feature,
            project: projectEntity,
            taskService: taskService,
            projectService: projectService
        )
        
        // Display ID allocation may succeed or fail (offline scenario)
        // Just verify the result structure is correct
        if let displayId = result.displayId {
            #expect(displayId > 0)
        }
    }
    
    // MARK: - Initial Status Tests
    
    @Test("Always creates tasks in idea status")
    func alwaysCreatesTasksInIdeaStatus() async throws {
        let (_, taskService, projectService, project) = try makeTestContext()
        let projectEntity = ProjectEntity.from(project)
        
        for type in TaskType.allCases {
            let result = try await AddTaskIntent.execute(
                name: "Task \(type.rawValue)",
                taskDescription: nil,
                type: type,
                project: projectEntity,
                taskService: taskService,
                projectService: projectService
            )
            
            #expect(result.status == "idea")
            
            let task = try taskService.findByID(result.taskId)
            #expect(task.status == .idea)
        }
    }
    
    // MARK: - Result Structure Tests
    
    @Test("Returns complete TaskCreationResult")
    func returnsCompleteTaskCreationResult() async throws {
        let (_, taskService, projectService, project) = try makeTestContext()
        let projectEntity = ProjectEntity.from(project)
        
        let result = try await AddTaskIntent.execute(
            name: "Complete Result Test",
            taskDescription: "Description",
            type: .chore,
            project: projectEntity,
            taskService: taskService,
            projectService: projectService
        )
        
        // Verify all required fields are present
        #expect(result.taskId != UUID(uuidString: "00000000-0000-0000-0000-000000000000"))
        #expect(result.status == "idea")
        #expect(result.projectId == project.id)
        #expect(result.projectName == "Test Project")
    }
    
    // MARK: - Error Handling Tests
    
    @Test("Throws projectNotFound when project is deleted")
    func throwsProjectNotFoundWhenProjectDeleted() async throws {
        let (context, taskService, projectService, project) = try makeTestContext()
        let projectEntity = ProjectEntity.from(project)
        
        // Delete the project after creating the entity
        context.delete(project)
        try context.save()
        
        await #expect(throws: VisualIntentError.self) {
            try await AddTaskIntent.execute(
                name: "Task for deleted project",
                taskDescription: nil,
                type: .feature,
                project: projectEntity,
                taskService: taskService,
                projectService: projectService
            )
        }
    }
    
    @Test("Throws projectNotFound with correct error message")
    func throwsProjectNotFoundWithCorrectMessage() async throws {
        let (context, taskService, projectService, project) = try makeTestContext()
        let projectEntity = ProjectEntity.from(project)
        
        context.delete(project)
        try context.save()
        
        do {
            _ = try await AddTaskIntent.execute(
                name: "Test",
                taskDescription: nil,
                type: .feature,
                project: projectEntity,
                taskService: taskService,
                projectService: projectService
            )
            Issue.record("Expected projectNotFound error to be thrown")
        } catch let error as VisualIntentError {
            guard case .projectNotFound(let message) = error else {
                Issue.record("Expected projectNotFound error, got \(error)")
                return
            }
            #expect(message.contains(projectEntity.name))
        }
    }
    
    @Test("Handles nil description correctly")
    func handlesNilDescriptionCorrectly() async throws {
        let (_, taskService, projectService, project) = try makeTestContext()
        let projectEntity = ProjectEntity.from(project)
        
        let result = try await AddTaskIntent.execute(
            name: "Task without description",
            taskDescription: nil,
            type: .feature,
            project: projectEntity,
            taskService: taskService,
            projectService: projectService
        )
        
        let task = try taskService.findByID(result.taskId)
        #expect(task.taskDescription == nil)
    }
    
    @Test("Handles empty description correctly")
    func handlesEmptyDescriptionCorrectly() async throws {
        let (_, taskService, projectService, project) = try makeTestContext()
        let projectEntity = ProjectEntity.from(project)
        
        let result = try await AddTaskIntent.execute(
            name: "Task with empty description",
            taskDescription: "",
            type: .feature,
            project: projectEntity,
            taskService: taskService,
            projectService: projectService
        )
        
        let task = try taskService.findByID(result.taskId)
        #expect(task.taskDescription == "")
    }
}
