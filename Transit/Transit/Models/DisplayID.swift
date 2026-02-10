import Foundation

enum DisplayID: Codable, Equatable {
    case permanent(Int)
    case provisional

    nonisolated var formatted: String {
        switch self {
        case .permanent(let value):
            return "T-\(value)"
        case .provisional:
            return "T-\u{2022}"
        }
    }
}
