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

        // Presentation Arbiter tests (R09)
        testQuestionThenApprovalThenResolveApprovalRestoresQuestion()
        testApprovalThenQuestionThenResolveQuestionKeepsApproval()

        if failures > 0 { exit(1) }
    }

    // MARK: - Presentation Arbiter (R09)

    enum IslandView: Equatable {
        case empty
        case overview
        case approval
        case question
        case note
    }

    enum IslandMode: Equatable {
        case hidden
        case compact
        case expanded
    }

    struct ApprovalInfo: Equatable {
        let id: UUID
        let sessionId: String
        let pillId: String
        let tool: String
        let command: String
        let inputKey: String
        var queueCount: Int
        let projectName: String
    }

    final class AppState {
        static let shared = AppState()
        var view: IslandView = .overview
        var mode: IslandMode = .compact
        var isPinned: Bool = false
        var focusId: String? = nil
        var pendingApproval: ApprovalInfo? = nil
        var pendingQuestion: AskQuestion? = nil

        func reset() {
            view = .overview
            mode = .compact
            isPinned = false
            focusId = nil
            pendingApproval = nil
            pendingQuestion = nil
        }
    }

    final class PresentationArbiter {
        var approvals = ApprovalQueue()
        var questions = QuestionQueue()
        var focusBeforeApproval: String? = nil
        var focusBeforeQuestion: String? = nil

        func expandIfNeeded(to view: IslandView) {
            let state = AppState.shared
            let isAlert: Bool
            switch view {
            case .approval, .question: isAlert = true
            default: isAlert = false
            }
            if state.mode == .expanded {
                if view == .approval || view == .question {
                    state.view = view
                } else if isAlert && state.pendingApproval == nil && state.pendingQuestion == nil {
                    state.view = view
                }
            } else if isAlert {
                state.view = view
                state.mode = .expanded
            }
        }

        func showApprovalHead() {
            let state = AppState.shared
            guard let head = approvals.head else { return }
            let isSameId = (state.pendingApproval?.id == head.id)
            if isSameId {
                if state.pendingApproval?.queueCount != approvals.count {
                    state.pendingApproval?.queueCount = approvals.count
                }
            } else {
                state.pendingApproval = ApprovalInfo(
                    id: head.id,
                    sessionId: head.sessionId,
                    pillId: head.pillId,
                    tool: head.tool,
                    command: head.command,
                    inputKey: head.inputKey,
                    queueCount: approvals.count,
                    projectName: head.projectName
                )
            }
            state.isPinned = true
            if focusBeforeApproval == nil { focusBeforeApproval = state.focusId }
            state.focusId = head.pillId
            expandIfNeeded(to: .approval)
        }

        func showQuestionHead() {
            if approvals.head != nil {
                showApprovalHead()
                return
            }
            let state = AppState.shared
            guard let head = questions.head else { return }
            let isSameId = (state.pendingQuestion?.id == head.id)
            if isSameId {
                if state.pendingQuestion?.queueCount != questions.count {
                    state.pendingQuestion?.queueCount = questions.count
                }
            } else {
                var q = head.question
                q.id = head.id
                q.pillId = head.pillId
                q.projectName = head.projectName
                q.queueIndex = 1
                q.queueCount = questions.count
                state.pendingQuestion = q
            }
            state.isPinned = true
            if focusBeforeQuestion == nil { focusBeforeQuestion = state.focusId }
            state.focusId = head.pillId
            expandIfNeeded(to: .question)
        }

        func enqueueApproval(_ a: QueuedApproval) {
            _ = approvals.enqueue(a)
            showApprovalHead()
        }

        func enqueueQuestion(_ q: QueuedQuestion) {
            _ = questions.enqueue(q)
            showQuestionHead()
        }

        func removeApproval(id: UUID) {
            guard let entry = approvals.remove(id: id) else { return }
            let state = AppState.shared
            if approvals.head != nil {
                showApprovalHead()
                return
            }
            state.pendingApproval = nil
            state.isPinned = false
            if let prev = focusBeforeApproval {
                focusBeforeApproval = nil
                if state.focusId == entry.pillId {
                    state.focusId = prev
                }
            }
            if questions.head != nil {
                showQuestionHead()
                return
            }
            state.view = .overview
        }

        func removeQuestion(id: UUID) {
            guard let entry = questions.remove(id: id) else { return }
            let state = AppState.shared
            if questions.isEmpty {
                state.pendingQuestion = nil
                if let prev = focusBeforeQuestion {
                    focusBeforeQuestion = nil
                    if state.focusId == entry.pillId {
                        state.focusId = prev
                    }
                }
            }
            if approvals.head != nil {
                showApprovalHead()
                return
            }
            if questions.head != nil {
                showQuestionHead()
                return
            }
            state.isPinned = false
            state.view = .overview
        }
    }

    static func testQuestionThenApprovalThenResolveApprovalRestoresQuestion() {
        let state = AppState.shared
        state.reset()
        state.focusId = "home"
        let arbiter = PresentationArbiter()

        let q1 = entry(1, session: "s-q1", pill: "agent_claude")
        arbiter.enqueueQuestion(q1)

        check("Q1: view is .question", state.view == .question)
        check("Q1: mode is .expanded", state.mode == .expanded)
        check("Q1: isPinned is true", state.isPinned == true)
        check("Q1: focusId is agent_claude", state.focusId == "agent_claude")
        check("Q1: pendingQuestion id matches q1", state.pendingQuestion?.id == q1.id)
        check("Q1: pendingApproval is nil", state.pendingApproval == nil)

        // Approval arrives and interrupts question
        let a1 = QueuedApproval(id: UUID(), fd: 10, sessionId: "s-a1", pillId: "agent_gemini",
                                projectName: "Proj", cwd: "/tmp", tool: "Bash", command: "git push", inputKey: "k")
        arbiter.enqueueApproval(a1)

        check("A1 arrives: view switched to .approval", state.view == .approval)
        check("A1 arrives: mode is .expanded", state.mode == .expanded)
        check("A1 arrives: isPinned is true", state.isPinned == true)
        check("A1 arrives: focusId switched to agent_gemini", state.focusId == "agent_gemini")
        check("A1 arrives: pendingApproval matches a1", state.pendingApproval?.id == a1.id)
        check("A1 arrives: pendingQuestion still stored", state.pendingQuestion?.id == q1.id)

        // Resolve approval A1 -> Q1 must be restored to view
        arbiter.removeApproval(id: a1.id)

        check("A1 resolved: view restored to .question", state.view == .question)
        check("A1 resolved: mode restored to .expanded", state.mode == .expanded)
        check("A1 resolved: isPinned restored to true", state.isPinned == true)
        check("A1 resolved: focusId restored to agent_claude", state.focusId == "agent_claude")
        check("A1 resolved: pendingApproval is nil", state.pendingApproval == nil)
        check("A1 resolved: pendingQuestion still matches q1", state.pendingQuestion?.id == q1.id)

        // Resolve question Q1 -> returns to overview and restores original focus "home"
        arbiter.removeQuestion(id: q1.id)

        check("Q1 resolved: view is .overview", state.view == .overview)
        check("Q1 resolved: isPinned is false", state.isPinned == false)
        check("Q1 resolved: focusId restored to home", state.focusId == "home")
        check("Q1 resolved: pendingQuestion is nil", state.pendingQuestion == nil)
        check("Q1 resolved: pendingApproval is nil", state.pendingApproval == nil)
    }

    static func testApprovalThenQuestionThenResolveQuestionKeepsApproval() {
        let state = AppState.shared
        state.reset()
        state.focusId = "home"
        let arbiter = PresentationArbiter()

        let a1 = QueuedApproval(id: UUID(), fd: 20, sessionId: "s-a1", pillId: "agent_gemini",
                                projectName: "Proj", cwd: "/tmp", tool: "Bash", command: "make", inputKey: "k")
        arbiter.enqueueApproval(a1)

        check("A1: view is .approval", state.view == .approval)
        check("A1: mode is .expanded", state.mode == .expanded)
        check("A1: isPinned is true", state.isPinned == true)
        check("A1: focusId is agent_gemini", state.focusId == "agent_gemini")
        check("A1: pendingApproval matches a1", state.pendingApproval?.id == a1.id)

        // Question Q1 arrives while A1 is active: approval priority keeps A1 on screen
        let q1 = entry(1, session: "s-q1", pill: "agent_claude")
        arbiter.enqueueQuestion(q1)

        check("Q1 queued behind A1: view remains .approval", state.view == .approval)
        check("Q1 queued behind A1: mode remains .expanded", state.mode == .expanded)
        check("Q1 queued behind A1: isPinned remains true", state.isPinned == true)
        check("Q1 queued behind A1: focusId remains agent_gemini", state.focusId == "agent_gemini")
        check("Q1 queued behind A1: pendingApproval matches a1", state.pendingApproval?.id == a1.id)
        check("Q1 queued behind A1: question count is 1", arbiter.questions.count == 1)

        // Q1 is answered/resolved (e.g. from Telegram or cancelled)
        arbiter.removeQuestion(id: q1.id)

        check("Q1 resolved while A1 waiting: view remains .approval", state.view == .approval)
        check("Q1 resolved while A1 waiting: mode remains .expanded", state.mode == .expanded)
        check("Q1 resolved while A1 waiting: isPinned remains true", state.isPinned == true)
        check("Q1 resolved while A1 waiting: focusId remains agent_gemini", state.focusId == "agent_gemini")
        check("Q1 resolved while A1 waiting: pendingApproval matches a1", state.pendingApproval?.id == a1.id)
        check("Q1 resolved while A1 waiting: pendingQuestion is nil", state.pendingQuestion == nil)

        // Finally A1 is resolved
        arbiter.removeApproval(id: a1.id)

        check("A1 resolved: view is .overview", state.view == .overview)
        check("A1 resolved: isPinned is false", state.isPinned == false)
        check("A1 resolved: focusId restored to home", state.focusId == "home")
        check("A1 resolved: pendingApproval is nil", state.pendingApproval == nil)
    }
}
