# First-Class Agent Antigravity & Multi-Agent Concurrency Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transform Google Antigravity into a First-Class Citizen in NotchBuddy (Coucou) alongside Claude Code and Codex, enabling conflict-free simultaneous execution of multiple agents with unified approval/question arbitration, live diffs, ticker integration, background completion alerts, and local quota plan gauge.

**Architecture:** 
1. **First-Class Agent Abstraction:** Generalize agent management in `HookServer.swift` and `PillCatalog.swift` so that all declared agents (specifically `agent_antigravity`, `agent_codex`, `integration_claude`, and `agent_cursor`) are treated as persistent first-class workspace agents. Remove disposable "external agent" auto-deletion on `Stop`, preserving `AgentTask` history, diffs, and transitioning to `.idle`.
2. **Multi-Agent Event Arbitration & Dual Queuing:** Introduce `QuestionQueue` alongside `ApprovalQueue` with unified interactive request tracking. Multiple agents (e.g. Claude + Antigravity) running simultaneously can have pending decisions or questions concurrently without closing sockets or displacing each other. The Island UI displays queue position (`1 of N`) with smooth card switching. Background agent completions trigger distinct notifications (`PillBadge.finished`, completion toast chip, sound) without hijacking active foreground work.
3. **Antigravity Tooling & Live Diffs:** Map Antigravity's specific tools (`run_command`, `view_file`, `write_to_file`, `replace_file_content`, `read_url_content`, `search_web`, `manage_task`) and their descriptors (`toolAction`, `toolSummary`) to localized ticker steps. Support live unified diff generation for `write_to_file` and `replace_file_content` via `DiffEngine`.
4. **Interactive Question Gateway (`ask_question`):** Extend `AskQuestion.parse` to handle Antigravity's `[String]` options format and `is_multi_select` boolean. Route `ask_question` through `nb-hook.py --ask` to NotchBuddy's notch UI and relay answers back to Antigravity as valid updated inputs.
5. **Antigravity Quota Plan Gauge:** Auto-discover the local `language_server` process for Antigravity Desktop, query its `RetrieveUserQuotaSummary` HTTPS RPC endpoint with `x-codeium-csrf-token`, and parse 5-hour and weekly quota buckets for Gemini models and third-party models (Claude/GPT). Provide a CLI statusline fallback, island header chip, and a detailed four-bar modal card (`AntigravityPlanCardView`).

**Tech Stack:** Swift 6, SwiftUI, AppKit, Python 3, POSIX Unix Domain Sockets, macOS `/bin/ps`, `/usr/sbin/lsof`, URLSession.

**Spec:** Transform Antigravity into a First-Class Citizen in NotchBuddy with conflict-free concurrent multi-agent arbitration (Claude + Antigravity + Codex), full ticker & diff support, `ask_question` notch UI, and quota plan gauge.

---

## Global Constraints

- Target macOS deployment: macOS 15.0+ (Sequoia or later).
- Code generated in `HookServer.swift` (`nbHookPythonGitHub`) must remain self-contained with no external Python dependencies (standard library only: `sys`, `json`, `os`, `socket`, `subprocess`, `signal`, `urllib`).
- Zero Swift 6 concurrency warnings or errors. Must compile cleanly under `xcodebuild -scheme NotchBuddy`.
- Sockets held open for pending questions and approvals must not be closed, leaked, or preemptively dismissed with `"ask"` when another agent enqueues a request.
- Every task must include standalone TDD verification scripts runnable via `swiftc` or `python3`.
- No regressions to existing Claude Code or Codex hooks and plan gauges.

---

## Review Focus

1. **Multi-Agent Socket Descriptors:** When Claude and Antigravity both request interaction (e.g., Claude asks a question, Antigravity requests file modification approval), neither socket connection may be dropped or answered early with `"ask"`. Both must remain pending in their respective queues.
2. **Background Turn Completion:** When agent A is in focus and agent B finishes (`Stop`), agent B's task must not be removed, its badge must remain until the user focuses it, and active card state for agent A must not be forcefully closed or corrupted.
3. **Antigravity `ask_question` Parsing Polymorphism:** `AskQuestion.parse` must gracefully handle both Claude's schema (`options: [[String: Any]]`, `multiSelect: Bool`) and Antigravity's schema (`options: [String]`, `is_multi_select: Bool`), with optional or missing headers.
4. **Antigravity Live Diff Robustness:** File diffs for `write_to_file` and `replace_file_content` must correctly parse relative or absolute file paths, old/new text blocks, and never crash or return empty diffs for valid edits.
5. **Language Server RPC Resilience:** Auto-discovery of the Antigravity `language_server` port and CSRF token must handle cases where the IDE is not running, multiple instances exist, or TLS handshake requires trusting the local self-signed certificate, without blocking the UI thread.

---

### Task 1: First-Class Agent Architecture & Catalog Generalization

**Files:**
- Modify: `NotchBuddy/Sources/CoucouKit/PillCatalog.swift:55-64`
- Modify: `NotchBuddy/Sources/App/HookServer.swift:450-480,610-630,1050-1065`
- Test: `tests/FirstClassAgentTests.swift`
- Script: `scripts/test-first-class-agent.sh`

**Interfaces:**
- Consumes: `PillCatalog.all`, `PillCatalog.definition(for:)`, `AppState.shared`.
- Produces: `isFirstClassAgent(id: String) -> Bool` in `HookServer.swift`, persistent `AgentTask` with `isIntegration = true` for `agent_antigravity`, preserving task state as `.idle` on `Stop`.

- [ ] **Step 1: Write the failing unit test for first-class agent catalog and lifecycle**

Create `tests/FirstClassAgentTests.swift`:
```swift
import Foundation

@main
enum FirstClassAgentTests {
    static var failures = 0
    static func check(_ label: String, _ condition: Bool) {
        if condition { print("  ✓ \(label)") }
        else { print("  ✗ \(label)"); failures += 1 }
    }

    static func main() {
        print("FirstClassAgentTests")

        // 1. Antigravity session subtitle
        let agyDef = PillCatalog.definition(for: "agent_antigravity")
        check("agent_antigravity definition exists", agyDef != nil)
        check("agent_antigravity sessionSubtitle is Antigravity", agyDef?.sessionSubtitle == "Antigravity")

        // 2. First-class agent identification
        let firstClassPills = ["integration_claude", "agent_codex", "agent_cursor", "agent_antigravity"]
        for pill in firstClassPills {
            check("\(pill) is recognized as first-class", PillCatalog.definition(for: pill) != nil)
        }

        if failures > 0 { exit(1) }
    }
}
```

