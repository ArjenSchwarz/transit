import AppIntents
import Foundation
import SwiftData
import Testing
@testable import Transit

@Suite(.serialized)
@MainActor
struct ProjectEntityTests {

    // MARK: - Factory Method

    @Test func fromProjectSetsIdAsUUIDString() throws {
        let context = try TestModelContainer.newContext()
        let project = Project(name: "Alpha", description: "Test", gitRepo: nil, colorHex: "#FF0000")
        context.insert(project)
        try context.save()

        let entity = ProjectEntity.from(project)
        #expect(entity.id == project.id.uuidString)
    }

    @Test func fromProjectSetsProjectId() throws {
        let context = try TestModelContainer.newContext()
        let project = Project(name: "Beta", description: "Test", gitRepo: nil, colorHex: "#00FF00")
        context.insert(project)
        try context.save()

        let entity = ProjectEntity.from(project)
        #expect(entity.projectId == project.id)
    }

    @Test func fromProjectSetsName() throws {
        let context = try TestModelContainer.newContext()
        let project = Project(name: "Gamma", description: "Test", gitRepo: nil, colorHex: "#0000FF")
        context.insert(project)
        try context.save()

        let entity = ProjectEntity.from(project)
        #expect(entity.name == "Gamma")
    }

    // MARK: - Display Representation

    @Test func typeDisplayRepresentationIsProject() {
        #expect(ProjectEntity.typeDisplayRepresentation.name == "Project")
    }

    @Test func displayRepresentationShowsName() throws {
        let entity = ProjectEntity(
            id: UUID().uuidString,
            projectId: UUID(),
            name: "My Project"
        )
        let title = String(localized: entity.displayRepresentation.title)
        #expect(title == "My Project")
    }

    // MARK: - Empty Project List

    @Test func queryReturnsEmptyWhenNoProjectsMatchId() throws {
        let context = try TestModelContainer.newContext()
        // Use a random UUID that won't match any project
        let fakeId = UUID().uuidString
        let descriptor = FetchDescriptor<Project>()
        let projects = try context.fetch(descriptor)
        let matching = projects.filter { $0.id.uuidString == fakeId }
        let entities = matching.map(ProjectEntity.from)
        #expect(entities.isEmpty)
    }
}
