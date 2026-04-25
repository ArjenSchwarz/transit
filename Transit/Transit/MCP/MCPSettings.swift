#if os(macOS)
import Foundation

@Observable
final class MCPSettings {

    private static let enabledKey = "mcpServerEnabled"
    private static let portKey = "mcpServerPort"
    private static let maintenanceToolsKey = "mcpMaintenanceToolsEnabled"
    static let defaultPort = 3141

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