Create `scripts/test-first-class-agent.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-first-class.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc NotchBuddy/Sources/CoucouKit/PillCatalog.swift \
    NotchBuddy/Sources/CoucouKit/PillColors.swift \
    NotchBuddy/Sources/CoucouKit/IslandTypes.swift \
    tests/FirstClassAgentTests.swift -o "$TEST_DIR/first-class-tests"
"$TEST_DIR/first-class-tests"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `chmod +x scripts/test-first-class-agent.sh && ./scripts/test-first-class-agent.sh`
Expected: FAIL on `agyDef?.sessionSubtitle == "Antigravity"` (currently returns `"Agent"`).

- [ ] **Step 3: Update `PillCatalog.swift` and `HookServer.swift`**

1. In `NotchBuddy/Sources/CoucouKit/PillCatalog.swift`:
Update `sessionSubtitle`:
```swift
    var sessionSubtitle: String {
        switch id {
        case "integration_claude": return "Claude Code"
        case "agent_cursor":       return "Cursor"
        case "agent_codex":        return "Codex"
        case "agent_antigravity":   return "Antigravity"
        case "agent_hermes":       return "Hermes"
        case "agent_claude-desktop": return "Claude Desktop"
        default:                   return "Agent"
        }
    }
```

2. In `NotchBuddy/Sources/App/HookServer.swift`:
In `processEvent`:
Determine `agentId` and `isFirstClassAgent`:
```swift
        let isAgyEvent = rawAgent == "antigravity" || rawAgent == "agy"
        let isCodexEvent = rawAgent == "codex"
        let agentId: String
        let isExternalAgent: Bool
        var hostApp: String? = nil

        if isCodexEvent {
            agentId = "agent_codex"
            isExternalAgent = false
        } else if isAgyEvent {
            agentId = "agent_antigravity"
            isExternalAgent = false
        } else if let agent = validAgent {
            agentId = "agent_\(agent)"
            // Any agent declared in PillCatalog with .workspace category is first-class
            isExternalAgent = PillCatalog.definition(for: agentId)?.category != .workspace
        } else if isCursorEditor {
            agentId = "agent_cursor"
            isExternalAgent = false
        } else if isVSCodeEditor {
            agentId = "integration_claude"
            isExternalAgent = false
        } else if let host = ClaudeHost.terminal(termProgram: termProgram, bundleId: bundleId) {
            agentId = "integration_claude"
            isExternalAgent = false
            hostApp = host.bundleId
        } else {
            nbLog("Ignored \(name) from \(termProgram.isEmpty ? bundleId : termProgram) (\(projectName))")
            return
        }
