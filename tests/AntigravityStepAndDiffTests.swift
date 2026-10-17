import Foundation

@main
enum AntigravityStepAndDiffTests {
    static var failures = 0

    static func check(_ label: String, _ condition: Bool) {
        if condition {
            print("  ✓ \(label)")
        } else {
            print("  ✗ \(label)")
            failures += 1
        }
    }

    static func main() {
        print("AntigravityStepAndDiffTests")

        // ── 1. Tool action mapping: explicit toolAction takes precedence ─────────
        print("\n1. Explicit toolAction / toolSummary mapping")
        do {
            let inputWithAction: [String: Any] = [
                "toolAction": "Searching the web",
                "toolSummary": "Web search",
                "query": "swift concurrency"
            ]
            let step1 = AntigravityStepFormatter.formatStep(tool: "search_web", input: inputWithAction)
            check("toolAction formatted correctly", step1?.contains("Searching the web") == true)
            check("toolAction includes query", step1?.contains("swift concurrency") == true)
            check("toolAction format is action · query", step1 == "Searching the web · swift concurrency")

            let inputWithTargetFile: [String: Any] = [
                "toolAction": "Refactoring code",
                "TargetFile": "/path/to/test.swift"
            ]
            let stepTarget = AntigravityStepFormatter.formatStep(tool: "replace_file_content", input: inputWithTargetFile)
            check("toolAction with TargetFile shows filename", stepTarget == "Refactoring code · test.swift")

            let inputWithAbsPath: [String: Any] = [
                "toolAction": "Checking file",
                "AbsolutePath": "/Users/pavel/Models/User.swift"
            ]
            let stepAbs = AntigravityStepFormatter.formatStep(tool: "view_file", input: inputWithAbsPath)
            check("toolAction with AbsolutePath shows filename", stepAbs == "Checking file · User.swift")

            let inputWithCmd: [String: Any] = [
                "toolAction": "Running tests",
                "CommandLine": "swift test --filter AntigravityTests"
            ]
            let stepCmd = AntigravityStepFormatter.formatStep(tool: "run_command", input: inputWithCmd)
            check("toolAction with CommandLine shows command", stepCmd == "Running tests · swift test --filter AntigravityTests")

            let inputNoDetails: [String: Any] = [
                "toolAction": "Initializing workspace"
            ]
            let stepNoDetails = AntigravityStepFormatter.formatStep(tool: "unknown_tool", input: inputNoDetails)
            check("toolAction without details returns action", stepNoDetails == "Initializing workspace")

            let inputSummaryFallback: [String: Any] = [
                "toolSummary": "Code search",
                "query": "DiffEngine"
            ]
            let stepSummary = AntigravityStepFormatter.formatStep(tool: "search_web", input: inputSummaryFallback)
            check("toolSummary fallback works when toolAction absent", stepSummary == "Code search · DiffEngine")
        }

        // ── 2. Antigravity tools default labels ──────────────────────────────────
        print("\n2. Antigravity tools default labels")
        do {
            let inputRead: [String: Any] = ["AbsolutePath": "/Users/pavel/file.swift"]
            let step2 = AntigravityStepFormatter.formatStep(tool: "view_file", input: inputRead)
            check("view_file shows file.swift", step2?.contains("file.swift") == true)
            check("view_file format is Reads · file.swift", step2 == "Reads · file.swift")

            let inputWrite: [String: Any] = ["TargetFile": "/Users/pavel/Config.swift"]
            let stepWrite = AntigravityStepFormatter.formatStep(tool: "write_to_file", input: inputWrite)
            check("write_to_file shows Writes · Config.swift", stepWrite == "Writes · Config.swift")

            let inputEdit: [String: Any] = ["TargetFile": "/Users/pavel/App.swift"]
            let stepEdit = AntigravityStepFormatter.formatStep(tool: "replace_file_content", input: inputEdit)
            check("replace_file_content shows Edits · App.swift", stepEdit == "Edits · App.swift")

            let inputFetch: [String: Any] = ["Url": "https://api.github.com/repos"]
            let stepFetch = AntigravityStepFormatter.formatStep(tool: "read_url_content", input: inputFetch)
            check("read_url_content shows Fetches · url", stepFetch == "Fetches · https://api.github.com/repos")

            let inputSearch: [String: Any] = ["query": "swift concurrency"]
            let stepSearch = AntigravityStepFormatter.formatStep(tool: "search_web", input: inputSearch)
            check("search_web shows Searches the web · query", stepSearch == "Searches the web · swift concurrency")

            let inputTask: [String: Any] = ["Action": "list"]
            let stepTask = AntigravityStepFormatter.formatStep(tool: "manage_task", input: inputTask)
            check("manage_task shows Tasks · list", stepTask == "Tasks · list")

            let stepAsk = AntigravityStepFormatter.formatStep(tool: "ask_question", input: [:])
            check("ask_question shows Asks", stepAsk == "Asks")

            let stepSubagents = AntigravityStepFormatter.formatStep(tool: "invoke_subagent", input: [:])
            check("invoke_subagent shows Subagents", stepSubagents == "Subagents")

            let stepSubagent = AntigravityStepFormatter.formatStep(tool: "define_subagent", input: [:])
            check("define_subagent shows Subagent", stepSubagent == "Subagent")
        }

        // ── 3. run_command bash verb inference ──────────────────────────────────
        print("\n3. run_command bash verb inference")
        do {
            let testCmd: [String: Any] = ["CommandLine": "pytest tests/test_api.py"]
            let stepTest = AntigravityStepFormatter.formatStep(tool: "run_command", input: testCmd)
            check("run_command infers Tests for pytest", stepTest == "Tests · pytest tests/test_api.py")

            let readCmd: [String: Any] = ["CommandLine": "cat /etc/resolv.conf"]
            let stepRead = AntigravityStepFormatter.formatStep(tool: "run_command", input: readCmd)
            check("run_command infers Reads for cat", stepRead == "Reads · cat /etc/resolv.conf")

            let searchCmd: [String: Any] = ["CommandLine": "grep -rn Antigravity ."]
            let stepSearch = AntigravityStepFormatter.formatStep(tool: "run_command", input: searchCmd)
            check("run_command infers Searches for grep", stepSearch == "Searches · grep -rn Antigravity .")

            let defaultCmd: [String: Any] = ["CommandLine": "echo 'hello'"]
            let stepDefault = AntigravityStepFormatter.formatStep(tool: "run_command", input: defaultCmd)
            check("run_command defaults to Runs for echo", stepDefault == "Runs · echo 'hello'")

            let emptyCmd: [String: Any] = [:]
            let stepEmpty = AntigravityStepFormatter.formatStep(tool: "run_command", input: emptyCmd)
            check("run_command with no command shows Runs", stepEmpty == "Runs")
        }

        // ── 4. Diff generation: write_to_file ────────────────────────────────────
        print("\n4. Diff generation: write_to_file")
        do {
            let writeInput: [String: Any] = [
                "TargetFile": "/tmp/test.swift",
                "CodeContent": "let a = 1\nlet b = 2\n"
            ]
            let diffWrite = DiffEngine.fromAntigravityTool(tool: "write_to_file", input: writeInput)
            check("write_to_file diff generated", diffWrite != nil)
            check("write_to_file added lines == 2", diffWrite?.added == 2)
            check("write_to_file removed lines == 0", diffWrite?.removed == 0)
            check("write_to_file name is test.swift", diffWrite?.name == "test.swift")
            check("write_to_file isNewFile is true", diffWrite?.isNewFile == true)

            // Empty content returns nil
            let emptyWriteInput: [String: Any] = [
                "TargetFile": "/tmp/empty.swift",
                "CodeContent": ""
            ]
            check("empty content write_to_file returns nil",
                  DiffEngine.fromAntigravityTool(tool: "write_to_file", input: emptyWriteInput) == nil)
        }

        // ── 5. Diff generation: replace_file_content ─────────────────────────────
        print("\n5. Diff generation: replace_file_content")
        do {
            let replaceInput: [String: Any] = [
                "TargetFile": "/tmp/test.swift",
                "TargetContent": "let a = 1\n",
                "ReplacementContent": "let a = 42\n"
            ]
            let diffReplace = DiffEngine.fromAntigravityTool(tool: "replace_file_content", input: replaceInput)
            check("replace_file_content diff generated", diffReplace != nil)
            check("replace_file_content path is test.swift", diffReplace?.name == "test.swift")
            check("replace_file_content added == 1", diffReplace?.added == 1)
            check("replace_file_content removed == 1", diffReplace?.removed == 1)
            check("replace_file_content has hunks", diffReplace?.hunks.isEmpty == false)
            check("replace_file_content isNewFile is false", diffReplace?.isNewFile == false)

            // Pure removal
            let deleteInput: [String: Any] = [
                "TargetFile": "/tmp/delete.swift",
                "TargetContent": "line to remove\n",
                "ReplacementContent": ""
            ]
            let diffDelete = DiffEngine.fromAntigravityTool(tool: "replace_file_content", input: deleteInput)
            check("replace_file_content deletion generates diff", diffDelete != nil)
            check("deletion removed lines == 1", diffDelete?.removed == 1)
            check("deletion added lines == 0", diffDelete?.added == 0)

            // Unhandled tool returns nil
            check("unhandled tool returns nil",
                  DiffEngine.fromAntigravityTool(tool: "view_file", input: replaceInput) == nil)
        }

        print("\nTotal failures: \(failures)")
        if failures > 0 {
            exit(1)
        }
    }
}
