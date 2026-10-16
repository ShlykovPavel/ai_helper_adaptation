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

// MARK: - Bot API Models

struct TelegramBotIdentity: Codable, Equatable, Sendable {
    let id: Int64
    let isBot: Bool
    let firstName: String
    let username: String?

    enum CodingKeys: String, CodingKey {
        case id
        case isBot = "is_bot"
        case firstName = "first_name"
        case username
    }

    init(id: Int64, isBot: Bool = true, firstName: String, username: String? = nil) {
        self.id = id
        self.isBot = isBot
        self.firstName = firstName
        self.username = username
    }
}

struct TelegramInlineKeyboardButton: Codable, Equatable, Sendable {
    let text: String
    let callbackData: String?
    let url: String?

    enum CodingKeys: String, CodingKey {
        case text
        case callbackData = "callback_data"
        case url
    }

    init(text: String, callbackData: String? = nil, url: String? = nil) {
        self.text = text
        self.callbackData = callbackData
        self.url = url
    }

    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = ["text": text]
        if let callbackData = callbackData {
            dict["callback_data"] = callbackData
        }
        if let url = url {
            dict["url"] = url
        }
        return dict
    }
}

struct TelegramInlineKeyboard: Codable, Equatable, Sendable {
    let inlineKeyboard: [[TelegramInlineKeyboardButton]]

    enum CodingKeys: String, CodingKey {
        case inlineKeyboard = "inline_keyboard"
    }

    init(inlineKeyboard: [[TelegramInlineKeyboardButton]]) {
        self.inlineKeyboard = inlineKeyboard
    }

    init(_ rows: [[TelegramInlineKeyboardButton]]) {
        self.inlineKeyboard = rows
    }

    func toDictionary() -> [String: Any] {
        return [
            "inline_keyboard": inlineKeyboard.map { row in
                row.map { $0.toDictionary() }
            }
        ]
    }
}

struct TelegramUser: Codable, Equatable, Sendable {
    let id: Int64
    let isBot: Bool?
    let firstName: String?
    let username: String?

    enum CodingKeys: String, CodingKey {
        case id
        case isBot = "is_bot"
        case firstName = "first_name"
        case username
    }

    init(id: Int64, isBot: Bool? = nil, firstName: String? = nil, username: String? = nil) {
        self.id = id
        self.isBot = isBot
        self.firstName = firstName
        self.username = username
    }
}

struct TelegramMessageChat: Codable, Equatable, Sendable {
    let id: Int64
    let type: String
    let title: String?
    let username: String?

    init(id: Int64, type: String, title: String? = nil, username: String? = nil) {
        self.id = id
        self.type = type
        self.title = title
        self.username = username
    }
}

struct TelegramMessage: Codable, Equatable, Sendable {
    let messageId: Int64
    let chat: TelegramMessageChat
    let from: TelegramUser?
    let text: String?

    enum CodingKeys: String, CodingKey {
        case messageId = "message_id"
        case chat
        case from
        case text
    }

    init(messageId: Int64, chat: TelegramMessageChat, from: TelegramUser? = nil, text: String? = nil) {
        self.messageId = messageId
        self.chat = chat
        self.from = from
        self.text = text
    }
}

struct TelegramCallbackQuery: Codable, Equatable, Sendable {
    let id: String
    let from: TelegramUser
    let message: TelegramMessage?
    let data: String?

    enum CodingKeys: String, CodingKey {
        case id
        case from
        case message
        case data
    }

    init(id: String, from: TelegramUser, message: TelegramMessage? = nil, data: String? = nil) {
        self.id = id
        self.from = from
        self.message = message
        self.data = data
    }
}

struct TelegramUpdate: Codable, Equatable, Sendable {
    let updateId: Int64
    let message: TelegramMessage?
    let callbackQuery: TelegramCallbackQuery?

    enum CodingKeys: String, CodingKey {
        case updateId = "update_id"
        case message
        case callbackQuery = "callback_query"
    }

    init(updateId: Int64, message: TelegramMessage? = nil, callbackQuery: TelegramCallbackQuery? = nil) {
        self.updateId = updateId
        self.message = message
        self.callbackQuery = callbackQuery
    }
}

enum TelegramConnectionStatus: Equatable, Sendable {
    case idle
    case polling
    case backoff(seconds: Int)
    case conflict
    case unauthorized
    case stopped
}

enum TelegramAPIError: Error, Equatable, Sendable, CustomStringConvertible {
    case unauthorized
    case forbidden(description: String)
    case conflict(description: String)
    case rateLimited(retryAfter: Int)
    case badResponse(statusCode: Int, description: String)
    case invalidResponse
    case networkError(String)

    var description: String {
        switch self {
        case .unauthorized:
            return "TelegramAPIError.unauthorized (401)"
        case .forbidden(let desc):
            return "TelegramAPIError.forbidden (403): \(Self.sanitize(desc))"
        case .conflict(let desc):
            return "TelegramAPIError.conflict (409): \(Self.sanitize(desc))"
        case .rateLimited(let retryAfter):
            return "TelegramAPIError.rateLimited (429): retry after \(retryAfter)s"
        case .badResponse(let status, let desc):
            return "TelegramAPIError.badResponse (\(status)): \(Self.sanitize(desc))"
        case .invalidResponse:
            return "TelegramAPIError.invalidResponse"
        case .networkError(let desc):
            return "TelegramAPIError.networkError: \(Self.sanitize(desc))"
        }
    }

    static func from(statusCode: Int, description: String, retryAfter: Int? = nil) -> TelegramAPIError {
        let cleanDesc = sanitize(description)
        switch statusCode {
        case 401:
            return .unauthorized
        case 403:
            return .forbidden(description: cleanDesc)
        case 409:
            return .conflict(description: cleanDesc)
        case 429:
            return .rateLimited(retryAfter: retryAfter ?? 1)
        default:
            return .badResponse(statusCode: statusCode, description: cleanDesc)
        }
    }

    static func sanitize(_ string: String, token: String? = nil) -> String {
        var result = string
        if let token = token, !token.isEmpty {
            result = result.replacingOccurrences(of: token, with: "<redacted-token>")
        }
        if let regex = try? NSRegularExpression(pattern: "bot[0-9]+:[a-zA-Z0-9_-]+", options: []) {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "bot<redacted-token>")
        }
        return result
    }
}
