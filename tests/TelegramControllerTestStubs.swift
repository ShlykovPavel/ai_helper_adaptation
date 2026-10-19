import Foundation
import Combine

struct ApprovalInfo {
    var sessionId: String
    var tool: String
    var command: String
    var inputKey: String
    var pillId: String
    var id: UUID
}

@MainActor final class AppState: ObservableObject {
    static let shared = AppState()
    @Published var pendingApproval: ApprovalInfo?
    @Published var pendingQuestion: AskQuestion?
}

@MainActor final class HookServer {
    static let shared = HookServer()
    static let events = PassthroughSubject<TelegramEvent, Never>()
    func sendApprovalDecision(_ decision: String, for id: UUID?) {}
    func sendQuestionAnswers(_ answers: [String: Any]) {}
    func sendQuestionAsk() {}
}

@MainActor final class TelegramSettingsStore {
    static let shared = TelegramSettingsStore()
    var connectionStatus: TelegramConnectionStatus = .idle
}

final class KeychainStore: Sendable {
    static let shared = KeychainStore()
    func get(_ key: String) -> String? { nil }
}

enum Keychain {
    static func load(key: String) -> String? { nil }
}
