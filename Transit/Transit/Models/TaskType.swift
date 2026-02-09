//
//  TaskType.swift
//  Transit
//
//  Hardcoded task types for categorization.
//

import Foundation

/// Task type for categorization (bug, feature, chore, research, documentation).
enum TaskType: String, Codable, CaseIterable, Sendable {
    case bug
    case feature
    case chore
    case research
    case documentation
}
