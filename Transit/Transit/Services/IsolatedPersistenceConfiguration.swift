import Foundation
import SwiftData

enum IsolatedPersistenceConfiguration {
    enum Failure: Error { case invalidCloudContainer }
    static func make(
        mode: AppPersistencePolicy.Mode,
        schema: Schema,
        applicationSupportDirectory: URL = .applicationSupportDirectory,
        cloudKitContainerID: String? = nil
    ) throws -> ModelConfiguration {
        if let cloudKitContainerID {
            guard mode.permitsCloudSync && cloudKitContainerID == mode.cloudKitContainerID else {
                throw Failure.invalidCloudContainer
            }
        }
        guard let url = PersistenceStoreLocation.storeURL(
            for: mode, applicationSupportDirectory: applicationSupportDirectory
        ) else {
            return ModelConfiguration(schema: schema, isStoredInMemoryOnly: true,
                                      groupContainer: .none, cloudKitDatabase: .none)
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return ModelConfiguration(mode == .production ? "TransitAppsRelease" : "TransitAppsDevelopment", schema: schema,
                                  url: url,
                                  cloudKitDatabase: cloudKitContainerID.map { .private($0) } ?? .none)
    }
}
