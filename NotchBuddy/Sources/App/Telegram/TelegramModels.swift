import Foundation

struct TelegramSettings: Codable, Equatable, Sendable {
    var enabled: Bool = false
    var notifyFinished: Bool = true
    var notifyQuestions: Bool = true
    var notifyApprovals: Bool = true
    var pairedChatId: Int64? = nil
    var pairedUserId: Int64? = nil
    var pairedBotUsername: String? = nil
}

enum TelegramActionKind: String, Codable, Equatable, Sendable {
    case approvalAllow, approvalDeny, questionSelect, questionSubmit, questionText, questionTerminal
}

struct TelegramAction: Equatable, Sendable {
    let ref: String
    let kind: TelegramActionKind
    let fingerprint: String
    let sessionId: String
    let expiresAt: Date
    let chatId: Int64
    let userId: Int64
    let messageId: Int64
}

enum TelegramActionRejection: Equatable, Sendable { case unauthorized, expired, consumed, unknown, fingerprintMismatch }
enum TelegramActionResult: Equatable, Sendable { case accepted(TelegramAction), rejected(TelegramActionRejection) }

protocol TelegramClock: Sendable { var now: Date { get } }
struct SystemTelegramClock: TelegramClock { var now: Date { Date() } }
struct FixedClock: TelegramClock { let now: Date }
