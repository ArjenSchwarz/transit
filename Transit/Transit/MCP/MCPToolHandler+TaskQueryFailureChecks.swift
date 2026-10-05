#if os(macOS)
import Foundation
import SwiftData

extension MCPToolHandler {
    /// Retain injected storage-error surfaces only. Successful live lookup
    /// values and semantic no-match/ambiguity outcomes never select saved rows.
    func checkTaskQueryProjectStorage(_ args: [String: Any]) throws {
        let result: Result<Project, ProjectLookupError>?
        if let raw = args["projectId"] as? String, let id = UUID(uuidString: raw) {
            result = projectService.findProject(id: id)
        } else if let name = args["project"] as? String, !name.trimmingCharacters(in: .whitespaces).isEmpty {
            result = projectService.findProject(id: nil, name: name)
        } else { result = nil }
        if let result, case .failure(.storageFailure(let hint)) = result {
            throw MCPTaskQueryError(code: "QUERY_FAILED", message: hint)
        }
    }

    func checkTaskQueryMilestoneStorage(_ args: [String: Any], project: ReadProjectIdentity?) throws {
        if let id = IntentHelpers.parseIntValue(args["milestoneDisplayId"]) {
            do { _ = try milestoneDisplayIDFinder.findByDisplayID(id) } catch is MilestoneService.Error {
                // Saved projection owns identity and missing-record validation.
            } catch { throw MCPTaskQueryError(code: "QUERY_FAILED", message: "Failed to look up milestone: \(error)") }
            return
        }
        guard let name = args["milestone"] as? String,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard let id = project?.id else {
            do { _ = try milestoneFetcher.fetchAllMilestones() } catch {
                throw MCPTaskQueryError(code: "QUERY_FAILED", message: "Failed to fetch milestones: \(error)")
            }
            return
        }
        let context = ModelContext(taskService.savedReadContainer)
        context.autosaveEnabled = false
        var descriptor = FetchDescriptor<Project>(predicate: #Predicate { $0.id == id })
        descriptor.includePendingChanges = false
        descriptor.fetchLimit = 2
        let matches = try context.fetch(descriptor)
        guard matches.count == 1, let project = matches.first else { return }
        do { _ = try milestoneService.findByName(name, in: project) } catch is MilestoneService.Error {
            // Discard hook's semantic outcomes; use the original saved capture.
        } catch { throw MCPTaskQueryError(code: "QUERY_FAILED", message: "Failed to look up milestone: \(error)") }
    }

}
#endif