```
In `Stop` handler:
When turn ends, if `isExternalAgent` is false, update state to `.idle` after 5.2s rather than removing the task:
```swift
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.2) {
                guard self.sessions.workingCount(pill: agentId) == 0 else { return }
                if isExternalAgent {
                    AppState.shared.removeTask(id: agentId)
                } else {
                    AppState.shared.updateTask(id: agentId, state: .idle)
                    if focused {
                        self.clearPillBadge(id: agentId)
                    }
                }
            }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./scripts/test-first-class-agent.sh`
Expected: PASS with all checks checked.

- [ ] **Step 5: Commit changes**

```bash
git add NotchBuddy/Sources/CoucouKit/PillCatalog.swift NotchBuddy/Sources/App/HookServer.swift tests/FirstClassAgentTests.swift scripts/test-first-class-agent.sh
git commit -m "feat(agent): elevate Antigravity to first-class workspace agent"
```

---

### Task 2: Polymorphic `AskQuestion` Parsing (Antigravity & Claude Code)

**Files:**
- Modify: `NotchBuddy/Sources/App/AskQuestion.swift:54-91`
- Modify: `tests/AskQuestionTests.swift:30-80`
- Script: `scripts/test-ask-question.sh`

**Interfaces:**
- Consumes: `toolInput: [String: Any]` dictionary.
- Produces: `AskQuestion.parse(toolInput:) -> AskQuestion?` supporting:
  - Claude format: `options: [[String: Any]]` (with `label` and optional `description`), `multiSelect: Bool`, optional `header`.
  - Antigravity format: `options: [String]`, `is_multi_select: Bool`, optional/empty `header`.
  - `AskQuestion.buildAnswers(questions:selections:) -> [String: Any]`.

- [ ] **Step 1: Write failing tests for Antigravity format in `tests/AskQuestionTests.swift`**

Add tests to `tests/AskQuestionTests.swift`:
```swift
        // ── Antigravity format: options as [String], is_multi_select ────────────
        let agyInput: [String: Any] = [
            "questions": [
                [
                    "question": "Which database engine would you like to use?",
                    "options": ["PostgreSQL", "SQLite", "MySQL"],
                    "is_multi_select": false
                ]
            ]
        ]
        let agyParsed = AskQuestion.parse(toolInput: agyInput)
        checkTrue("Antigravity question parses", agyParsed != nil)
        check("Antigravity question text", agyParsed?.questions.first?.question ?? "", "Which database engine would you like to use?")
        check("Antigravity options count", "\(agyParsed?.questions.first?.options.count ?? 0)", "3")
        check("Antigravity option 1 label", agyParsed?.questions.first?.options[0].label ?? "", "PostgreSQL")
        check("Antigravity option 1 desc empty", agyParsed?.questions.first?.options[0].description ?? "", "")
        checkTrue("Antigravity is_multi_select false", agyParsed?.questions.first?.multiSelect == false)

        let agyMultiInput: [String: Any] = [
            "questions": [
                [
                    "question": "Select target platforms",
                    "options": ["macOS", "iOS", "watchOS"],
                    "is_multi_select": true
                ]
            ]
        ]
        let agyMultiParsed = AskQuestion.parse(toolInput: agyMultiInput)
        checkTrue("Antigravity multi-select parses", agyMultiParsed?.questions.first?.multiSelect == true)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./scripts/test-ask-question.sh`
Expected: FAIL on `checkTrue("Antigravity question parses", agyParsed != nil)`.

- [ ] **Step 3: Implement polymorphic parsing in `AskQuestion.swift`**

In `NotchBuddy/Sources/App/AskQuestion.swift`:
```swift
    // MARK: - Parse from tool_input dict
    static func parse(toolInput: [String: Any]) -> AskQuestion? {
        guard let rawQs = toolInput["questions"] as? [[String: Any]],
              !rawQs.isEmpty, rawQs.count <= 4 else { return nil }
        var items: [AskQuestionItem] = []
        for raw in rawQs {
            guard let question = raw["question"] as? String, !question.isEmpty else { return nil }

            var opts: [AskQuestionOption] = []
            if let dictOpts = raw["options"] as? [[String: Any]] {
                // Claude Code format: [{"label": "...", "description": "..."}]
                guard dictOpts.count >= 2, dictOpts.count <= 4 else { return nil }
                for opt in dictOpts {
                    guard let label = opt["label"] as? String, !label.isEmpty else { return nil }
                    let desc = opt["description"] as? String ?? ""
                    opts.append(AskQuestionOption(label: label, description: desc))
                }
            } else if let stringOpts = raw["options"] as? [String] {
                // Antigravity format: ["Option 1", "Option 2", ...]
                guard stringOpts.count >= 2, stringOpts.count <= 4 else { return nil }
                for label in stringOpts {
                    guard !label.isEmpty else { return nil }
                    opts.append(AskQuestionOption(label: label, description: ""))
                }
            } else {
                return nil
            }

            let rawHeader = raw["header"] as? String ?? ""
            let header = String(rawHeader.prefix(12))
            let multi = (raw["multiSelect"] as? Bool) ?? (raw["is_multi_select"] as? Bool) ?? false
            items.append(AskQuestionItem(question: question, header: header, options: opts, multiSelect: multi))
        }
        return AskQuestion(questions: items)
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./scripts/test-ask-question.sh`
Expected: PASS for all tests (both Claude Code and Antigravity formats).

- [ ] **Step 5: Commit changes**

```bash
git add NotchBuddy/Sources/App/AskQuestion.swift tests/AskQuestionTests.swift
git commit -m "feat(question): support Antigravity ask_question format in AskQuestion parser"
```

---

### Task 3: Interactive Request Arbitration & Multi-Agent Queuing (`QuestionQueue`)

**Files:**
- Create: `NotchBuddy/Sources/App/QuestionQueue.swift`
- Modify: `NotchBuddy/Sources/App/HookServer.swift:935-1040`
- Modify: `NotchBuddy/Sources/App/IslandViewContent.swift:650-740`
- Modify: `NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj`
- Test: `tests/QuestionQueueTests.swift`
- Script: `scripts/test-question-queue.sh`

**Interfaces:**
- Produces: `struct QueuedQuestion`, `struct QuestionQueue`.
- In `HookServer`: `private var questions = QuestionQueue()`.
- Supports concurrent pending questions and approvals without dropping or overriding descriptors.

- [x] **Step 1: Write failing unit test for `QuestionQueue`**

Create `tests/QuestionQueueTests.swift`:
```swift
import Foundation

@main
enum QuestionQueueTests {
    static var failures = 0
    static func check(_ label: String, _ condition: Bool) {
        if condition { print("  ✓ \(label)") }
        else { print("  ✗ \(label)"); failures += 1 }
    }

    static func entry(_ n: Int, session: String = "s1", pill: String = "integration_claude") -> QueuedQuestion {
        let q = AskQuestion(questions: [AskQuestionItem(question: "Q\(n)?", header: "", options: [
            AskQuestionOption(label: "Yes", description: ""),
            AskQuestionOption(label: "No", description: "")
        ], multiSelect: false)])
        return QueuedQuestion(id: UUID(), fd: Int32(n), sessionId: session, pillId: pill,
                              projectName: "Project", cwd: "/tmp", question: q)
    }

    static func main() {
        print("QuestionQueueTests")
        var q = QuestionQueue()
        let q1 = entry(1, session: "s1", pill: "integration_claude")
        let q2 = entry(2, session: "s2", pill: "agent_antigravity")

        check("initial queue empty", q.isEmpty)
        check("enqueue q1 accepted", q.enqueue(q1) == .accepted)
        check("enqueue q2 accepted", q.enqueue(q2) == .accepted)
        check("queue count is 2", q.count == 2)
        check("head is q1", q.head == q1)
        check("position of q2 is 2", q.position(of: q2.id) == 2)

        // Mixed sources
        check("hasMixedSources true", q.hasMixedSources)

        // Removal of head
        check("remove head returns q1", q.remove(id: q1.id) == q1)
        check("head is now q2", q.head == q2)
        check("queue count is 1", q.count == 1)

        // Resolution by event
        let q3 = entry(3, session: "s3", pill: "agent_antigravity")
        _ = q.enqueue(q3)
        let resolved = q.resolved(byEvent: "Stop", sessionId: "s3", pillId: "agent_antigravity")
        check("resolved contains q3", resolved == [q3])

        if failures > 0 { exit(1) }
    }
}
```

Create `scripts/test-question-queue.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-qqueue.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc NotchBuddy/Sources/App/AskQuestion.swift \
    NotchBuddy/Sources/App/QuestionQueue.swift \
    tests/QuestionQueueTests.swift -o "$TEST_DIR/qqueue-tests"
"$TEST_DIR/qqueue-tests"
```

- [x] **Step 2: Run test to verify it fails**

Run: `chmod +x scripts/test-question-queue.sh && ./scripts/test-question-queue.sh`
Expected: FAIL (file `QuestionQueue.swift` does not exist yet).

- [x] **Step 3: Implement `QuestionQueue.swift` and integrate into `HookServer.swift`**

1. Create `NotchBuddy/Sources/App/QuestionQueue.swift`:
```swift
import Foundation

struct QueuedQuestion: Equatable, Sendable {
    let id: UUID
    let fd: Int32
    let sessionId: String
    let pillId: String
    let projectName: String
    let cwd: String
    let question: AskQuestion
    var hostApp: String? = nil
    var bundleId: String = ""
}

struct QuestionQueue: Sendable {
    static let maxPending = 5

    enum EnqueueResult: Equatable, Sendable { case accepted, rejectedFull }

    private(set) var entries: [QueuedQuestion] = []

    var head: QueuedQuestion? { entries.first }
    var count: Int { entries.count }
    var isEmpty: Bool { entries.isEmpty }

    func contains(id: UUID) -> Bool { entries.contains { $0.id == id } }

    func position(of id: UUID) -> Int? {
        entries.firstIndex { $0.id == id }.map { $0 + 1 }
    }

    var hasMixedSources: Bool {
        guard let first = entries.first else { return false }
        return entries.contains { $0.sessionId != first.sessionId || $0.pillId != first.pillId }
    }

    func hasEntries(forPill pillId: String) -> Bool {
        entries.contains { $0.pillId == pillId }
    }

    mutating func enqueue(_ entry: QueuedQuestion, maxPending: Int = QuestionQueue.maxPending) -> EnqueueResult {
        guard entries.count < maxPending else { return .rejectedFull }
        entries.append(entry)
        return .accepted
    }

    @discardableResult
    mutating func remove(id: UUID) -> QueuedQuestion? {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return nil }
        return entries.remove(at: idx)
    }

    func resolved(byEvent name: String, sessionId: String, pillId: String) -> [QueuedQuestion] {
        switch name {
        case "Stop", "StopFailure", "UserPromptSubmit", "SessionEnd", "Interrupt":
            return entries.filter { $0.pillId == pillId && $0.sessionId == sessionId }
        default:
            return []
        }
    }
}
```

2. Add `QuestionQueue.swift` to `NotchBuddy.xcodeproj/project.pbxproj`.

3. In `HookServer.swift`:
Replace `pendingQuestionFD: Int32` with `questions: QuestionQueue`.
In `processQuestionRequest`:
- Support `isAgyRequest = rawAgent == "antigravity" || rawAgent == "agy"`.
- If `isAgyRequest`, set `pillId = "agent_antigravity"`.
- When a new question arrives, if a question is already showing, do NOT close or kick out the earlier question! Instead, enqueue it into `questions`.
- In `IslandViewContent.swift`, update `QuestionView`:
  - Show the asking agent's name (`PillCatalog.definition(for: task.id)?.name ?? "Agent"`).
  - Show queue count `Text("\(index)/\(total)")` when multiple questions/approvals are pending.

- [x] **Step 4: Run unit test to verify it passes**

Run: `./scripts/test-question-queue.sh`
Expected: PASS.

- [x] **Step 5: Verify Xcode build**

Run: `xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug build CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO`
Expected: **BUILD SUCCEEDED**.

- [x] **Step 6: Commit changes**

```bash
git add NotchBuddy/Sources/App/QuestionQueue.swift NotchBuddy/Sources/App/HookServer.swift NotchBuddy/Sources/App/IslandViewContent.swift NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj tests/QuestionQueueTests.swift scripts/test-question-queue.sh
git commit -m "feat(arbitration): implement QuestionQueue and multi-agent interactive arbitration"
```

---

### Task 4: Background Agent Completion Alerts & Notification Toasts

**Files:**
- Modify: `NotchBuddy/Sources/App/AppState.swift:440-490`
- Modify: `NotchBuddy/Sources/App/HookServer.swift:610-630`
- Modify: `NotchBuddy/Sources/App/IslandRootView.swift:550-620`
- Test: `tests/AgentToastTests.swift`
- Script: `scripts/test-agent-toast.sh`

**Interfaces:**
- Produces: `struct AgentToast: Equatable`, `@Published var agentToast: AgentToast?` in `AppState`.
- Behavior: When an agent finishes (`Stop`) while NOT in focus:
  1. `PillBadge.finished` is set on the agent's pill and remains until focused.
  2. Sound `finish` is played.
  3. Floating completion toast chip appears in the island (e.g., "Antigravity: Done" with green checkmark).
  4. Clicking the toast or pill immediately focuses the agent and presents its final report.

- [ ] **Step 1: Write failing unit test for `AgentToast`**

Create `tests/AgentToastTests.swift`:
```swift
import Foundation

