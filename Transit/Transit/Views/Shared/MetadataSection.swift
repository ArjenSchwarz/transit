import SwiftUI

struct MetadataSection: View {
    @Binding var metadata: [String: String]
    let isEditing: Bool

    var body: some View {
        #if os(macOS)
        metadataContent
        #else
        Section("Metadata") {
            metadataContent
        }
        #endif
    }

    @ViewBuilder
    private var metadataContent: some View {
        if metadata.isEmpty && !isEditing {
            Text("No metadata")
                .foregroundStyle(.secondary)
        }
        ForEach(metadata.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
            if isEditing {
                HStack {
                    Text(key)
                        .foregroundStyle(.secondary)
                    Spacer()
                    TextField("Value", text: binding(for: key))
                    Button(role: .destructive) {
                        metadata.removeValue(forKey: key)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.red)
                    }
                }
            } else {
                LabeledContent(key, value: value)
            }
        }
        if isEditing {
            AddMetadataRow(metadata: $metadata)
        }
    }

    private func binding(for key: String) -> Binding<String> {
        Binding(
            get: { metadata[key] ?? "" },
            set: { metadata[key] = $0 }
        )
    }
}

private struct AddMetadataRow: View {
    @Binding var metadata: [String: String]
    @State private var newKey = ""
    @State private var newValue = ""

    var body: some View {
        HStack {
            TextField("Key", text: $newKey)
                .textContentType(nil)
            TextField("Value", text: $newValue)
                .textContentType(nil)
            Button {
                let trimmedKey = newKey.trimmingCharacters(in: .whitespaces)
                guard !trimmedKey.isEmpty else { return }
                metadata[trimmedKey] = newValue
                newKey = ""
                newValue = ""
            } label: {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(.green)
            }
            .disabled(newKey.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }
}
