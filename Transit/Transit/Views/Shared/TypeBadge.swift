//
//  TypeBadge.swift
//  Transit
//
//  Tinted badge for task type display.
//

import SwiftUI

struct TypeBadge: View {
    let type: TaskType

    private var badgeColor: Color {
        switch type {
        case .bug:
            return .red
        case .feature:
            return .blue
        case .chore:
            return .gray
        case .research:
            return .purple
        case .documentation:
            return .green
        }
    }

    private var label: String {
        switch type {
        case .bug:
            return "Bug"
        case .feature:
            return "Feature"
        case .chore:
            return "Chore"
        case .research:
            return "Research"
        case .documentation:
            return "Docs"
        }
    }

    var body: some View {
        Text(label)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(badgeColor)
            .clipShape(Capsule())
    }
}