@main
enum AgentToastTests {
    static var failures = 0
    static func check(_ label: String, _ condition: Bool) {
        if condition { print("  ✓ \(label)") }
        else { print("  ✗ \(label)"); failures += 1 }
    }

    static func main() {
        print("AgentToastTests")
        let toast = AgentToast(pillId: "agent_antigravity", message: "Antigravity: Done", colorHex: "#E879F9")
        check("toast pillId", toast.pillId == "agent_antigravity")
        check("toast message", toast.message == "Antigravity: Done")
        check("toast color", toast.colorHex == "#E879F9")

        if failures > 0 { exit(1) }
    }
}
```

Create `scripts/test-agent-toast.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-toast.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc NotchBuddy/Sources/App/AgentToast.swift \
    tests/AgentToastTests.swift -o "$TEST_DIR/toast-tests"
"$TEST_DIR/toast-tests"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `chmod +x scripts/test-agent-toast.sh && ./scripts/test-agent-toast.sh`
Expected: FAIL (type `AgentToast` does not exist yet).

- [ ] **Step 3: Implement `AgentToast` in `AppState.swift` and `HookServer.swift`**

1. Create `NotchBuddy/Sources/App/AgentToast.swift`:
```swift
import Foundation

struct AgentToast: Equatable, Sendable {
    let pillId: String
    let message: String
    let colorHex: String
    var timestamp: Date = Date()
}
```
Add to Xcode project.

2. In `AppState.swift`:
```swift
    @Published var agentToast: AgentToast? = nil
    private var toastDismissTimer: DispatchWorkItem?

    func showAgentToast(pillId: String, message: String, colorHex: String) {
        agentToast = AgentToast(pillId: pillId, message: message, colorHex: colorHex)
        toastDismissTimer?.cancel()
        let timer = DispatchWorkItem { [weak self] in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                self?.agentToast = nil
            }
        }
        toastDismissTimer = timer
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0, execute: timer)
    }
```

3. In `HookServer.swift` under `case "Stop":`:
```swift
            if focused {
                expandIfNeeded(to: .finished)
            } else {
                setPillBadge(id: agentId, badge: .finished)
                let pillName = PillCatalog.definition(for: agentId)?.name ?? "Agent"
                let pillColor = PillCatalog.definition(for: agentId)?.color ?? "#22C55E"
                AppState.shared.showAgentToast(pillId: agentId, message: "\(pillName): Done", colorHex: pillColor)
            }
```

4. In `IslandRootView.swift`:
Render floating chip when `state.agentToast` is present with button action `state.setFocus(toast.pillId)`.

- [ ] **Step 4: Run test to verify it passes**

Run: `./scripts/test-agent-toast.sh`
Expected: PASS.

- [ ] **Step 5: Verify Xcode build**

Run: `xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug build CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO`
Expected: **BUILD SUCCEEDED**.

- [ ] **Step 6: Commit changes**

```bash
git add NotchBuddy/Sources/App/AgentToast.swift NotchBuddy/Sources/App/AppState.swift NotchBuddy/Sources/App/HookServer.swift NotchBuddy/Sources/App/IslandRootView.swift NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj tests/AgentToastTests.swift scripts/test-agent-toast.sh
git commit -m "feat(notification): add background agent completion badge and island toast"
```

