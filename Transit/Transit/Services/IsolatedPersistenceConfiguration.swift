import Foundation
import SwiftData

enum IsolatedPersistenceConfiguration {
    enum Failure: Error { case productionModeNotAllowed }
    static func make(
        mode: AppPersistencePolicy.Mode,
        schema: Schema,
        applicationSupportDirectory: URL = .applicationSupportDirectory
    ) throws -> ModelConfiguration {
        guard mode != .production else { throw Failure.productionModeNotAllowed }
        if mode.usesMemoryStore {
            return ModelConfiguration(schema: schema, isStoredInMemoryOnly: true,
                                      groupContainer: .none, cloudKitDatabase: .none)
        }
        let directory = applicationSupportDirectory.appendingPathComponent("TransitDevelopment", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return ModelConfiguration("TransitDevelopment", schema: schema,
                                  url: directory.appendingPathComponent("development.store"),
                                  cloudKitDatabase: .none)
    }
}
