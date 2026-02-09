//
//  EmptyStateView.swift
//  Transit
//
//  Reusable empty state messaging component.
//

import SwiftUI

struct EmptyStateView: View {
    let message: String

    var body: some View {
        Text(message)
            .foregroundStyle(.secondary)
            .font(.body)
            .multilineTextAlignment(.center)
            .padding()
    }
}
