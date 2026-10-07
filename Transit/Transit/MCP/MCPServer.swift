#if os(macOS)
import Foundation
import Hummingbird
import NIOCore
import NIOFoundationCompat
import ServiceLifecycle

@MainActor @Observable
final class MCPServer {

    private enum DesiredState: Equatable {
        case stopped
        case invalidPort(Int)
        case running(port: Int, runID: Int)
    }

    private struct ActiveServer {
        let port: Int
        let runID: Int
        let serviceGroup: ServiceGroup
        let task: Task<Void, Never>
    }

    private let toolHandler: MCPToolHandler
    nonisolated let readCoordinator: MCPReadCoordinator
    var listenerGeneration: Int { serverGeneration }
    private var desiredState: DesiredState = .stopped
    private var lifecycleTask: Task<Void, Never>?
    private var activeServer: ActiveServer?
    private var nextRunID = 0
    private var serverGeneration = 0
    private var listenerScope: UUID?
    var isRunning: Bool { activeServer != nil }
    var activePort: Int? { activeServer?.port }

    /// A human-readable reason the server is not running, or `nil` when the
    /// server is running or was stopped intentionally. Set when the configured
    /// port is invalid or when binding the listening socket fails (e.g. the
    /// port is already in use), so Settings can surface an actionable message
    /// instead of a bare "Stopped".
    private(set) var startError: String?

    init(toolHandler: MCPToolHandler, readCoordinator: MCPReadCoordinator? = nil) {
        self.toolHandler = toolHandler
        self.readCoordinator = readCoordinator ?? toolHandler.readCoordinator
        precondition(self.readCoordinator === toolHandler.readCoordinator)
    }
}

extension MCPServer {
    /// Starts the server unless the same port is already active or requested.
    /// Repeated requests join one reconciliation pass instead of launching
    /// competing Hummingbird applications.
    func start(port: Int) async {
        await request(runningState(port: port, forceRestart: false))
    }

    /// Replaces the current listener even when the port is unchanged. The old
    /// service group shuts down gracefully before the replacement can bind.
    func restart(port: Int) async {
        await request(runningState(port: port, forceRestart: true))
    }

    /// Stops the server and returns only after Hummingbird has gracefully
    /// released its listener. A newer request can supersede this one meanwhile.
    func stop() async {
        await request(.stopped)
    }

    private func runningState(port: Int, forceRestart: Bool) -> DesiredState {
        guard MCPSettings.isValidPort(port) else {
            return .invalidPort(port)
        }

        if !forceRestart {
            if case .running(let requestedPort, let runID) = desiredState,
               requestedPort == port {
                return .running(port: port, runID: runID)
            }
            if let activeServer, activeServer.port == port {
                return .running(port: port, runID: activeServer.runID)
            }
        }

        nextRunID += 1
        return .running(port: port, runID: nextRunID)
    }

    private func request(_ state: DesiredState) async {
        desiredState = state
        if lifecycleTask == nil {
            lifecycleTask = Task { @MainActor [weak self] in
                await self?.reconcileLifecycle()
            }
        }
        let currentLifecycleTask = lifecycleTask
        await currentLifecycleTask?.value
    }

    /// Applies only the latest requested state. Requests arriving while old
    /// listener teardown is suspended overwrite stale intermediate states and
    /// are picked up by the next loop iteration.
    private func reconcileLifecycle() async {
        while true {
            let target = desiredState
            switch target {
            case .stopped:
                await tearDownCurrentServer()
                if desiredState == target {
                    startError = nil
                }

            case .invalidPort(let port):
                await tearDownCurrentServer()
                if desiredState == target {
                    startError = "Port \(port) is invalid. Use a value between "
                        + "\(MCPSettings.validPortRange.lowerBound) and "
                        + "\(MCPSettings.validPortRange.upperBound)."
                }

            case .running(let port, let runID):
                if activeServer?.port != port || activeServer?.runID != runID {
                    await tearDownCurrentServer()
                    if desiredState == target {
                        launchServer(port: port, runID: runID)
                    }
                }
            }

            guard desiredState == target else { continue }
            lifecycleTask = nil
            return
        }
    }

    private func tearDownCurrentServer() async {
        if let listenerScope { readCoordinator.stopListener(listenerScope) }
        listenerScope = nil
        toolHandler.setTaskQueryAdmission(open: false)
        toolHandler.finishToolListChangeSessions()
        guard let currentServer = activeServer else { return }

        // Task cancellation only cancels ServiceGroup's child tasks; it does
        // not invoke Hummingbird Server.shutdownGracefully(), so task completion
        // is not a listener-release fence. Trigger the group's graceful path,
        // then await its run task before permitting a replacement bind. The
        // generation bump must precede the trigger: if the detached task has
        // not reached `run()` yet, the group jumps to `.finished` and `run()`
        // throws `alreadyFinished`, which the fenced callback must not report
        // as a start failure for a server the caller just asked to stop.
        serverGeneration += 1
        activeServer = nil
        await currentServer.serviceGroup.triggerGracefulShutdown()
        await currentServer.task.value
    }

    /// Ignore completion from a listener replaced by a newer generation.
    func listenerDidExit(generation: Int, failure: String?) {
        guard serverGeneration == generation else { return }
        if let listenerScope { readCoordinator.stopListener(listenerScope) }
        listenerScope = nil
        toolHandler.setTaskQueryAdmission(open: false)
        activeServer = nil
        toolHandler.finishToolListChangeSessions()
        if let failure { startError = failure }
    }

    private func launchServer(port: Int, runID: Int) {
        serverGeneration += 1
        let currentGeneration = serverGeneration
        startError = nil

        toolHandler.openToolListSubscriptions()
        toolHandler.setTaskQueryAdmission(open: true)
        let scope = UUID()
        listenerScope = scope
        readCoordinator.startListener(scope)
        let handler = toolHandler
        let setNotRunning = { @MainActor [weak self] (failure: String?) in
            self?.listenerDidExit(generation: currentGeneration, failure: failure)
        }
        let app = Application(
            router: Self.makeRouter(handler: handler, readCoordinator: readCoordinator,
                admissionOwner: .listener(scope)),
            configuration: .init(
                address: .hostname("127.0.0.1", port: port)
            )
        )
        // No unix signal traps (`runService()` would install SIGTERM/SIGINT by
        // default): they change the process's signal disposition permanently,
        // and teardown here is driven by `triggerGracefulShutdown()`.
        let configuration = MCPServerLifecycleConfiguration.make(
            services: [app],
            logger: app.logger
        )
        let serviceGroup = ServiceGroup(configuration: configuration)
        let task = Task.detached {
            var failure: String?
            do {
                try await serviceGroup.run()
            } catch {
                failure = "Could not start server on port \(port): "
                    + error.localizedDescription
            }
            await setNotRunning(failure)
        }
        activeServer = ActiveServer(
            port: port,
            runID: runID,
            serviceGroup: serviceGroup,
            task: task
        )
    }
}
#endif
