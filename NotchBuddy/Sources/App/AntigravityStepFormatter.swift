import Foundation

enum AntigravityStepFormatter {

    /// Collapses whitespace and limits length for single-line display.
    static func oneLine(_ text: String, limit: Int = 60) -> String {
        let collapsed = text.split(whereSeparator: { $0.isNewline || $0 == "\t" })
                            .joined(separator: " ")
        return collapsed.count > limit ? String(collapsed.prefix(limit)) + "…" : collapsed
    }

    /// Infers a localized verb from a shell command's first word or test runner patterns.
    static func bashVerb(_ command: String) -> String {
        let first = command.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? ""
        switch first {
        case "cat", "bat", "head", "tail", "less", "more", "nl":
            return String(localized: "step.reads", defaultValue: "Reads")
        case "rg", "grep", "find", "fd", "ls", "tree", "wc":
            return String(localized: "step.searches", defaultValue: "Searches")
        default:
            break
        }
        let testRunners = ["pytest", "vitest", "jest", "npm test", "npm run test",
                           "cargo test", "go test", "swift test", "make test",
                           "xcodebuild test", "unittest"]
        if testRunners.contains(where: { command.contains($0) }) {
            return String(localized: "step.tests", defaultValue: "Tests")
        }
        return String(localized: "step.runs", defaultValue: "Runs")
    }

    /// Formats an Antigravity tool or explicit action into a localized ticker step string.
    /// Returns `nil` if neither explicit action nor an Antigravity tool name is present.
    static func formatStep(tool: String, input: [String: Any]) -> String? {
        // 1. Explicit toolAction or toolSummary takes precedence
        let rawAction = (input["toolAction"] as? String) ?? (input["toolSummary"] as? String)
        if let action = rawAction?.trimmingCharacters(in: .whitespacesAndNewlines), !action.isEmpty {
            if let target = (input["TargetFile"] as? String) ?? (input["AbsolutePath"] as? String), !target.isEmpty {
                return "\(action) · \(URL(fileURLWithPath: target).lastPathComponent)"
            } else if let cmd = input["CommandLine"] as? String, !cmd.isEmpty {
                return "\(action) · \(oneLine(cmd))"
            } else if let query = input["query"] as? String, !query.isEmpty {
                return "\(action) · \(oneLine(query))"
            }
            return action
        }

        // 2. Default verbs for Antigravity tool names
        switch tool {
        case "run_command":
            if let cmd = input["CommandLine"] as? String, !cmd.isEmpty {
                let verb = bashVerb(cmd)
                return "\(verb) · \(oneLine(cmd))"
            }
            return String(localized: "step.runs", defaultValue: "Runs")

        case "view_file":
            let label = String(localized: "step.reads", defaultValue: "Reads")
            if let target = (input["AbsolutePath"] as? String) ?? (input["TargetFile"] as? String) ?? (input["path"] as? String) ?? (input["file_path"] as? String), !target.isEmpty {
                return "\(label) · \(URL(fileURLWithPath: target).lastPathComponent)"
            }
            return label

        case "write_to_file":
            let label = String(localized: "step.writes", defaultValue: "Writes")
            if let target = (input["TargetFile"] as? String) ?? (input["file_path"] as? String) ?? (input["AbsolutePath"] as? String), !target.isEmpty {
                return "\(label) · \(URL(fileURLWithPath: target).lastPathComponent)"
            }
            return label

        case "replace_file_content":
            let label = String(localized: "step.edits", defaultValue: "Edits")
            if let target = (input["TargetFile"] as? String) ?? (input["file_path"] as? String) ?? (input["AbsolutePath"] as? String), !target.isEmpty {
                return "\(label) · \(URL(fileURLWithPath: target).lastPathComponent)"
            }
            return label

        case "read_url_content":
            let label = String(localized: "step.fetches", defaultValue: "Fetches")
            if let url = (input["Url"] as? String) ?? (input["url"] as? String) ?? (input["URL"] as? String), !url.isEmpty {
                return "\(label) · \(oneLine(url))"
            }
            return label

        case "search_web":
            let label = String(localized: "step.web-search", defaultValue: "Searches the web")
            if let query = input["query"] as? String, !query.isEmpty {
                return "\(label) · \(oneLine(query))"
            }
            return label

        case "manage_task":
            let label = String(localized: "step.tasks", defaultValue: "Tasks")
            if let action = (input["Action"] as? String) ?? (input["action"] as? String) ?? (input["TaskId"] as? String) ?? (input["taskId"] as? String), !action.isEmpty {
                return "\(label) · \(oneLine(action))"
            }
            return label

        case "ask_question":
            return String(localized: "step.asks", defaultValue: "Asks")

        case "invoke_subagent":
            return String(localized: "step.subagents", defaultValue: "Subagents")

        case "define_subagent":
            return String(localized: "step.subagent", defaultValue: "Subagent")

        default:
            return nil
        }
    }
}
