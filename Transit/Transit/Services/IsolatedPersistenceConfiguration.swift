import Foundation
import SwiftData

enum IsolatedPersistenceConfiguration {
    enum Failure: Error { case productionModeNotAllowed, invalidCloudContainer }
    static func make(
        mode: AppPersistencePolicy.Mode,
        schema: Schema,
        applicationSupportDirectory: URL = .applicationSupportDirectory,
        cloudKitContainerID: String? = nil
    ) throws -> ModelConfiguration {
        guard mode != .production else { throw Failure.productionModeNotAllowed }
        if let cloudKitContainerID {
            guard mode == .development && cloudKitContainerID == mode.cloudKitContainerID else {
                throw Failure.invalidCloudContainer
            }
        }
        if mode.usesMemoryStore {
            return ModelConfiguration(schema: schema, isStoredInMemoryOnly: true,
                                      groupContainer: .none, cloudKitDatabase: .none)
        }
        let directory = applicationSupportDirectory.appendingPathComponent("TransitDevelopment", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return ModelConfiguration("TransitDevelopment", schema: schema,
                                  url: directory.appendingPathComponent("development.store"),
                                  cloudKitDatabase: cloudKitContainerID.map { .private($0) } ?? .none)
    }
}
