import Foundation
import CoreGraphics

// Minimal stubs for standalone IslandTypes compilation
enum EyeShape: String { case pill }
struct IslandScreenGeometry { static let fallbackNotchWidth: CGFloat = 160 }

@main
enum MultiAgentConcurrencyE2ETests {
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
        print("=== MultiAgentConcurrencyE2ETests ===")

        testSimultaneousMultiAgentArrival()
        testFileDescriptorPreservation()
        testDualQueueDrainingAndOrder()
        testCrossQueueResolution()
        testEventBasedCleanup()
        testPillCatalogFirstClassWorkspaceAgents()

        if failures > 0 {
            print("\n❌ MultiAgentConcurrencyE2ETests FAILED with \(failures) error(s)")
            exit(1)
        }
        print("\n✅ MultiAgentConcurrencyE2ETests PASSED")
    }

    // MARK: - 1. Simultaneous Arrival of Requests from Multiple Agents
    static func testSimultaneousMultiAgentArrival() {
        print("\n--- 1. Simultaneous Multi-Agent Arrival ---")
        var approvals = ApprovalQueue()
        var questions = QuestionQueue()

        // 1. Claude Code approval request arrives
        let claudeApproval = QueuedApproval(
            id: UUID(),
            fd: 10,
            sessionId: "claude-session-101",
            pillId: "integration_claude",
            projectName: "Coucou",
            cwd: "/tmp/project",
            tool: "Bash",
            command: "git push origin main",
            inputKey: "{\"command\":\"git push origin main\"}"
        )
        let claudeRes = approvals.enqueue(claudeApproval)
        check("Claude approval enqueued successfully", claudeRes == .accepted)

        // 2. Antigravity interactive question arrives
        let agyQuestionItem = AskQuestionItem(
            question: "Which database migration strategy?",
            header: "Migration",
            options: [
                AskQuestionOption(label: "Flyway", description: "Automated Java/SQL migrations"),
                AskQuestionOption(label: "Liquibase", description: "XML/YAML migrations"),
                AskQuestionOption(label: "Raw SQL", description: "Manual run")
            ],
            multiSelect: false
        )
        let agyQuestion = AskQuestion(questions: [agyQuestionItem], pillId: "agent_antigravity", projectName: "Coucou")
        let agyEntry = QueuedQuestion(
            id: UUID(),
            fd: 11,
            sessionId: "agy-session-202",
            pillId: "agent_antigravity",
            projectName: "Coucou",
            cwd: "/tmp/project",
            question: agyQuestion
        )
        let agyRes = questions.enqueue(agyEntry)
        check("Antigravity question enqueued successfully", agyRes == .accepted)

        // 3. Codex approval request arrives
        let codexApproval = QueuedApproval(
            id: UUID(),
            fd: 12,
            sessionId: "codex-session-303",
            pillId: "agent_codex",
            projectName: "Coucou",
            cwd: "/tmp/project",
            tool: "Bash",
            command: "npm test",
            inputKey: "{\"command\":\"npm test\"}"
        )
        let codexRes = approvals.enqueue(codexApproval)
        check("Codex approval enqueued successfully", codexRes == .accepted)

        // Verify queue counts and presence
        check("ApprovalQueue contains exactly 2 approvals", approvals.count == 2)
        check("QuestionQueue contains exactly 1 question", questions.count == 1)
        check("ApprovalQueue head is Claude approval", approvals.head?.id == claudeApproval.id)
        check("QuestionQueue head is Antigravity question", questions.head?.id == agyEntry.id)
        check("ApprovalQueue contains mixed sources (Claude + Codex)", approvals.hasMixedSources)
        check("ApprovalQueue has entries for integration_claude", approvals.hasEntries(forPill: "integration_claude"))
        check("ApprovalQueue has entries for agent_codex", approvals.hasEntries(forPill: "agent_codex"))
        check("QuestionQueue has entries for agent_antigravity", questions.hasEntries(forPill: "agent_antigravity"))
    }

    // MARK: - 2. File Descriptor Preservation
    static func testFileDescriptorPreservation() {
        print("\n--- 2. File Descriptor Preservation ---")
        var approvals = ApprovalQueue()
        var questions = QuestionQueue()

        let claudeFD: Int32 = 21
        let agyFD: Int32 = 22
        let codexFD: Int32 = 23
        let cursorFD: Int32 = 24

        let claude = QueuedApproval(
            id: UUID(), fd: claudeFD, sessionId: "claude-sess",
            pillId: "integration_claude", projectName: "Coucou",
            cwd: "/tmp", tool: "Bash", command: "ls -la", inputKey: "{}"
        )
        let codex = QueuedApproval(
            id: UUID(), fd: codexFD, sessionId: "codex-sess",
            pillId: "agent_codex", projectName: "Coucou",
            cwd: "/tmp", tool: "Bash", command: "cargo build", inputKey: "{}"
        )
        let cursor = QueuedApproval(
            id: UUID(), fd: cursorFD, sessionId: "cursor-sess",
            pillId: "agent_cursor", projectName: "Coucou",
            cwd: "/tmp", tool: "Bash", command: "pytest", inputKey: "{}"
        )

        let agyItem = AskQuestion(questions: [AskQuestionItem(question: "Deploy?", header: "", options: [
            AskQuestionOption(label: "Yes", description: ""),
            AskQuestionOption(label: "No", description: "")
        ], multiSelect: false)])
        let agy = QueuedQuestion(
            id: UUID(), fd: agyFD, sessionId: "agy-sess",
            pillId: "agent_antigravity", projectName: "Coucou",
            cwd: "/tmp", question: agyItem
        )

        _ = approvals.enqueue(claude)
        _ = questions.enqueue(agy)
        _ = approvals.enqueue(codex)
        _ = approvals.enqueue(cursor)

        // Verify none of the file descriptors were overwritten, mutated, or lost
        check("Claude approval fd preserved (21)", approvals.entries[0].fd == claudeFD)
        check("Codex approval fd preserved (23)", approvals.entries[1].fd == codexFD)
        check("Cursor approval fd preserved (24)", approvals.entries[2].fd == cursorFD)
        check("Antigravity question fd preserved (22)", questions.entries[0].fd == agyFD)

        // Queue limits: verify full queue does not clobber existing entries or their FDs
        var smallQueue = ApprovalQueue()
        _ = smallQueue.enqueue(claude)
        _ = smallQueue.enqueue(codex)
        let overflow = QueuedApproval(
            id: UUID(), fd: 99, sessionId: "overflow",
            pillId: "integration_claude", projectName: "Coucou",
            cwd: "/tmp", tool: "Bash", command: "boom", inputKey: "{}"
        )
        let rejected = smallQueue.enqueue(overflow, maxPending: 2)
        check("Queue rejects beyond maxPending", rejected == .rejectedFull)
        check("Head fd preserved after rejected enqueue", smallQueue.head?.fd == claudeFD)
        check("Second fd preserved after rejected enqueue", smallQueue.entries[1].fd == codexFD)
    }

    // MARK: - 3. Dual Queue Draining & Order Preservation
    static func testDualQueueDrainingAndOrder() {
        print("\n--- 3. Dual Queue Draining and Order Preservation ---")
        var approvals = ApprovalQueue()
        var questions = QuestionQueue()

        let app1 = QueuedApproval(id: UUID(), fd: 31, sessionId: "s1", pillId: "integration_claude",
                                  projectName: "P", cwd: "/", tool: "Bash", command: "cmd1", inputKey: "{}")
        let app2 = QueuedApproval(id: UUID(), fd: 32, sessionId: "s2", pillId: "agent_codex",
                                  projectName: "P", cwd: "/", tool: "Bash", command: "cmd2", inputKey: "{}")
        let app3 = QueuedApproval(id: UUID(), fd: 33, sessionId: "s3", pillId: "agent_cursor",
                                  projectName: "P", cwd: "/", tool: "Bash", command: "cmd3", inputKey: "{}")

        _ = approvals.enqueue(app1)
        _ = approvals.enqueue(app2)
        _ = approvals.enqueue(app3)

        let q1Item = AskQuestion(questions: [AskQuestionItem(question: "Q1?", header: "", options: [
            AskQuestionOption(label: "A", description: ""),
            AskQuestionOption(label: "B", description: "")
        ], multiSelect: false)])
        let q2Item = AskQuestion(questions: [AskQuestionItem(question: "Q2?", header: "", options: [
            AskQuestionOption(label: "C", description: ""),
            AskQuestionOption(label: "D", description: "")
        ], multiSelect: false)])

        let q1 = QueuedQuestion(id: UUID(), fd: 41, sessionId: "qs1", pillId: "agent_antigravity",
                                projectName: "P", cwd: "/", question: q1Item)
        let q2 = QueuedQuestion(id: UUID(), fd: 42, sessionId: "qs2", pillId: "agent_antigravity",
                                projectName: "P", cwd: "/", question: q2Item)

        _ = questions.enqueue(q1)
        _ = questions.enqueue(q2)

        // Check positions
        check("app1 at position 1", approvals.position(of: app1.id) == 1)
        check("app2 at position 2", approvals.position(of: app2.id) == 2)
        check("app3 at position 3", approvals.position(of: app3.id) == 3)
        check("q1 at position 1", questions.position(of: q1.id) == 1)
        check("q2 at position 2", questions.position(of: q2.id) == 2)

        // Drain approvals FIFO
        let removedApp1 = approvals.remove(id: app1.id)
        check("Removed head app1", removedApp1?.id == app1.id)
        check("New head is app2", approvals.head?.id == app2.id)
        check("app2 now position 1", approvals.position(of: app2.id) == 1)
        check("app3 now position 2", approvals.position(of: app3.id) == 2)
        check("Questions untouched while draining approvals", questions.count == 2 && questions.head?.id == q1.id)

        let removedApp2 = approvals.remove(id: app2.id)
        check("Removed app2", removedApp2?.id == app2.id)
        check("New head is app3", approvals.head?.id == app3.id)

        let removedApp3 = approvals.remove(id: app3.id)
        check("Removed app3", removedApp3?.id == app3.id)
        check("ApprovalQueue empty", approvals.isEmpty)

        // Drain questions FIFO
        let removedQ1 = questions.remove(id: q1.id)
        check("Removed q1", removedQ1?.id == q1.id)
        check("New question head is q2", questions.head?.id == q2.id)
        check("q2 now position 1", questions.position(of: q2.id) == 1)

        let removedQ2 = questions.remove(id: q2.id)
        check("Removed q2", removedQ2?.id == q2.id)
        check("QuestionQueue empty", questions.isEmpty)
    }

    // MARK: - 4. Cross-Queue Resolution
    static func testCrossQueueResolution() {
        print("\n--- 4. Cross-Queue Resolution ---")
        var approvals = ApprovalQueue()
        var questions = QuestionQueue()

        let claudeApp = QueuedApproval(
            id: UUID(), fd: 51, sessionId: "claude-session-cross",
            pillId: "integration_claude", projectName: "Coucou",
            cwd: "/tmp", tool: "Bash", command: "make test", inputKey: "{}"
        )
        let agyQuestion = QueuedQuestion(
            id: UUID(), fd: 52, sessionId: "agy-session-cross",
            pillId: "agent_antigravity", projectName: "Coucou",
            cwd: "/tmp", question: AskQuestion(questions: [
                AskQuestionItem(question: "Overwrite file?", header: "", options: [
                    AskQuestionOption(label: "Yes", description: ""),
                    AskQuestionOption(label: "No", description: "")
                ], multiSelect: false)
            ])
        )

        _ = approvals.enqueue(claudeApp)
        _ = questions.enqueue(agyQuestion)

        check("Approvals count is 1 before cross-queue resolution", approvals.count == 1)
        check("Questions count is 1 before cross-queue resolution", questions.count == 1)

        // Resolving Claude approval (e.g. user clicks Allow)
        let resolvedClaude = approvals.remove(id: claudeApp.id)
        check("Claude approval removed", resolvedClaude?.id == claudeApp.id)
        check("Approvals queue is now empty", approvals.isEmpty)

        // Crucial requirement: Antigravity question must remain completely intact at head!
        check("Antigravity question remains in queue", !questions.isEmpty)
        check("Antigravity question remains head", questions.head?.id == agyQuestion.id)
        check("Antigravity question fd preserved (52)", questions.head?.fd == 52)
        check("Antigravity question sessionId preserved", questions.head?.sessionId == "agy-session-cross")
        check("Antigravity question prompt text preserved", questions.head?.question.questions[0].question == "Overwrite file?")

        // Now resolving Antigravity question
        let resolvedAgy = questions.remove(id: agyQuestion.id)
        check("Antigravity question removed", resolvedAgy?.id == agyQuestion.id)
        check("Both queues empty after cross-queue completion", approvals.isEmpty && questions.isEmpty)
    }

    // MARK: - 5. Event-Based Cleanup
    static func testEventBasedCleanup() {
        print("\n--- 5. Event-Based Cleanup ---")
        var approvals = ApprovalQueue()
        var questions = QuestionQueue()

        let s1 = "session-alpha"
        let s2 = "session-beta"

        // Setup approvals for s1 and s2
        let app1 = QueuedApproval(
            id: UUID(), fd: 61, sessionId: s1, pillId: "integration_claude",
            projectName: "P", cwd: "/", tool: "Bash", command: "git status",
            inputKey: "{\"cmd\":\"git status\"}"
        )
        let app2 = QueuedApproval(
            id: UUID(), fd: 62, sessionId: s2, pillId: "agent_codex",
            projectName: "P", cwd: "/", tool: "Bash", command: "cargo check",
            inputKey: "{\"cmd\":\"cargo check\"}"
        )
        _ = approvals.enqueue(app1)
        _ = approvals.enqueue(app2)

        // Setup questions for s1 and s2
        let q1 = QueuedQuestion(
            id: UUID(), fd: 71, sessionId: s1, pillId: "integration_claude",
            projectName: "P", cwd: "/",
            question: AskQuestion(questions: [AskQuestionItem(question: "Q1?", header: "", options: [
                AskQuestionOption(label: "1", description: ""),
                AskQuestionOption(label: "2", description: "")
            ], multiSelect: false)])
        )
        let q2 = QueuedQuestion(
            id: UUID(), fd: 72, sessionId: s2, pillId: "agent_antigravity",
            projectName: "P", cwd: "/",
            question: AskQuestion(questions: [AskQuestionItem(question: "Q2?", header: "", options: [
                AskQuestionOption(label: "A", description: ""),
                AskQuestionOption(label: "B", description: "")
            ], multiSelect: false)])
        )
        _ = questions.enqueue(q1)
        _ = questions.enqueue(q2)

        // 1. PostToolUse on s1 for Claude
        let ptResolvedApps = approvals.resolved(
            byEvent: "PostToolUse", sessionId: s1, pillId: "integration_claude",
            tool: "Bash", inputKey: "{\"cmd\":\"git status\"}"
        )
        check("PostToolUse matches app1 in approvals", ptResolvedApps == [app1])

        let ptResolvedQuestions = questions.resolved(
            byEvent: "PostToolUse", sessionId: s1, pillId: "integration_claude"
        )
        check("PostToolUse matches q1 in questions", ptResolvedQuestions == [q1])

        // Verify s2 items are NOT resolved by s1 events
        let s2StopOnAgy = questions.resolved(byEvent: "Stop", sessionId: s2, pillId: "agent_antigravity")
        check("Stop matches q2 for Antigravity on session s2", s2StopOnAgy == [q2])

        let s2SessionEndOnCodex = approvals.resolved(
            byEvent: "SessionEnd", sessionId: s2, pillId: "agent_codex",
            tool: "", inputKey: ""
        )
        check("SessionEnd matches app2 for Codex on session s2", s2SessionEndOnCodex == [app2])

        // Verify mismatched events do not trigger resolution
        let noMatchEvent = questions.resolved(byEvent: "Notification", sessionId: s2, pillId: "agent_antigravity")
        check("Unrelated event does not resolve questions", noMatchEvent.isEmpty)

        let wrongPillApp = approvals.resolved(
            byEvent: "Stop", sessionId: s1, pillId: "agent_antigravity",
            tool: "", inputKey: ""
        )
        check("Wrong pill does not resolve approvals", wrongPillApp.isEmpty)
    }

    // MARK: - 6. PillCatalog First-Class Workspace Agents Integration
    static func testPillCatalogFirstClassWorkspaceAgents() {
        print("\n--- 6. PillCatalog First-Class Workspace Agents ---")

        let firstClassPills = [
            ("agent_antigravity", "Antigravity", "Antigravity", PillCategory.workspace, true),
            ("agent_codex", "Codex", "Codex", PillCategory.workspace, true),
            ("integration_claude", "VS Code", "Claude Code", PillCategory.workspace, false),
            ("agent_cursor", "Cursor", "Cursor", PillCategory.workspace, false)
        ]

        for (id, name, sessionSubtitle, category, isGithubOnly) in firstClassPills {
            let def = PillCatalog.definition(for: id)
            check("PillCatalog contains '\(id)'", def != nil)
            guard let def else { continue }

            check("'\(id)' name is '\(name)'", def.name == name)
            check("'\(id)' sessionSubtitle is '\(sessionSubtitle)'", def.sessionSubtitle == sessionSubtitle)
            check("'\(id)' category is .workspace", def.category == category)
            check("'\(id)' githubOnly is \(isGithubOnly)", def.githubOnly == isGithubOnly)
            check("'\(id)' defaultColor is valid hex format", def.defaultColor.hasPrefix("#") && def.defaultColor.count == 7)
            check("'\(id)' color is valid hex format", def.color.hasPrefix("#") && def.color.count == 7)
        }

        // Verify defaultMainPillId
        check("defaultMainPillId is integration_claude", PillCatalog.defaultMainPillId == "integration_claude")

        // Verify all first-class agents exist in PillCatalog.all
        let allIds = PillCatalog.all.map { $0.id }
        check("PillCatalog.all contains agent_antigravity", allIds.contains("agent_antigravity"))
        check("PillCatalog.all contains agent_codex", allIds.contains("agent_codex"))
        check("PillCatalog.all contains integration_claude", allIds.contains("integration_claude"))
        check("PillCatalog.all contains agent_cursor", allIds.contains("agent_cursor"))

        // Verify in PillCatalog.available (non-AppStore build)
        let availableIds = PillCatalog.available.map { $0.id }
        check("PillCatalog.available contains agent_antigravity", availableIds.contains("agent_antigravity"))
        check("PillCatalog.available contains agent_codex", availableIds.contains("agent_codex"))
        check("PillCatalog.available contains integration_claude", availableIds.contains("integration_claude"))
        check("PillCatalog.available contains agent_cursor", availableIds.contains("agent_cursor"))
    }
}