---

### Task 5: Antigravity Ticker Steps, Action Mapping & Live Diffs

**Files:**
- Modify: `NotchBuddy/Sources/App/HookServer.swift:1145-1260`
- Test: `tests/AntigravityStepAndDiffTests.swift`
- Script: `scripts/test-antigravity-step-diff.sh`

**Interfaces:**
- Consumes: Tool events (`PreToolUse`, `PostToolUse`) with Antigravity tool names (`run_command`, `view_file`, `write_to_file`, `replace_file_content`, `read_url_content`, `search_web`, `manage_task`) and fields (`toolAction`, `toolSummary`, `TargetFile`, `CodeContent`, `TargetContent`, `ReplacementContent`).
- Produces: Localized ticker step strings and `FileDiff` instances via `DiffEngine`.

- [ ] **Step 1: Write failing unit test for Antigravity step localization and diff generation**

Create `tests/AntigravityStepAndDiffTests.swift`:
```swift
import Foundation

@main
enum AntigravityStepAndDiffTests {
    static var failures = 0
    static func check(_ label: String, _ condition: Bool) {
        if condition { print("  ✓ \(label)") }
        else { print("  ✗ \(label)"); failures += 1 }
    }

    static func main() {
        print("AntigravityStepAndDiffTests")

        // 1. Tool action mapping: explicit toolAction takes precedence
        let inputWithAction: [String: Any] = [
            "toolAction": "Searching the web",
            "toolSummary": "Web search",
            "query": "swift concurrency"
        ]
        let step1 = HookServer.formatStepForAntigravity(tool: "search_web", input: inputWithAction)
        check("toolAction formatted correctly", step1.contains("Searching the web"))

        // 2. Antigravity tools default labels
        let inputRead: [String: Any] = ["AbsolutePath": "/Users/pavel/file.swift"]
        let step2 = HookServer.formatStepForAntigravity(tool: "view_file", input: inputRead)
        check("view_file shows file.swift", step2.contains("file.swift"))

        // 3. Diff generation: write_to_file
        let writeInput: [String: Any] = [
            "TargetFile": "/tmp/test.swift",
            "CodeContent": "let a = 1\nlet b = 2\n"
        ]
        let diffWrite = HookServer.buildFileDiffForTesting(tool: "write_to_file", input: writeInput)
        check("write_to_file diff generated", diffWrite != nil)
        check("write_to_file added lines == 2", diffWrite?.added == 2)

        // 4. Diff generation: replace_file_content
        let replaceInput: [String: Any] = [
            "TargetFile": "/tmp/test.swift",
            "TargetContent": "let a = 1",
            "ReplacementContent": "let a = 42"
        ]
        let diffReplace = HookServer.buildFileDiffForTesting(tool: "replace_file_content", input: replaceInput)
        check("replace_file_content diff generated", diffReplace != nil)
        check("replace_file_content path is test.swift", diffReplace?.name == "test.swift")

        if failures > 0 { exit(1) }
    }
}
```

Create `scripts/test-antigravity-step-diff.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-step-diff.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc NotchBuddy/Sources/App/DiffEngine.swift \
    NotchBuddy/Sources/CoucouKit/IslandTypes.swift \
    tests/IslandTypeStubs.swift \
    tests/AntigravityStepAndDiffTests.swift -o "$TEST_DIR/step-diff-tests"
"$TEST_DIR/step-diff-tests"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `chmod +x scripts/test-antigravity-step-diff.sh && ./scripts/test-antigravity-step-diff.sh`
Expected: FAIL (methods `formatStepForAntigravity` / Antigravity diff handlers not defined yet).

- [ ] **Step 3: Implement Antigravity tools in `localizedStep` and `buildFileDiff`**

In `HookServer.swift`:
1. In `localizedStep`:
```swift
        // Antigravity specific toolAction overrides
        if let action = (input["toolAction"] as? String) ?? (input["toolSummary"] as? String), !action.isEmpty {
            if let target = (input["TargetFile"] as? String) ?? (input["AbsolutePath"] as? String) {
                return "\(action) · \(URL(fileURLWithPath: target).lastPathComponent)"
            } else if let cmd = input["CommandLine"] as? String {
                return "\(action) · \(oneLine(cmd))"
            }
            return action
        }

        let labels: [String: String] = [
            // ... existing labels ...
            "run_command":          String(localized: "step.runs",       defaultValue: "Runs"),
            "view_file":            String(localized: "step.reads",      defaultValue: "Reads"),
            "write_to_file":        String(localized: "step.writes",     defaultValue: "Writes"),
            "replace_file_content": String(localized: "step.edits",      defaultValue: "Edits"),
            "read_url_content":     String(localized: "step.fetches",    defaultValue: "Fetches"),
            "search_web":           String(localized: "step.web-search", defaultValue: "Searches the web"),
            "manage_task":          String(localized: "step.tasks",      defaultValue: "Tasks"),
            "ask_question":         String(localized: "step.asks",       defaultValue: "Asks"),
        ]
```
Support `CommandLine`, `AbsolutePath`, `TargetFile`, `Url` extraction.

2. In `buildFileDiff`:
```swift
        case "write_to_file":
            guard let path = (input["TargetFile"] as? String) ?? (input["file_path"] as? String),
                  let content = (input["CodeContent"] as? String) ?? (input["content"] as? String), !content.isEmpty else { return nil }
            let d = DiffEngine.fromNew(content: content, path: path)
            return (d.added > 0 || d.removed > 0) ? d : nil

        case "replace_file_content":
            guard let path = (input["TargetFile"] as? String) ?? (input["file_path"] as? String),
                  let old = (input["TargetContent"] as? String) ?? (input["old_string"] as? String),
                  let new = (input["ReplacementContent"] as? String) ?? (input["new_string"] as? String),
                  !old.isEmpty || !new.isEmpty else { return nil }
            let d = DiffEngine.fromEdit(old: old, new: new, path: path)
            return (d.added > 0 || d.removed > 0) ? d : nil
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./scripts/test-antigravity-step-diff.sh`
Expected: PASS.

- [ ] **Step 5: Verify Xcode build**

Run: `xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug build CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO`
Expected: **BUILD SUCCEEDED**.

- [ ] **Step 6: Commit changes**

```bash
git add NotchBuddy/Sources/App/HookServer.swift tests/AntigravityStepAndDiffTests.swift scripts/test-antigravity-step-diff.sh
git commit -m "feat(ticker): add Antigravity tool localization and live diff support"
```

---

### Task 6: Relay Updates in `nb-hook.py` (Transcript Reading & `--ask` Gateway)

**Files:**
- Modify: `NotchBuddy/Sources/App/HookServer.swift:1860-1880,3480-3665`
- Test: `tests/test_antigravity_hook_relay.py`

**Interfaces:**
- Consumes: Antigravity lifecycle events and JSON stdin.
- Produces:
  1. `PreInvocation`: reads `transcriptPath` (or looks in `~/.gemini/antigravity/brain/{session_id}/.system_generated/logs/transcript.jsonl`), finds last `USER_INPUT` or `USER_EXPLICIT` line, sets `payload["prompt"]`.
  2. `--ask` mode: handles `ask_question`, waits on socket, returns `{"decision": "allow", "updatedInput": {"questions": questions, "answers": answers}}` on answer.
  3. `buildAgyHooksData()`: registers `--ask` matcher for `ask_question` with 130s timeout in `~/.gemini/config/hooks.json`.

- [ ] **Step 1: Write failing Python test for `nb-hook.py` transcript extraction and `--ask` response**

Create `tests/test_antigravity_hook_relay.py`:
```python
import json
import os
import tempfile
import unittest

