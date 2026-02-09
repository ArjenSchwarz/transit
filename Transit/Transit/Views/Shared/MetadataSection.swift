//
//  MetadataSection.swift
//  Transit
//
//  Key-value display and edit for task metadata.
//

import SwiftUI

struct MetadataSection: View {
    @Binding var metadata: [String: String]
    let isEditing: Bool

    @State private var newKey = ""
    @State private var newValue = ""

    var body: some View {
        Section("Metadata") {
            if metadata.isEmpty && !isEditing {
                Text("No metadata")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(metadata.keys.sorted()), id: \.self) { key in
                    if isEditing {
                        HStack {
                            Text(key)
                                .foregroundStyle(.secondary)
                            Spacer()
                            TextField("Value", text: Binding(
                                get: { metadata[key] ?? "" },
                                set: { metadata[key] = $0 }
                            ))
                            .multilineTextAlignment(.trailing)
                            Button(role: .destructive) {
                                metadata.removeValue(forKey: key)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        HStack {
                            Text(key)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(metadata[key] ?? "")
                        }
                    }
                }

                if isEditing {
                    HStack {
                        TextField("Key", text: $newKey)
                        TextField("Value", text: $newValue)
                        Button {
                            guard !newKey.isEmpty else { return }
                            metadata[newKey] = newValue
                            newKey = ""
                            newValue = ""
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(.green)
                        }
                        .buttonStyle(.plain)
                        .disabled(newKey.isEmpty)
                    }
                }
            }
        }
    }
}
