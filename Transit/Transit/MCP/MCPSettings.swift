#if os(macOS)
import Foundation

@Observable
final class MCPSettings {

    private static let enabledKey = "mcpServerEnabled"
    private static let portKey = "mcpServerPort"
    private static let maintenanceToolsKey = "mcpMaintenanceToolsEnabled"
    static let defaultPort = 3141

    /// Valid TCP port range. Port 0 means "any available port" to the OS and is
    /// not a usable fixed address for the MCP server, so it is excluded.
    static let validPortRange = 1...65535

    /// Whether a value is a usable TCP port for binding the MCP server.
    static func isValidPort(_ value: Int) -> Bool {
        validPortRange.contains(value)
    }

    var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey) }
    }

    var port: Int {
        didSet { UserDefaults.standard.set(port, forKey: Self.portKey) }
    }

    var maintenanceToolsEnabled: Bool {
        didSet { UserDefaults.standard.set(maintenanceToolsEnabled, forKey: Self.maintenanceToolsKey) }
    }

    init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        let stored = UserDefaults.standard.integer(forKey: Self.portKey)
        self.port = stored > 0 ? stored : Self.defaultPort
        self.maintenanceToolsEnabled = UserDefaults.standard.bool(forKey: Self.maintenanceToolsKey)
    }
}

#endif