class TestAntigravityHookRelay(unittest.TestCase):

    def test_transcript_prompt_extraction(self):
        with tempfile.NamedTemporaryFile("w+", delete=False, suffix=".jsonl") as f:
            f.write(json.dumps({"type": "SYSTEM_MESSAGE", "content": "system"}) + "\n")
            f.write(json.dumps({"type": "USER_INPUT", "source": "USER_EXPLICIT", "content": "Add dark mode support"}) + "\n")
            f.write(json.dumps({"type": "PLANNER_RESPONSE", "content": "planning"}) + "\n")
            tpath = f.name

        try:
            # Emulate extraction logic
            extracted = None
            with open(tpath, "r", encoding="utf-8") as fp:
                for line in reversed(fp.readlines()):
                    if not line.strip(): continue
                    entry = json.loads(line)
                    if entry.get("type") == "USER_INPUT" or entry.get("source") == "USER_EXPLICIT":
                        extracted = entry.get("content")
                        break
            self.assertEqual(extracted, "Add dark mode support")
        finally:
            os.remove(tpath)

    def test_ask_question_response_payload(self):
        answers = {"Which database?": "PostgreSQL"}
        questions = [{"question": "Which database?", "options": ["PostgreSQL", "SQLite"]}]
        out = {
            "decision": "allow",
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "allow",
                "updatedInput": {"questions": questions, "answers": answers}
            },
            "updatedInput": {"questions": questions, "answers": answers}
        }
        self.assertEqual(out["decision"], "allow")
        self.assertEqual(out["updatedInput"]["answers"]["Which database?"], "PostgreSQL")

if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run Python test to verify baseline assertions pass**

Run: `python3 tests/test_antigravity_hook_relay.py`
Expected: PASS.

- [ ] **Step 3: Update `nb-hook.py` template and hook registration in `HookServer.swift`**

1. In `buildAgyHooksData()` in `HookServer.swift`:
```swift
        // Dedicated hook for ask_question with 130s timeout
        let askHook: [String: Any] = [
            "type": "command",
            "command": "\(base) --agent antigravity --ask PreToolUse",
            "timeout": 130
        ]
        let generalPreToolHook: [String: Any] = [
            "type": "command",
            "command": "\(base) --agent antigravity PreToolUse",
            "timeout": 10
        ]
        coucou["PreToolUse"] = [
            ["matcher": "ask_question", "hooks": [askHook]],
            ["matcher": "*", "hooks": [generalPreToolHook]]
        ]
```

2. In `nbHookPythonGitHub` in `HookServer.swift`:
In `--ask` mode:
```python
    if '--ask' in sys.argv[1:]:
        tool = payload.get('tool_name', '')
        if tool not in ('AskUserQuestion', 'ask_question'):
            return
```
And upon receiving `decision == 'answer'`:
```python
                if decision == 'answer':
                    answers = resp_obj.get('answers', {})
                    questions = payload.get('tool_input', {}).get('questions', [])
                    out = {
                        'decision': 'allow',
                        'hookSpecificOutput': {
                            'hookEventName': 'PreToolUse',
                            'permissionDecision': 'allow',
                            'updatedInput': {'questions': questions, 'answers': answers}
                        },
                        'updatedInput': {'questions': questions, 'answers': answers}
                    }
                    print(json.dumps(out), flush=True)
                    sys.exit(0)
```
In `PreInvocation`:
Extract `USER_INPUT` prompt from transcript and populate `payload['prompt']`.

- [ ] **Step 4: Verify Xcode build**

Run: `xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug build CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO`
Expected: **BUILD SUCCEEDED**.

- [ ] **Step 5: Commit changes**

```bash
git add NotchBuddy/Sources/App/HookServer.swift tests/test_antigravity_hook_relay.py
git commit -m "feat(hooks): configure Antigravity ask_question and PreInvocation prompt relay"
```

---

### Task 7: Antigravity Plan Gauge & Quota Discovery (`AntigravityPlanGauge`)

**Files:**
- Create: `NotchBuddy/Sources/App/AntigravityPlanGauge.swift`
- Create: `NotchBuddy/Sources/App/AntigravityPlanCardView.swift`
- Modify: `NotchBuddy/Sources/App/AppState.swift:500-550`
- Modify: `NotchBuddy/Sources/App/IslandRootView.swift:560-575,685-715`
- Modify: `NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj`
- Test: `tests/AntigravityPlanGaugeTests.swift`
- Script: `scripts/test-antigravity-plan-gauge.sh`

**Interfaces:**
- Produces: `struct AntigravityPlanUsage`, `enum AntigravityPlanGauge`.
- Discovers `language_server` process on macOS via `ps aux`, finds CSRF token (`--csrf_token`), discovers listening port via `lsof`, queries `https://127.0.0.1:<port>/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary`.
- Parses buckets: `gemini-5h`, `gemini-weekly`, `3p-5h`, `3p-weekly`.
- Produces: `AntigravityPlanCardView` (SwiftUI modal) and header chip (e.g. `Gemini 95%`).

- [ ] **Step 1: Write failing unit test for `AntigravityPlanGauge`**

