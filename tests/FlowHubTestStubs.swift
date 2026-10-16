import Foundation
import Combine

final class KeychainStore: @unchecked Sendable {
    static let shared = KeychainStore()
    private var store: [String: String] = [:]
    func get(_ key: String) -> String? { store[key] }
    func set(_ key: String, value: String) { store[key] = value }
    func remove(_ key: String) { store.removeValue(forKey: key) }
}

enum Keychain {
    static func load(key: String) -> String? { nil }
}

struct ApprovalInfo: Sendable {
    var sessionId: String
    var tool: String
    var command: String
    var inputKey: String
    var pillId: String
    var id: UUID = UUID()
    var queueCount: Int = 1
    var projectName: String? = nil
}

final class AppState: ObservableObject {
    static let shared = AppState()
    @Published var pendingApproval: ApprovalInfo? = nil
    @Published var pendingQuestion: AskQuestion? = nil
}

final class HookServer: @unchecked Sendable {
    static let shared = HookServer()
    static let events = PassthroughSubject<TelegramEvent, Never>()
    var lastApprovalDecision: String?
    var lastApprovalId: UUID?
    var lastQuestionAnswers: [String: Any]?

    func sendApprovalDecision(_ decision: String, for id: UUID? = nil) {
        lastApprovalDecision = decision
        lastApprovalId = id
    }

    func sendQuestionAnswers(_ answers: [String: Any]) {
        lastQuestionAnswers = answers
    }

    func sendQuestionAsk() {}
}
