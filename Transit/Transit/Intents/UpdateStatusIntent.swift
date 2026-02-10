import Foundation
#if canImport(AppIntents)
import AppIntents
#endif

#if canImport(AppIntents)
struct UpdateStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Transit: Update Status"
    static let openAppWhenRun = false

    @Parameter(title: "Input JSON")
    var input: String

    @Dependency private var taskService: TaskService

    @MainActor
    func perform() async -> some IntentResult & ReturnsValue<String> {
        let output = Self.execute(input: input, taskService: taskService)
        return .result(value: output)
    }
}
#endif

extension UpdateStatusIntent {
    @MainActor
    static func execute(
        input: String,
        taskService: TaskService
    ) -> String {
        guard let object = IntentJSON.parseObject(from: input) else {
            return IntentError.invalidInput(
                hint: "Expected JSON object with displayId and status."
            ).response
        }

        guard let displayID = parseDisplayID(object["displayId"]) else {
            return IntentError.invalidInput(
                hint: "Field 'displayId' is required (e.g. 42 or \"T-42\")."
            ).response
        }

        guard let statusValue = object["status"] as? String,
              let newStatus = parseStatus(statusValue) else {
            return IntentError.invalidStatus(
                hint: "Field 'status' must be one of TaskStatus raw values."
            ).response
        }

        let task: TransitTask
        do {
            task = try taskService.findByDisplayID(displayID)
        } catch TaskService.Error.taskNotFound {
            return IntentError.taskNotFound(
                hint: "No task found with displayId T-\(displayID)."
            ).response
        } catch {
            return IntentError.invalidInput(hint: "Unable to resolve task by displayId.").response
        }

        do {
            try taskService.updateStatus(task: task, to: newStatus)
            let payload: [String: Any] = [
                "ok": true,
                "taskId": task.id.uuidString.lowercased(),
                "displayId": displayID,
                "status": task.status.rawValue
            ]
            return IntentJSON.encode(payload)
        } catch {
            return IntentError.invalidInput(hint: "Unable to update task status.").response
        }
    }

    static func parseDisplayID(_ rawValue: Any?) -> Int? {
        if let intValue = rawValue as? Int, intValue > 0 {
            return intValue
        }
        guard let stringValue = rawValue as? String else {
            return nil
        }
        let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("T-") {
            return Int(trimmed.dropFirst(2))
        }
        return Int(trimmed)
    }

    static func parseStatus(_ rawValue: String) -> TaskStatus? {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let status = TaskStatus(rawValue: normalized) {
            return status
        }

        switch normalized {
        case "ready for implementation":
            return .readyForImplementation
        case "in progress":
            return .inProgress
        case "ready for review":
            return .readyForReview
        default:
            return nil
        }
    }
}
