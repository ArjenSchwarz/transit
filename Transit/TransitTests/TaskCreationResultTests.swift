import Foundation
import Testing
@testable import Transit

@MainActor
@Suite
struct TaskCreationResultTests {
    
    @Test func initializesWithAllProperties() {
        let taskId = UUID()
        let projectId = UUID()
        
        let result = TaskCreationResult(
            taskId: taskId,
            displayId: 42,
            status: "idea",
            projectId: projectId,
            projectName: "Test Project"
        )
        
        #expect(result.taskId == taskId)
        #expect(result.displayId == 42)
        #expect(result.status == "idea")
        #expect(result.projectId == projectId)
        #expect(result.projectName == "Test Project")
    }
    
    @Test func handlesNilDisplayId() {
        let taskId = UUID()
        let projectId = UUID()
        
        let result = TaskCreationResult(
            taskId: taskId,
            displayId: nil,
            status: "idea",
            projectId: projectId,
            projectName: "Test Project"
        )
        
        #expect(result.taskId == taskId)
        #expect(result.displayId == nil)
        #expect(result.status == "idea")
        #expect(result.projectId == projectId)
        #expect(result.projectName == "Test Project")
    }
    
    @Test func handlesEmptyProjectName() {
        let taskId = UUID()
        let projectId = UUID()
        
        let result = TaskCreationResult(
            taskId: taskId,
            displayId: 1,
            status: "idea",
            projectId: projectId,
            projectName: ""
        )
        
        #expect(result.projectName == "")
    }
    
    @Test func handlesProjectNameWithSpecialCharacters() {
        let taskId = UUID()
        let projectId = UUID()
        
        let result = TaskCreationResult(
            taskId: taskId,
            displayId: 1,
            status: "idea",
            projectId: projectId,
            projectName: "Project: Test & Dev (2026)"
        )
        
        #expect(result.projectName == "Project: Test & Dev (2026)")
    }
    
    @Test func handlesProjectNameWithUnicode() {
        let taskId = UUID()
        let projectId = UUID()
        
        let result = TaskCreationResult(
            taskId: taskId,
            displayId: 1,
            status: "idea",
            projectId: projectId,
            projectName: "プロジェクト 🚀"
        )
        
        #expect(result.projectName == "プロジェクト 🚀")
    }
    
    @Test func preservesUUIDIdentity() {
        let taskId = UUID()
        let projectId = UUID()
        
        let result = TaskCreationResult(
            taskId: taskId,
            displayId: 1,
            status: "idea",
            projectId: projectId,
            projectName: "Test"
        )
        
        // Verify UUIDs are preserved exactly
        #expect(result.taskId.uuidString == taskId.uuidString)
        #expect(result.projectId.uuidString == projectId.uuidString)
    }
}
