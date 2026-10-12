import Foundation
import Observation
import SwiftData

/// Installed app hooks never run for scratch or independently constructed synthetic stores.
@MainActor @Observable
final class DatabaseMaintenanceGate {
    static let shared = DatabaseMaintenanceGate()
    private var installedContainer: ObjectIdentifier?
    private var prepare: (() throws -> [String])?
    private var cancel: (() throws -> Void)?
    private var authorize: (() throws -> Void)?
    private var finish: (() throws -> Void)?
    private(set) var requiresRestart = false
    private(set) var replacementCommitted = false
    private(set) var recoveryBackupURL: URL?

    func install(
        container: ModelContainer, prepare: @escaping () throws -> [String],
        authorize: @escaping () throws -> Void = {}, cancel: @escaping () throws -> Void = {},
        finish: @escaping () throws -> Void
    ) {
        installedContainer = ObjectIdentifier(container)
        self.prepare = prepare
        self.cancel = cancel
        self.authorize = authorize
        self.finish = finish
    }

    func reservationSnapshot(for container: ModelContainer) throws -> [String]? {
        guard installedContainer == ObjectIdentifier(container) else { return nil }
        guard !requiresRestart else { throw DatabaseBackupError.unavailable }
        return try prepare?()
    }

    func authorizeReplacement(of container: ModelContainer) throws {
        guard installedContainer == ObjectIdentifier(container) else { return }
        try authorize?()
    }

    func cancelReplacement(of container: ModelContainer) throws {
        guard installedContainer == ObjectIdentifier(container) else { return }
        try cancel?()
    }

    func requireMutationAvailable(in container: ModelContainer) throws {
        guard installedContainer != ObjectIdentifier(container) || !requiresRestart else {
            throw DatabaseBackupError.unavailable
        }
    }

    func didReplace(_ container: ModelContainer, availability: PersistenceAvailability,
                    recoveryBackupURL: URL? = nil, committed: Bool = true) throws {
        guard installedContainer == ObjectIdentifier(container) else { return }
        container.mainContext.autosaveEnabled = false
        requiresRestart = true
        replacementCommitted = committed
        self.recoveryBackupURL = recoveryBackupURL
        availability.requireRestartAfterReplacement()
        try finish?()
    }
}
