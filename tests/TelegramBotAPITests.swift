import Foundation

actor MockTelegramHTTPTransport: TelegramHTTPTransport {
    struct RequestRecord: @unchecked Sendable {
        let method: String
        let body: [String: Any]
    }

    private var _records: [RequestRecord] = []
    var responseProvider: (@Sendable (String, [String: Any]) throws -> [String: Any])?

    init(responseProvider: (@Sendable (String, [String: Any]) throws -> [String: Any])? = nil) {
        self.responseProvider = responseProvider
    }

    var records: [RequestRecord] { _records }
    var lastRecord: RequestRecord? { _records.last }

    func setResponseProvider(_ provider: (@Sendable (String, [String: Any]) throws -> [String: Any])?) {
        self.responseProvider = provider
    }

    func request(_ method: String, body: [String: Any]) async throws -> [String: Any] {
        _records.append(RequestRecord(method: method, body: body))
        if let provider = responseProvider {
            return try provider(method, body)
        }
        return ["ok": true, "result": [String: Any]()]
    }
}

@main struct TelegramAPITestRunner {
    static func main() async {
        await runTelegramBotAPITests()
        await runTelegramPollingTests()
    }
}

func runTelegramBotAPITests() async {
    // 1. getUpdates encoding with offset and timeout
    do {
        let mock = MockTelegramHTTPTransport { method, body in
            return [
                "ok": true,
                "result": [
                    [
                        "update_id": 1001,
                        "message": [
                            "message_id": 7,
                            "chat": ["id": 123456789, "type": "private"],
                            "from": ["id": 987654321, "is_bot": false, "first_name": "Test"],
                            "text": "/start pairNonceExample"
                        ]
                    ]
                ]
            ]
        }
        let api = TelegramBotAPI(transport: mock)
        let updates = try! await api.getUpdates(offset: 42, timeoutSeconds: 25)
        let last = await mock.lastRecord
        precondition(last?.method == "getUpdates")
        precondition(last?.body["offset"] as? Int64 == 42)
        precondition(last?.body["timeout"] as? Int == 25)
        precondition(last?.body["allowed_updates"] as? [String] == ["message", "callback_query"])
        precondition(updates.count == 1)
        precondition(updates[0].updateId == 1001)
        precondition(updates[0].message?.messageId == 7)
        precondition(updates[0].message?.chat.id == 123456789)
        precondition(updates[0].message?.chat.type == "private")
        precondition(updates[0].message?.from?.id == 987654321)
        precondition(updates[0].message?.text == "/start pairNonceExample")
    }

    // 2. getUpdates without offset
    do {
        let mock = MockTelegramHTTPTransport { _, _ in ["ok": true, "result": []] }
        let api = TelegramBotAPI(transport: mock)
        let updates = try! await api.getUpdates(offset: nil, timeoutSeconds: 25)
        let last = await mock.lastRecord
        precondition(updates.isEmpty)
        precondition(last?.body["offset"] == nil)
        precondition(last?.body["timeout"] as? Int == 25)
    }

    // 3. sendMessage produces inline keyboard and returns messageId
    do {
        let mock = MockTelegramHTTPTransport { method, body in
            return ["ok": true, "result": ["message_id": 88]]
        }
        let api = TelegramBotAPI(transport: mock)
        let kb = TelegramInlineKeyboard([
            [
                TelegramInlineKeyboardButton(text: "Allow", callbackData: "c:ref1:allow"),
                TelegramInlineKeyboardButton(text: "Deny", callbackData: "c:ref1:deny")
            ]
        ])
        let msgId = try! await api.sendMessage(chatId: 12345, text: "Action required", keyboard: kb)
        let last = await mock.lastRecord
        precondition(msgId == 88)
        precondition(last?.method == "sendMessage")
        precondition(last?.body["chat_id"] as? Int64 == 12345)
        precondition(last?.body["text"] as? String == "Action required")
        let replyMarkup = last?.body["reply_markup"] as? [String: Any]
        let inlineKb = replyMarkup?["inline_keyboard"] as? [[[String: Any]]]
        precondition(inlineKb?.count == 1)
        precondition(inlineKb?[0].count == 2)
        precondition(inlineKb?[0][0]["text"] as? String == "Allow")
        precondition(inlineKb?[0][0]["callback_data"] as? String == "c:ref1:allow")
        precondition(inlineKb?[0][1]["text"] as? String == "Deny")
        precondition(inlineKb?[0][1]["callback_data"] as? String == "c:ref1:deny")
    }

    // 4. sendMessage truncates text at 3,500 characters
    do {
        let mock = MockTelegramHTTPTransport { _, _ in ["ok": true, "result": ["message_id": 1]] }
        let api = TelegramBotAPI(transport: mock)
        let longText = String(repeating: "A", count: 4000)
        _ = try! await api.sendMessage(chatId: 10, text: longText, keyboard: nil)
        let last = await mock.lastRecord
        let sentText = last?.body["text"] as? String
        precondition(sentText?.count == 3500)
    }

    // 5. answerCallbackQuery encoding
    do {
        let mock = MockTelegramHTTPTransport { _, _ in ["ok": true, "result": true] }
        let api = TelegramBotAPI(transport: mock)
        try! await api.answerCallbackQuery(id: "cb_99", text: "Done", showAlert: true)
        let last = await mock.lastRecord
        precondition(last?.method == "answerCallbackQuery")
        precondition(last?.body["callback_query_id"] as? String == "cb_99")
        precondition(last?.body["text"] as? String == "Done")
        precondition(last?.body["show_alert"] as? Bool == true)
    }

    // 6. editMessage with text and keyboard
    do {
        let mock = MockTelegramHTTPTransport { _, _ in ["ok": true, "result": ["message_id": 42]] }
        let api = TelegramBotAPI(transport: mock)
        let kb = TelegramInlineKeyboard([[TelegramInlineKeyboardButton(text: "Updated", callbackData: "c:r:sel")]])
        try! await api.editMessage(chatId: 123, messageId: 42, text: "Resolved", keyboard: kb)
        let last = await mock.lastRecord
        precondition(last?.method == "editMessageText")
        precondition(last?.body["chat_id"] as? Int64 == 123)
        precondition(last?.body["message_id"] as? Int64 == 42)
        precondition(last?.body["text"] as? String == "Resolved")
        precondition(last?.body["reply_markup"] != nil)
    }

    // 7. editMessage with keyboard only (text == nil)
    do {
        let mock = MockTelegramHTTPTransport { _, _ in ["ok": true, "result": ["message_id": 42]] }
        let api = TelegramBotAPI(transport: mock)
        try! await api.editMessage(chatId: 123, messageId: 42, text: nil, keyboard: nil)
        let last = await mock.lastRecord
        precondition(last?.method == "editMessageReplyMarkup")
        precondition(last?.body["chat_id"] as? Int64 == 123)
        precondition(last?.body["message_id"] as? Int64 == 42)
    }

    // 8. deleteWebhook
    do {
        let mock = MockTelegramHTTPTransport { _, _ in ["ok": true, "result": true] }
        let api = TelegramBotAPI(transport: mock)
        try! await api.deleteWebhook(dropPendingUpdates: false)
        let last = await mock.lastRecord
        precondition(last?.method == "deleteWebhook")
        precondition(last?.body["drop_pending_updates"] as? Bool == false)
    }

    // 9. getMe returns TelegramBotIdentity
    do {
        let mock = MockTelegramHTTPTransport { _, _ in
            return [
                "ok": true,
                "result": [
                    "id": 999111,
                    "is_bot": true,
                    "first_name": "CoucouBot",
                    "username": "coucou_helper_bot"
                ]
            ]
        }
        let api = TelegramBotAPI(transport: mock)
        let me = try! await api.getMe()
        let last = await mock.lastRecord
        precondition(last?.method == "getMe")
        precondition(me.id == 999111)
        precondition(me.isBot == true)
        precondition(me.firstName == "CoucouBot")
        precondition(me.username == "coucou_helper_bot")
    }

    // 10. Typed errors mapping: 401, 409, 429
    do {
        let mock401 = MockTelegramHTTPTransport { _, _ in
            ["ok": false, "error_code": 401, "description": "Unauthorized"]
        }
        let api401 = TelegramBotAPI(transport: mock401)
        do {
            _ = try await api401.getMe()
            preconditionFailure("Expected 401 to throw")
        } catch let error as TelegramAPIError {
            precondition(error == .unauthorized)
        } catch {
            preconditionFailure("Unexpected error: \(error)")
        }

        let mock409 = MockTelegramHTTPTransport { _, _ in
            ["ok": false, "error_code": 409, "description": "Conflict: another getUpdates instance is active"]
        }
        let api409 = TelegramBotAPI(transport: mock409)
        do {
            _ = try await api409.getUpdates(offset: nil, timeoutSeconds: 25)
            preconditionFailure("Expected 409 to throw")
        } catch let error as TelegramAPIError {
            if case .conflict(let desc) = error {
                precondition(desc.contains("Conflict"))
            } else {
                preconditionFailure("Expected .conflict")
            }
        } catch {
            preconditionFailure("Unexpected error: \(error)")
        }

        let mock429 = MockTelegramHTTPTransport { _, _ in
            [
                "ok": false,
                "error_code": 429,
                "description": "Too Many Requests",
                "parameters": ["retry_after": 7]
            ]
        }
        let api429 = TelegramBotAPI(transport: mock429)
        do {
            _ = try await api429.getMe()
            preconditionFailure("Expected 429 to throw")
        } catch let error as TelegramAPIError {
            precondition(error == .rateLimited(retryAfter: 7))
        } catch {
            preconditionFailure("Unexpected error: \(error)")
        }
    }

    // 11. Token redaction: token is never exposed in error descriptions
    do {
        let secretToken = "123456789:AAF_SECRET_TOKEN_VALUE_XYZ"
        let rawError = "Request to https://api.telegram.org/bot\(secretToken)/getMe failed with bot123456789:AAF_SECRET_TOKEN_VALUE_XYZ"
        let sanitized = TelegramAPIError.sanitize(rawError, token: secretToken)
        precondition(!sanitized.contains(secretToken))
        precondition(!sanitized.contains("AAF_SECRET_TOKEN_VALUE_XYZ"))
        precondition(sanitized.contains("<redacted-token>"))

        let err = TelegramAPIError.badResponse(statusCode: 500, description: rawError)
        precondition(!err.description.contains(secretToken))
        precondition(!err.description.contains("AAF_SECRET_TOKEN_VALUE_XYZ"))
    }

    // 12. Fixtures decoding through TelegramBotAPI.getUpdates
    do {
        let fixtureFiles = [
            "tests/fixtures/telegram/get-updates-pairing.json",
            "tests/fixtures/telegram/get-updates-approval.json",
            "tests/fixtures/telegram/get-updates-question.json",
            "tests/fixtures/telegram/get-updates-foreign-chat.json"
        ]
        for path in fixtureFiles {
            let data = try! Data(contentsOf: URL(fileURLWithPath: path))
            let json = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
            let mock = MockTelegramHTTPTransport { _, _ in json }
            let api = TelegramBotAPI(transport: mock)
            let updates = try! await api.getUpdates(offset: nil, timeoutSeconds: 25)
            precondition(!updates.isEmpty, "Failed to decode updates from \(path)")
        }
    }

    // 13. URLSessionTelegramHTTPTransport real request formation and error mapping via MockURLProtocol
    do {
        final class MockURLProtocol: URLProtocol, @unchecked Sendable {
            nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

            override class func canInit(with request: URLRequest) -> Bool { true }
            override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

            override func startLoading() {
                guard let handler = Self.requestHandler else {
                    client?.urlProtocol(self, didFailWithError: NSError(domain: "MockURLProtocol", code: -1))
                    return
                }
                do {
                    let (response, data) = try handler(request)
                    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                    client?.urlProtocol(self, didLoad: data)
                    client?.urlProtocolDidFinishLoading(self)
                } catch {
                    client?.urlProtocol(self, didFailWithError: error)
                }
            }

            override func stopLoading() {}
        }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        let token = "SECRET_BOT_TOKEN_123"
        let transport = URLSessionTelegramHTTPTransport(token: token, session: session)

        // Test URL formation and header
        MockURLProtocol.requestHandler = { req in
            precondition(req.url?.absoluteString == "https://api.telegram.org/botSECRET_BOT_TOKEN_123/sendMessage")
            precondition(req.httpMethod == "POST")
            precondition(req.value(forHTTPHeaderField: "Content-Type") == "application/json")
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = try! JSONSerialization.data(withJSONObject: ["ok": true, "result": ["message_id": 999]])
            return (resp, data)
        }
        let res = try! await transport.request("sendMessage", body: ["chat_id": 1, "text": "hello"])
        precondition((res["result"] as? [String: Any])?["message_id"] as? Int == 999)

        // Test 401 via HTTPURLResponse
        MockURLProtocol.requestHandler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            let data = try! JSONSerialization.data(withJSONObject: ["ok": false, "error_code": 401, "description": "Unauthorized"])
            return (resp, data)
        }
        do {
            _ = try await transport.request("getMe", body: [:])
            preconditionFailure("Expected 401")
        } catch let err as TelegramAPIError {
            precondition(err == .unauthorized)
        } catch {
            preconditionFailure("Unexpected error")
        }

        // Test token redaction on network error
        MockURLProtocol.requestHandler = { req in
            throw NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut, userInfo: [
                NSLocalizedDescriptionKey: "Failed connecting to https://api.telegram.org/bot\(token)/getMe"
            ])
        }
        do {
            _ = try await transport.request("getMe", body: [:])
            preconditionFailure("Expected network error")
        } catch let err as TelegramAPIError {
            precondition(!err.description.contains(token))
            precondition(err.description.contains("<redacted-token>"))
        } catch {
            preconditionFailure("Unexpected error")
        }
    }

    print("TelegramBotAPITests: PASS")
}
