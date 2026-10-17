import Foundation

protocol TelegramHTTPTransport: Sendable {
    func request(_ method: String, body: [String: Any]) async throws -> [String: Any]
}

final class URLSessionTelegramHTTPTransport: TelegramHTTPTransport, @unchecked Sendable {
    private let token: String
    private let baseURL: URL
    private let session: URLSession
    private let defaultTimeout: TimeInterval
    private let longPollTimeout: TimeInterval

    init(
        token: String,
        baseURL: URL? = nil,
        session: URLSession = .shared,
        defaultTimeout: TimeInterval = 10.0,
        longPollTimeout: TimeInterval = 25.0
    ) {
        self.token = token
        self.baseURL = baseURL ?? URL(string: "https://api.telegram.org/bot\(token)/")!
        self.session = session
        self.defaultTimeout = defaultTimeout
        self.longPollTimeout = longPollTimeout
    }

    func request(_ method: String, body: [String: Any]) async throws -> [String: Any] {
        guard let url = URL(string: method, relativeTo: baseURL) else {
            throw TelegramAPIError.networkError("Invalid URL for method \(method)")
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let timeout: TimeInterval
        if method == "getUpdates" {
            let timeoutSec = (body["timeout"] as? Int) ?? Int(longPollTimeout)
            timeout = max(TimeInterval(timeoutSec) + 5.0, longPollTimeout)
        } else {
            timeout = defaultTimeout
        }
        urlRequest.timeoutInterval = timeout

        do {
            urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        } catch {
            throw TelegramAPIError.networkError("Failed to serialize request: \(sanitize(error.localizedDescription))")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw TelegramAPIError.networkError(sanitize("\(error)"))
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TelegramAPIError.invalidResponse
        }

        let jsonObject: Any?
        do {
            jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            let rawString = String(data: data, encoding: .utf8) ?? ""
            let truncated = sanitize(String(rawString.prefix(200)))
            if httpResponse.statusCode == 401 {
                throw TelegramAPIError.unauthorized
            }
            throw TelegramAPIError.badResponse(
                statusCode: httpResponse.statusCode,
                description: "Invalid JSON: \(truncated)"
            )
        }

        guard let dict = jsonObject as? [String: Any] else {
            throw TelegramAPIError.invalidResponse
        }

        let isOk = (dict["ok"] as? Bool) ?? false
        let statusCode = httpResponse.statusCode

        if !isOk || statusCode >= 400 {
            let errCode = (dict["error_code"] as? Int) ?? statusCode
            let rawDesc = (dict["description"] as? String) ?? "Telegram API request failed"
            let desc = sanitize(String(rawDesc.prefix(200)))
            let parameters = dict["parameters"] as? [String: Any]
            let retryAfter = parameters?["retry_after"] as? Int

            throw TelegramAPIError.from(statusCode: errCode, description: desc, retryAfter: retryAfter)
        }

        return dict
    }

    private func sanitize(_ string: String) -> String {
        TelegramAPIError.sanitize(string, token: token)
    }
}

final class TelegramBotAPI: Sendable {
    private let transport: TelegramHTTPTransport

    init(transport: TelegramHTTPTransport) {
        self.transport = transport
    }

    init(token: String, session: URLSession = .shared) {
        self.transport = URLSessionTelegramHTTPTransport(token: token, session: session)
    }

    private func execute(_ method: String, body: [String: Any]) async throws -> [String: Any] {
        let response = try await transport.request(method, body: body)
        if let ok = response["ok"] as? Bool, !ok {
            let errorCode = (response["error_code"] as? Int) ?? (response["status"] as? Int) ?? 0
            let desc = (response["description"] as? String) ?? "Telegram API request failed"
            let parameters = response["parameters"] as? [String: Any]
            let retryAfter = parameters?["retry_after"] as? Int
            throw TelegramAPIError.from(statusCode: errorCode, description: desc, retryAfter: retryAfter)
        }
        return response
    }

    func getMe() async throws -> TelegramBotIdentity {
        let response = try await execute("getMe", body: [:])
        guard let result = response["result"] as? [String: Any] else {
            throw TelegramAPIError.invalidResponse
        }
        let data = try JSONSerialization.data(withJSONObject: result, options: [])
        return try JSONDecoder().decode(TelegramBotIdentity.self, from: data)
    }

    func getUpdates(offset: Int64? = nil, timeoutSeconds: Int = 25) async throws -> [TelegramUpdate] {
        var body: [String: Any] = [
            "timeout": timeoutSeconds,
            "allowed_updates": ["message", "callback_query"]
        ]
        if let offset = offset {
            body["offset"] = offset
        }
        let response = try await execute("getUpdates", body: body)
        guard let result = response["result"] as? [Any] else {
            throw TelegramAPIError.invalidResponse
        }
        let data = try JSONSerialization.data(withJSONObject: result, options: [])
        return try JSONDecoder().decode([TelegramUpdate].self, from: data)
    }

    func sendMessage(chatId: Int64, text: String, keyboard: TelegramInlineKeyboard? = nil) async throws -> Int64 {
        let safeText = String(text.prefix(3500))
        var body: [String: Any] = [
            "chat_id": chatId,
            "text": safeText
        ]
        if let keyboard = keyboard {
            body["reply_markup"] = keyboard.toDictionary()
        }
        let response = try await execute("sendMessage", body: body)
        guard let result = response["result"] as? [String: Any] else {
            throw TelegramAPIError.invalidResponse
        }
        if let n = result["message_id"] as? NSNumber {
            return n.int64Value
        } else if let n = result["message_id"] as? Int64 {
            return n
        } else if let n = result["message_id"] as? Int {
            return Int64(n)
        } else {
            throw TelegramAPIError.invalidResponse
        }
    }

    func answerCallbackQuery(id: String, text: String? = nil, showAlert: Bool = false) async throws {
        var body: [String: Any] = [
            "callback_query_id": id,
            "show_alert": showAlert
        ]
        if let text = text {
            body["text"] = String(text.prefix(3500))
        }
        _ = try await execute("answerCallbackQuery", body: body)
    }

    func editMessage(chatId: Int64, messageId: Int64, text: String? = nil, keyboard: TelegramInlineKeyboard? = nil) async throws {
        var body: [String: Any] = [
            "chat_id": chatId,
            "message_id": messageId
        ]
        if let keyboard = keyboard {
            body["reply_markup"] = keyboard.toDictionary()
        }
        let method: String
        if let text = text {
            method = "editMessageText"
            body["text"] = String(text.prefix(3500))
        } else {
            method = "editMessageReplyMarkup"
        }
        _ = try await execute(method, body: body)
    }

    func deleteWebhook(dropPendingUpdates: Bool = false) async throws {
        let body: [String: Any] = [
            "drop_pending_updates": dropPendingUpdates
        ]
        _ = try await execute("deleteWebhook", body: body)
    }
}
