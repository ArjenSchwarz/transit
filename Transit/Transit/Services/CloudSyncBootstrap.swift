/// Derives the CloudKit mode for services that depend on the live `ModelContainer`.
///
/// A requested CloudKit configuration only becomes active when `ContainerFactory`
/// successfully opens it. Its in-memory fallback is always CloudKit-free, regardless
/// of the launch preference, so direct CloudKit clients must remain inactive.
enum CloudSyncBootstrap {

    static func effectiveActiveCloudSync(
        requestedCloudSyncActive: Bool,
        containerOutcome: ContainerFactory.ContainerOutcome
    ) -> Bool {
        requestedCloudSyncActive && containerOutcome.error == nil
    }
}
