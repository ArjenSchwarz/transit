import SwiftData
import SwiftUI
import Testing
@testable import Transit

@MainActor
struct ProjectServiceTests {
    @Test
    func createProjectPersistsAndNormalizesInputs() throws {
        let container = try makeInMemoryModelContainer()
        let context = ModelContext(container)
        let service = ProjectService(modelContext: context)

        let project = try service.createProject(
            name: "  Transit  ",
            description: "  Main tracker  ",
            gitRepo: "   ",
            color: .blue
        )

        #expect(project.name == "Transit")
        #expect(project.projectDescription == "Main tracker")
        #expect(project.gitRepo == nil)
        #expect(project.colorHex == Color.blue.hexString)
    }

    @Test
    func findProjectSupportsIDAndCaseInsensitiveName() throws {
        let container = try makeInMemoryModelContainer()
        let context = ModelContext(container)
        let service = ProjectService(modelContext: context)

        let project = try service.createProject(name: "Transit", description: "Main", color: .green)

        #expect(try service.findProject(id: project.id).id == project.id)
        #expect(try service.findProject(name: "transit").id == project.id)
        #expect(try service.findProject(name: " TrAnSiT ").id == project.id)
    }

    @Test
    func findProjectReportsAmbiguousAndMissing() throws {
        let container = try makeInMemoryModelContainer()
        let context = ModelContext(container)
        let service = ProjectService(modelContext: context)

        _ = try service.createProject(name: "Transit", description: "Main", color: .red)
        _ = try service.createProject(name: "transit", description: "Duplicate", color: .orange)

        #expect(throws: ProjectService.Error.ambiguousProject) {
            try service.findProject(name: "TRANSIT")
        }

        #expect(throws: ProjectService.Error.projectNotFound) {
            try service.findProject(name: "unknown")
        }

        #expect(throws: ProjectService.Error.missingLookup) {
            try service.findProject()
        }
    }

    @Test
    func activeTaskCountExcludesTerminalStatuses() throws {
        let container = try makeInMemoryModelContainer()
        let context = ModelContext(container)
        let service = ProjectService(modelContext: context)

        let project = try service.createProject(name: "Transit", description: "Main", color: .mint)

        context.insert(TransitTask(name: "Idea", status: .idea, project: project))
        context.insert(TransitTask(name: "Planning", status: .planning, project: project))
        context.insert(TransitTask(name: "Done", status: .done, completionDate: .now, project: project))
        context.insert(TransitTask(name: "Abandoned", status: .abandoned, completionDate: .now, project: project))
        try context.save()

        #expect(try service.activeTaskCount(for: project) == 2)
    }

    @Test
    func projectServiceDoesNotExposeDeleteAPI() throws {
        let container = try makeInMemoryModelContainer()
        let service = ProjectService(modelContext: ModelContext(container))

        #expect(!(service is any ProjectDeletionAPI))
    }
}

private protocol ProjectDeletionAPI {
    func deleteProject(_ project: Project) throws
}
