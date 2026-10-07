import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct TaskConsolidationHistoryTests {
    @Test func defaultSchemaRegistersImmutableScalarHistory() throws {
        let fixture = try TestModelContainer()
        let entity = try #require(fixture.container.schema.entitiesByName["TaskConsolidationEvent"])
        #expect(entity.relationships.isEmpty)
        #expect(entity.uniquenessConstraints.isEmpty)
        #expect(Set(entity.attributes.map(\.name)) == [
            "id", "operationId", "kindRawValue", "createdAt", "originScopeId", "survivorTaskId",
            "candidate1", "candidate2", "candidate3", "candidate4", "candidate5", "payloadJSON"
        ])
        for attribute in entity.attributes {
            #expect(!attribute.isUnique)
            #expect(attribute.isOptional || attribute.defaultValue != nil)
        }
    }
}
