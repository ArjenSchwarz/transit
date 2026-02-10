import CoreTransferable
import Foundation
import UniformTypeIdentifiers

struct TaskDragPayload: Codable, Transferable {
    let taskID: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .taskDragPayload)
    }
}

extension UTType {
    nonisolated static let taskDragPayload = UTType(exportedAs: "me.nore.ig.transit.task-drag-payload")
}
