import Foundation

enum ReportMarkdownFormatter {
    static func format(_ data: ReportData) -> String {
        var lines: [String] = []

        lines.append("# Report: \(data.dateRangeLabel)")

        if data.isEmpty {
            lines.append("")
            lines.append("No tasks completed or abandoned in this period.")
            return lines.joined(separator: "\n") + "\n"
        }

        lines.append("")
        let summary = ReportData.summaryText(done: data.totalDone, abandoned: data.totalAbandoned)
        let taskWord = data.totalTasks == 1 ? "task" : "tasks"
        lines.append("**\(data.totalTasks) \(taskWord)** (\(summary))")

        for group in data.projectGroups {
            lines.append("")
            lines.append("## \(sanitize(group.projectName))")
            lines.append("")
            lines.append(ReportData.summaryText(done: group.doneCount, abandoned: group.abandonedCount))
            lines.append("")

            for task in group.tasks {
                lines.append(formatTask(task))
            }
        }

        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Private

    private static func formatTask(_ task: ReportTask) -> String {
        let name = sanitize(task.name)
        let typeLabel = task.taskType.rawValue.capitalized
        if task.isAbandoned {
            return "- ~~\(task.displayID): \(typeLabel): \(name)~~ (Abandoned)"
        }
        return "- \(task.displayID): \(typeLabel): \(name)"
    }

    private static func sanitize(_ text: String) -> String {
        escape(normalize(text))
    }

    private static func normalize(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
    }

    private static func escape(_ text: String) -> String {
        var output = String()
        output.reserveCapacity(text.count)
        for character in text {
            switch character {
            case "\\", "`", "*", "_", "~", "[", "]", "#", "<", ">", "|":
                output.append("\\")
                output.append(character)
            default:
                output.append(character)
            }
        }
        return output
    }
}
