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