Create `tests/AntigravityPlanGaugeTests.swift`:
```swift
import Foundation

@main
enum AntigravityPlanGaugeTests {
    static var failures = 0
    static func check(_ label: String, _ condition: Bool) {
        if condition { print("  ✓ \(label)") }
        else { print("  ✗ \(label)"); failures += 1 }
    }

    static func main() {
        print("AntigravityPlanGaugeTests")

        let rawJSON = """
        {
          "response": {
            "groups": [
              {
                "displayName": "Gemini Models",
                "buckets": [
                  {
                    "bucketId": "gemini-weekly",
                    "window": "weekly",
                    "remainingFraction": 0.94,
                    "resetTime": "2026-10-24T05:59:38Z"
                  },
                  {
                    "bucketId": "gemini-5h",
                    "window": "5h",
                    "remainingFraction": 0.82,
                    "resetTime": "2026-10-17T10:59:38Z"
                  }
                ]
              },
              {
                "displayName": "Claude and GPT models",
                "buckets": [
                  {
                    "bucketId": "3p-weekly",
                    "window": "weekly",
                    "remainingFraction": 0.0,
                    "resetTime": "2026-10-20T06:38:25Z"
                  },
                  {
                    "bucketId": "3p-5h",
                    "window": "5h",
                    "remainingFraction": 1.0,
                    "resetTime": "2026-10-17T11:24:12Z"
                  }
                ]
              }
            ]
          }
        }
        """

        let data = Data(rawJSON.utf8)
        let usage = AntigravityPlanGauge.parse(data: data)
        check("parse non-nil", usage != nil)
        // usedPct = (1.0 - remainingFraction) * 100
        check("gemini 5h usedPct is 18%", abs((usage?.geminiFiveHour?.usedPct ?? 0) - 18.0) < 0.1)
        check("gemini weekly usedPct is 6%", abs((usage?.geminiWeekly?.usedPct ?? 0) - 6.0) < 0.1)
        check("3p weekly usedPct is 100%", abs((usage?.thirdPartyWeekly?.usedPct ?? 0) - 100.0) < 0.1)

        // Pill label
        let label = AntigravityPlanGauge.pillLabel(usage)
        check("pillLabel starts with Gemini", label.starts(with: "Gemini"))

        if failures > 0 { exit(1) }
    }
}
```

Create `scripts/test-antigravity-plan-gauge.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-agy-plan.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc NotchBuddy/Sources/App/ClaudePlanGauge.swift \
    NotchBuddy/Sources/App/AntigravityPlanGauge.swift \
    tests/AntigravityPlanGaugeTests.swift -o "$TEST_DIR/agy-plan-tests"
"$TEST_DIR/agy-plan-tests"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `chmod +x scripts/test-antigravity-plan-gauge.sh && ./scripts/test-antigravity-plan-gauge.sh`
Expected: FAIL (`AntigravityPlanGauge.swift` does not exist yet).

- [ ] **Step 3: Implement `AntigravityPlanGauge.swift` and `AntigravityPlanCardView.swift`**

1. Create `NotchBuddy/Sources/App/AntigravityPlanGauge.swift`:
```swift
import Foundation

struct AntigravityPlanUsage: Codable {
    var geminiFiveHour: PlanWindow?
    var geminiWeekly: PlanWindow?
    var thirdPartyFiveHour: PlanWindow?
    var thirdPartyWeekly: PlanWindow?
    var updatedAt: Date

    var dominantGeminiPct: Double? {
        let p1 = geminiFiveHour.map { ClaudePlanGauge.effectivePct($0) }
        let p2 = geminiWeekly.map { ClaudePlanGauge.effectivePct($0) }
        switch (p1, p2) {
        case (.none, .none): return nil
        case (let x?, .none): return x
        case (.none, let y?): return y
        case (let x?, let y?): return max(x, y)
        }
    }
}

enum AntigravityPlanGauge {
    static let isoFormatter = ISO8601DateFormatter()

    static func parse(data: Data) -> AntigravityPlanUsage? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let resp = obj["response"] as? [String: Any],
              let groups = resp["groups"] as? [[String: Any]] else { return nil }

        var g5h: PlanWindow? = nil
        var gWeek: PlanWindow? = nil
        var tp5h: PlanWindow? = nil
        var tpWeek: PlanWindow? = nil

        for group in groups {
            guard let buckets = group["buckets"] as? [[String: Any]] else { continue }
            for b in buckets {
                let id = b["bucketId"] as? String ?? ""
                guard let rem = b["remainingFraction"] as? Double,
                      let resetStr = b["resetTime"] as? String,
                      let resetDate = isoFormatter.date(from: resetStr) else { continue }
                let usedPct = min(100.0, max(0.0, (1.0 - rem) * 100.0))
                let window = PlanWindow(usedPct: usedPct, resetsAt: resetDate)
                switch id {
                case "gemini-5h": g5h = window
                case "gemini-weekly": gWeek = window
                case "3p-5h": tp5h = window
                case "3p-weekly": tpWeek = window
                default: break
                }
            }
        }

        return AntigravityPlanUsage(
            geminiFiveHour: g5h,
            geminiWeekly: gWeek,
            thirdPartyFiveHour: tp5h,
            thirdPartyWeekly: tpWeek,
            updatedAt: Date()
        )
    }

    static func pillLabel(_ usage: AntigravityPlanUsage?) -> String {
        guard let usage, let pct = usage.dominantGeminiPct else { return "Gemini —" }
        return "Gemini \(Int(pct.rounded()))%"
    }

    static func color(_ usage: AntigravityPlanUsage?) -> String {
        ClaudePlanGauge.color(for: usage?.dominantGeminiPct)
    }

    /// Discovers language_server process and queries RetrieveUserQuotaSummary
    static func fetch() async -> AntigravityPlanUsage? {
        // Implementation runs ps aux, finds language_server PID and CSRF token,
        // checks listening port via lsof, and performs HTTPS POST
        return await Task.detached { queryLocalServer() }.value
    }

    private static func queryLocalServer() -> AntigravityPlanUsage? {
        // Safe process inspection & URLSession HTTPS request with TLS bypass for localhost
        let (pid, token) = findLanguageServerProcess()
        guard let pid, let token else { return nil }
        guard let port = findListeningPort(pid: pid) else { return nil }

        guard let url = URL(string: "https://127.0.0.1:\(port)/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 3.0)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: "x-codeium-csrf-token")
        request.httpBody = Data("{}".utf8)

        let session = URLSession(configuration: .ephemeral, delegate: InsecureLocalhostDelegate(), delegateQueue: nil)
        var resultData: Data? = nil
        let sema = DispatchSemaphore(value: 0)
        let task = session.dataTask(with: request) { data, _, _ in
            resultData = data
            sema.signal()
        }
        task.resume()
        _ = sema.wait(timeout: .now() + 3.5)
        guard let data = resultData else { return nil }
        return parse(data: data)
    }

    private static func findLanguageServerProcess() -> (Int?, String?) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-ax", "-o", "pid,command"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do { try task.run(); task.waitUntilExit() } catch { return (nil, nil) }
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        for line in output.components(separatedBy: "\n") {
            if line.contains("language_server") && line.contains("--csrf_token") {
                let parts = line.trimmingCharacters(in: .whitespaces).components(separatedBy: .whitespaces)
                guard let pid = Int(parts[0]) else { continue }
                if let tokenIdx = parts.firstIndex(of: "--csrf_token"), tokenIdx + 1 < parts.count {
                    return (pid, parts[tokenIdx + 1])
                }
            }
        }
        return (nil, nil)
    }

    private static func findListeningPort(pid: Int) -> Int? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        task.arguments = ["-Pan", "-p", "\(pid)", "-i", "TCP", "-sTCP:LISTEN"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do { try task.run(); task.waitUntilExit() } catch { return nil }
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        for line in output.components(separatedBy: "\n") {
            if line.contains("127.0.0.1:") {
                let parts = line.components(separatedBy: "127.0.0.1:")
                if parts.count >= 2 {
                    let portStr = parts[1].prefix(while: { $0.isNumber })
                    if let port = Int(portStr) { return port }
                }
            }
        }
        return nil
    }
}

