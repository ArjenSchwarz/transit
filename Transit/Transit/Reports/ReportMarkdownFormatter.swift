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
        let summary = summaryParts(done: data.totalDone, abandoned: data.totalAbandoned)
        lines.append("**\(data.totalTasks) tasks** (\(summary))")

        for group in data.projectGroups {
            lines.append("")
            lines.append("## \(sanitize(group.projectName))")
            lines.append("")
            lines.append(summaryParts(done: group.doneCount, abandoned: group.abandonedCount))
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
        if task.isAbandoned {
            return "- ~~\(task.displayID): \(name)~~ (Abandoned)"
        }
        return "- \(task.displayID): \(name)"
    }

    private static func summaryParts(done: Int, abandoned: Int) -> String {
        switch (done > 0, abandoned > 0) {
        case (true, true):
            return "\(done) done, \(abandoned) abandoned"
        case (true, false):
            return "\(done) done"
        case (false, true):
            return "\(abandoned) abandoned"
        case (false, false):
            return "0 done"
        }
    }

    private static func sanitize(_ text: String) -> String {
        var result = text
        // Normalize newlines first
        result = result.replacingOccurrences(of: "\r\n", with: " ")
        result = result.replacingOccurrences(of: "\r", with: " ")
        result = result.replacingOccurrences(of: "\n", with: " ")
        // Escape GFM metacharacters — backslash first
        result = result.replacingOccurrences(of: "\\", with: "\\\\")
        result = result.replacingOccurrences(of: "`", with: "\\`")
        result = result.replacingOccurrences(of: "*", with: "\\*")
        result = result.replacingOccurrences(of: "_", with: "\\_")
        result = result.replacingOccurrences(of: "~", with: "\\~")
        result = result.replacingOccurrences(of: "[", with: "\\[")
        result = result.replacingOccurrences(of: "]", with: "\\]")
        result = result.replacingOccurrences(of: "#", with: "\\#")
        result = result.replacingOccurrences(of: "<", with: "\\<")
        result = result.replacingOccurrences(of: ">", with: "\\>")
        result = result.replacingOccurrences(of: "|", with: "\\|")
        return result
    }
}
