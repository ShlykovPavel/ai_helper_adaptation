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
        check("resolved contains q3 on Stop", resolved == [q3])

        let resolvedPostTool = q.resolved(byEvent: "PostToolUse", sessionId: "s3", pillId: "agent_antigravity")
        check("resolved contains q3 on PostToolUse", resolvedPostTool == [q3])

        let resolvedPostToolFailure = q.resolved(byEvent: "PostToolUseFailure", sessionId: "s3", pillId: "agent_antigravity")
        check("resolved contains q3 on PostToolUseFailure", resolvedPostToolFailure == [q3])

        let resolvedUnrelated = q.resolved(byEvent: "Notification", sessionId: "s3", pillId: "agent_antigravity")
        check("resolved empty on Notification", resolvedUnrelated.isEmpty)

        let codex = entry(4, session: "s4", pill: "agent_codex")
        _ = q.enqueue(codex)
        check("parallel Codex tool completion keeps question pending",
              q.resolved(byEvent: "PostToolUse", sessionId: "s4", pillId: "agent_codex").isEmpty)
        check("Codex session ending still clears question",
              q.resolved(byEvent: "Stop", sessionId: "s4", pillId: "agent_codex") == [codex])

        if failures > 0 { exit(1) }
    }
}
