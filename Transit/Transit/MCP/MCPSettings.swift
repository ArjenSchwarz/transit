#if os(macOS)
import Foundation

@Observable
final class MCPSettings {

    private static let enabledKey = "mcpServerEnabled"
    private static let portKey = "mcpServerPort"
    static let defaultPort = 3141

    var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey) }
    }

    var port: Int {
        didSet { UserDefaults.standard.set(port, forKey: Self.portKey) }
    }

    init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        let stored = UserDefaults.standard.integer(forKey: Self.portKey)
        self.port = stored > 0 ? stored : Self.defaultPort
    }
}

#endif
