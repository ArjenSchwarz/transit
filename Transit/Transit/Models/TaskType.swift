import Foundation

enum TaskType: String, Codable, CaseIterable {
    case bug
    case feature
    case chore
    case research
    case documentation
}
