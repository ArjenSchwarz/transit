#if os(macOS)
import Foundation

/// macOS Settings sidebar categories. Each category maps to a detail panel
/// rendered by `SettingsView.settingsDetailContent`.
enum SettingsCategory: String, CaseIterable, Identifiable {
    case general, projects, mcpServer, dataMaintenance, backups, acknowledgments
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .projects: "Projects"
        case .mcpServer: "MCP Server"
        case .dataMaintenance: "Data Maintenance"
        case .backups: "Backups"
        case .acknowledgments: "Acknowledgments"
        }
    }

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .projects: "folder"
        case .mcpServer: "network"
        case .dataMaintenance: "wrench.and.screwdriver"
        case .backups: "externaldrive"
        case .acknowledgments: "heart.text.square"
        }
    }
}
#endif