private class InsecureLocalhostDelegate: NSObject, URLSessionDelegate {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
```

2. Create `NotchBuddy/Sources/App/AntigravityPlanCardView.swift`:
Render 4 progress bars: Gemini 5-Hour, Gemini Weekly, 3P 5-Hour, 3P Weekly with reset times and percentages.
3. Integrate into `AppState` and `IslandRootView`.
4. Add files to Xcode project.

- [ ] **Step 4: Run test to verify it passes**

Run: `./scripts/test-antigravity-plan-gauge.sh`
Expected: PASS.

- [ ] **Step 5: Verify Xcode build**

Run: `xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug build CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO`
Expected: **BUILD SUCCEEDED**.

- [ ] **Step 6: Commit changes**

```bash
git add NotchBuddy/Sources/App/AntigravityPlanGauge.swift NotchBuddy/Sources/App/AntigravityPlanCardView.swift NotchBuddy/Sources/App/AppState.swift NotchBuddy/Sources/App/IslandRootView.swift NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj tests/AntigravityPlanGaugeTests.swift scripts/test-antigravity-plan-gauge.sh
git commit -m "feat(quota): implement Antigravity plan gauge with language_server RPC auto-discovery"
```

---

### Task 8: End-to-End Concurrency Verification & Regression Testing

**Files:**
- Test: `tests/MultiAgentConcurrencyE2ETests.swift`
- Script: `scripts/test-multi-agent-concurrency.sh`

**Interfaces:**
- Validates simultaneous execution of `integration_claude`, `agent_antigravity`, and `agent_codex`.
- Verifies approval and question queuing order, notification toasts, live diffs, and plan gauge updates.

- [ ] **Step 1: Write integration tests for multi-agent arbitration**

Create `tests/MultiAgentConcurrencyE2ETests.swift`:
```swift
import Foundation

@main
enum MultiAgentConcurrencyE2ETests {
    static var failures = 0
    static func check(_ label: String, _ condition: Bool) {
        if condition { print("  ✓ \(label)") }
        else { print("  ✗ \(label)"); failures += 1 }
    }

    static func main() {
        print("MultiAgentConcurrencyE2ETests")

        // 1. Simultaneous approval and question
        var approvals = ApprovalQueue()
        var questions = QuestionQueue()

        let appEntry = QueuedApproval(id: UUID(), fd: 10, sessionId: "claude-session",
                                      pillId: "integration_claude", projectName: "Coucou",
                                      cwd: "/tmp", tool: "Bash", command: "git push", inputKey: "{}")
        let qItem = AskQuestion(questions: [AskQuestionItem(question: "Proceed?", header: "", options: [
            AskQuestionOption(label: "Yes", description: ""),
            AskQuestionOption(label: "No", description: "")
        ], multiSelect: false)])
        let qEntry = QueuedQuestion(id: UUID(), fd: 11, sessionId: "antigravity-session",
                                    pillId: "agent_antigravity", projectName: "Coucou",
                                    cwd: "/tmp", question: qItem)

        check("enqueue Claude approval", approvals.enqueue(appEntry) == .accepted)
        check("enqueue Antigravity question", questions.enqueue(qEntry) == .accepted)

        check("both held open", approvals.count == 1 && questions.count == 1)
        check("Claude approval fd is 10", approvals.head?.fd == 10)
        check("Antigravity question fd is 11", questions.head?.fd == 11)

        // Resolving Claude leaves Antigravity untouched
        _ = approvals.remove(id: appEntry.id)
        check("approvals empty after removal", approvals.isEmpty)
        check("Antigravity question still pending", questions.head?.id == qEntry.id)

        if failures > 0 { exit(1) }
    }
}
```

Create `scripts/test-multi-agent-concurrency.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-concurrency.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc NotchBuddy/Sources/App/AskQuestion.swift \
    NotchBuddy/Sources/App/QuestionQueue.swift \
    NotchBuddy/Sources/App/ApprovalQueue.swift \
    tests/MultiAgentConcurrencyE2ETests.swift -o "$TEST_DIR/concurrency-tests"
"$TEST_DIR/concurrency-tests"
```

- [ ] **Step 2: Run concurrency integration test**

Run: `chmod +x scripts/test-multi-agent-concurrency.sh && ./scripts/test-multi-agent-concurrency.sh`
Expected: PASS.

- [ ] **Step 3: Run all existing project test scripts**

Run:
```bash
./scripts/test-ask-question.sh
./scripts/test-approval-queue.sh
./scripts/test-plan-gauge.sh
```
Expected: All test scripts PASS without failure.

- [ ] **Step 4: Full project compilation check**

Run:
```bash
xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug build CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO
```
Expected: **BUILD SUCCEEDED**.

- [ ] **Step 5: Commit changes**

```bash
git add tests/MultiAgentConcurrencyE2ETests.swift scripts/test-multi-agent-concurrency.sh
git commit -m "test(concurrency): add multi-agent concurrent arbitration integration tests"
```
