import SwiftUI

enum TaskType: String, Codable, CaseIterable {
    case bug
    case feature
    case chore
    case research
    case documentation

    var tintColor: Color {
        switch self {
        case .bug: .red
        case .feature: .blue
        case .chore: .orange
        case .research: .purple
        case .documentation: .green
        }
    }
}
