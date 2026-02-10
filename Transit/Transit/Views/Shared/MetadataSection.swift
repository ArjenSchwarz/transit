import Foundation
import SwiftUI

struct MetadataEntry: Identifiable, Equatable {
    let id: UUID
    var key: String
    var value: String
}

enum MetadataDraft {
    static func makeEntries(from metadata: [String: String]?) -> [MetadataEntry] {
        guard let metadata, !metadata.isEmpty else {
            return []
        }

        var entries: [MetadataEntry] = []
        entries.reserveCapacity(metadata.count)

        for (key, value) in metadata {
            entries.append(MetadataEntry(id: UUID(), key: key, value: value))
        }

        entries.sort { lhs, rhs in
            lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending
        }

        return entries
    }

    static func materialize(entries: [MetadataEntry]) -> [String: String]? {
        guard !entries.isEmpty else {
            return nil
        }

        var metadata: [String: String] = [:]
        metadata.reserveCapacity(entries.count)

        for entry in entries {
            let key = entry.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else {
                continue
            }

            let value = entry.value.trimmingCharacters(in: .whitespacesAndNewlines)
            metadata[key] = value
        }

        return metadata.isEmpty ? nil : metadata
    }
}

struct MetadataSection: View {
    private let title: String
    private let isEditable: Bool
    private let onChange: (([String: String]?) -> Void)?
    private let readOnlyEntries: [MetadataEntry]

    @State private var editableEntries: [MetadataEntry]

    init(title: String = "Metadata", metadata: [String: String]?) {
        let entries = MetadataDraft.makeEntries(from: metadata)
        self.title = title
        self.isEditable = false
        self.onChange = nil
        self.readOnlyEntries = entries
        _editableEntries = State(initialValue: entries)
    }

    init(title: String = "Metadata", metadata: Binding<[String: String]?>) {
        let entries = MetadataDraft.makeEntries(from: metadata.wrappedValue)
        self.title = title
        self.isEditable = true
        self.readOnlyEntries = []
        self.onChange = { value in
            metadata.wrappedValue = value
        }
        _editableEntries = State(initialValue: entries)
    }

    var body: some View {
        Section(title) {
            if isEditable {
                editableContent
            } else {
                readOnlyContent
            }
        }
    }

    private var readOnlyContent: some View {
        Group {
            if readOnlyEntries.isEmpty {
                EmptyStateView(message: "No metadata")
            } else {
                ForEach(readOnlyEntries) { entry in
                    HStack(alignment: .firstTextBaseline) {
                        Text(entry.key)
                        Spacer(minLength: 12)
                        Text(entry.value)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
        }
    }

    private var editableContent: some View {
        Group {
            if editableEntries.isEmpty {
                EmptyStateView(message: "No metadata yet")
            }

            ForEach($editableEntries) { $entry in
                VStack(alignment: .leading, spacing: 8) {
                    metadataKeyField(text: $entry.key)
                    TextField("Value", text: $entry.value)
                }
            }
            .onDelete(perform: deleteEntries)

            Button("Add Metadata", action: addEntry)
        }
        .onChange(of: editableEntries) { _, updatedEntries in
            onChange?(MetadataDraft.materialize(entries: updatedEntries))
        }
    }

    private func addEntry() {
        editableEntries.append(MetadataEntry(id: UUID(), key: "", value: ""))
    }

    private func deleteEntries(at offsets: IndexSet) {
        editableEntries.remove(atOffsets: offsets)
    }

    @ViewBuilder
    private func metadataKeyField(text: Binding<String>) -> some View {
        #if os(iOS) || os(tvOS) || os(watchOS)
        TextField("Key", text: text)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        #else
        TextField("Key", text: text)
        #endif
    }
}

#Preview {
    Form {
        MetadataSection(metadata: ["branch": "main", "owner": "orbit"])

        MetadataSection(
            metadata: .constant([
                "status": "ready",
                "ticket": "T-42"
            ])
        )
    }
}
