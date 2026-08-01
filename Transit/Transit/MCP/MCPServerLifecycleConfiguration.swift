#if os(macOS)
import Logging
import ServiceLifecycle

/// Service Lifecycle policy for the embedded server. Keeping this separate from
/// `MCPServer` makes the timeout and no-signal contract directly testable.
nonisolated enum MCPServerLifecycleConfiguration {
    static let defaultMaximumGracefulShutdown: Duration = .seconds(5)

    static func make(
        services: [any Service],
        logger: Logger,
        maximumGracefulShutdown: Duration = defaultMaximumGracefulShutdown
    ) -> ServiceGroupConfiguration {
        var configuration = ServiceGroupConfiguration(
            services: services,
            logger: logger
        )
        configuration.maximumGracefulShutdownDuration = maximumGracefulShutdown
        return configuration
    }
}

#endif
