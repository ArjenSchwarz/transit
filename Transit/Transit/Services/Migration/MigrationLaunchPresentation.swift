import Foundation

/// Presentation only: verification and the ordinary-write gate remain owned by the existing preflight/bootstrap.
nonisolated enum MigrationLaunchPresentation: Equatable, Sendable {
    case checking, ready, needsSetup, failed(String)

    var showsSetup: Bool {
        switch self {
        case .checking, .ready: false
        case .needsSetup, .failed: true
        }
    }

    var message: String {
        switch self {
        case .checking, .ready: ""
        case .needsSetup: "No saved readiness. Inspect the destination and choose verified next-ID floors."
        case .failed(let message): message
        }
    }

    @MainActor static func verify(_ preflight: MigrationCounterPreflight) async -> Self {
        do { return try await preflight.verifySaved() ? .ready : .needsSetup } catch {
            return .failed(error.localizedDescription)
        }
    }
}
