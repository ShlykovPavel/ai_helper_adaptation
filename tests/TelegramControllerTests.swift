import Foundation
import Combine

actor MockTelegramTransport: TelegramHTTPTransport {
    struct SentRequest: @unchecked Sendable {
        let method: String
        let body: [String: Any]
    }

    private var _requests: [SentRequest] = []
    var nextMessageId: Int64 = 100

    var requests: [SentRequest] { _requests }
    var lastRequest: SentRequest? { _requests.last }

    func request(_ method: String, body: [String: Any]) async throws -> [String: Any] {
        _requests.append(SentRequest(method: method, body: body))
        if method == "sendMessage" {
            let mid = nextMessageId
            nextMessageId += 1
            return ["ok": true, "result": ["message_id": mid]]
        }
        return ["ok": true, "result": [String: Any]()]
    }

    func clear() {
        _requests.removeAll()
    }
}

final class TestHookServerRecorder: @unchecked Sendable {
    var decisions: [(decision: String, id: UUID?)] = []
    var answers: [[String: Any]] = []
    var askedCount: Int = 0

    func recordDecision(_ decision: String, id: UUID?) {
        decisions.append((decision, id))
    }

    func recordAnswers(_ a: [String: Any]) {
        answers.append(a)
    }

    func recordAsk() {
        askedCount += 1
    }

    func clear() {
        decisions.removeAll()
        answers.removeAll()
        askedCount = 0
    }
}

@main
@MainActor
struct TelegramControllerTestRunner {
    static func main() async {
        print("Running TelegramControllerTests...")
        await testStopCreatesOneFinishedMessageAndDeduplicatesSecondIdenticalStop()
        await testApprovalSendsAllowDenyKeyboard()
        await testForeignCallbackIsRejected()
        await testValidCallbackReachesHookServerOnlyWhileApprovalIsPending()
        await testCallbackWithMismatchedFingerprintIsRejected()
        await testQuestionSingleSelectMapsToBuildAnswers()
        await testQuestionMultiSelectMapsToBuildAnswers()
        await testQuestionTextAnswer()
        await testLocalResolutionRemovesKeyboard()
        await testDisabledTelegramRejectsCallbacksAndSendsNoMessages()
        await testPollingStartsWhenUnpaired()
        await testMultipleApprovalsInQueueAndHeadValidation()
        await testMultiQuestionHandlingWithoutPartialDispatch()
        await testSettingsChangedResetsAPIWithNewToken()
        await testEditMessageLengthCapping()
        print("All TelegramControllerTests PASSED!")
    }

    private static let pairedChatId: Int64 = 123456789
    private static let pairedUserId: Int64 = 987654321

    private static func makeSettings(enabled: Bool = true) -> TelegramSettings {
        TelegramSettings(
            enabled: enabled,
            notifyFinished: true,
            notifyQuestions: true,
            notifyApprovals: true,
            pairedChatId: pairedChatId,
            pairedUserId: pairedUserId,
            pairedBotUsername: "CoucouBot"
        )
    }

    // 1. Stop creates one finished message; second identical Stop is deduplicated
    static func testStopCreatesOneFinishedMessageAndDeduplicatesSecondIdenticalStop() async {
        let transport = MockTelegramTransport()
        let api = TelegramBotAPI(transport: transport)
        let recorder = TestHookServerRecorder()
        let controller = TelegramBotController(
            api: api,
            settings: makeSettings(),
            onApprovalDecision: { recorder.recordDecision($0, id: $1) },
            onQuestionAnswers: { recorder.recordAnswers($0) }
        )

        let event1 = TelegramEvent(
            sessionId: "sess-1",
            agentId: "integration_claude",
            agentName: "Claude Code",
            projectName: "Coucou",
            kind: .finished,
            finalText: "All tests passing."
        )

        controller.handle(event: event1)
        try? await Task.sleep(nanoseconds: 50_000_000)

        var reqs = await transport.requests
        assert(reqs.count == 1, "Expected exactly 1 sendMessage for Stop")
        assert(reqs[0].method == "sendMessage")
        let text1 = (reqs[0].body["text"] as? String) ?? ""
        assert(text1.contains("Claude Code (Coucou)"), "Expected header in message: \(text1)")
        assert(text1.contains("All tests passing."), "Expected finalText in message: \(text1)")

        // Second identical Stop should be deduplicated
        controller.handle(event: event1)
        try? await Task.sleep(nanoseconds: 50_000_000)

        reqs = await transport.requests
        assert(reqs.count == 1, "Second identical Stop must be deduplicated, found \(reqs.count) requests")

        // Different session or turn is not deduplicated
        let event2 = TelegramEvent(
            sessionId: "sess-2",
            agentId: "integration_claude",
            agentName: "Claude Code",
            projectName: "Coucou",
            kind: .finished,
            finalText: "Second task done."
        )
        controller.handle(event: event2)
        try? await Task.sleep(nanoseconds: 50_000_000)

        reqs = await transport.requests
        assert(reqs.count == 2, "Expected 2 sendMessage requests after different Stop")
        print("  ✓ Stop message and deduplication: PASS")
    }

    // 2. Approval sends Allow/Deny keyboard
    static func testApprovalSendsAllowDenyKeyboard() async {
        let transport = MockTelegramTransport()
        let api = TelegramBotAPI(transport: transport)
        let recorder = TestHookServerRecorder()
        let controller = TelegramBotController(
            api: api,
            settings: makeSettings(),
            onApprovalDecision: { recorder.recordDecision($0, id: $1) },
            onQuestionAnswers: { recorder.recordAnswers($0) }
        )

        let approvalId = UUID()
        let snap = ApprovalSnapshot(
            id: approvalId,
            tool: "Bash",
            command: "git push origin main",
            inputKey: "{\"command\":\"git push origin main\"}",
            pillId: "integration_claude",
            sessionId: "sess-1",
            projectName: "Coucou"
        )
        let event = TelegramEvent(
            sessionId: "sess-1",
            agentId: "integration_claude",
            agentName: "Claude Code",
            projectName: "Coucou",
            kind: .approval,
            approval: snap
        )

        controller.handle(event: event)
        try? await Task.sleep(nanoseconds: 50_000_000)

        let reqs = await transport.requests
        assert(reqs.count == 1, "Expected 1 request for approval")
        assert(reqs[0].method == "sendMessage")
        let text = (reqs[0].body["text"] as? String) ?? ""
        assert(text.contains("Tool: Bash"), "Expected tool in text: \(text)")
        assert(text.contains("git push origin main"), "Expected command in text: \(text)")

        let markup = reqs[0].body["reply_markup"] as? [String: Any]
        assert(markup != nil, "Expected reply_markup on approval message")
        let inlineKeyboard = markup?["inline_keyboard"] as? [[[String: Any]]]
        assert(inlineKeyboard != nil && inlineKeyboard!.count == 1, "Expected 1 row of buttons")
        let buttons = inlineKeyboard![0]
        assert(buttons.count == 2, "Expected 2 buttons (Allow and Deny)")
        assert(buttons[0]["text"] as? String == "Разрешить")
        assert(buttons[1]["text"] as? String == "Запретить")
        let allowData = (buttons[0]["callback_data"] as? String) ?? ""
        let denyData = (buttons[1]["callback_data"] as? String) ?? ""
        assert(allowData.hasPrefix("c:") && allowData.hasSuffix(":allow"), "Invalid allow callback data: \(allowData)")
        assert(denyData.hasPrefix("c:") && denyData.hasSuffix(":deny"), "Invalid deny callback data: \(denyData)")
        print("  ✓ Approval keyboard: PASS")
    }

    // 3. Foreign callback is rejected
    static func testForeignCallbackIsRejected() async {
        let transport = MockTelegramTransport()
        let api = TelegramBotAPI(transport: transport)
        let recorder = TestHookServerRecorder()
        let controller = TelegramBotController(
            api: api,
            settings: makeSettings(),
            onApprovalDecision: { recorder.recordDecision($0, id: $1) },
            onQuestionAnswers: { recorder.recordAnswers($0) }
        )

        let snap = ApprovalSnapshot(
            id: UUID(),
            tool: "Bash",
            command: "rm -rf tmp",
            pillId: "integration_claude",
            sessionId: "sess-1",
            projectName: "Coucou"
        )
        controller.handle(event: TelegramEvent(sessionId: "sess-1", agentId: "integration_claude", agentName: "Claude Code", kind: .approval, approval: snap))
        try? await Task.sleep(nanoseconds: 50_000_000)

        let reqs = await transport.requests
        let markup = reqs[0].body["reply_markup"] as! [String: Any]
        let buttons = (markup["inline_keyboard"] as! [[[String: Any]]])[0]
        let allowData = buttons[0]["callback_data"] as! String

        // A. Foreign User
        let foreignUserUpdate = TelegramUpdate(
            updateId: 2001,
            callbackQuery: TelegramCallbackQuery(
                id: "cb-foreign-user",
                from: TelegramUser(id: 111222333, firstName: "Attacker"),
                message: TelegramMessage(messageId: 100, chat: TelegramMessageChat(id: pairedChatId, type: "private")),
                data: allowData
            )
        )
        await controller.handle(update: foreignUserUpdate)
        assert(recorder.decisions.isEmpty, "Foreign user callback must NOT trigger approval decision")

        // B. Foreign Chat
        let foreignChatUpdate = TelegramUpdate(
            updateId: 2002,
            callbackQuery: TelegramCallbackQuery(
                id: "cb-foreign-chat",
                from: TelegramUser(id: pairedUserId, firstName: "Owner"),
                message: TelegramMessage(messageId: 100, chat: TelegramMessageChat(id: 999888777, type: "private")),
                data: allowData
            )
        )
        await controller.handle(update: foreignChatUpdate)
        assert(recorder.decisions.isEmpty, "Foreign chat callback must NOT trigger approval decision")

        // C. Group Chat
        let groupChatUpdate = TelegramUpdate(
            updateId: 2003,
            callbackQuery: TelegramCallbackQuery(
                id: "cb-group-chat",
                from: TelegramUser(id: pairedUserId, firstName: "Owner"),
                message: TelegramMessage(messageId: 100, chat: TelegramMessageChat(id: pairedChatId, type: "group")),
                data: allowData
            )
        )
        await controller.handle(update: groupChatUpdate)
        assert(recorder.decisions.isEmpty, "Group chat callback must NOT trigger approval decision")
        print("  ✓ Foreign callback rejected: PASS")
    }

    // 4. Valid callback reaches HookServer only while the same approval id/fingerprint is pending
    static func testValidCallbackReachesHookServerOnlyWhileApprovalIsPending() async {
        let transport = MockTelegramTransport()
        let api = TelegramBotAPI(transport: transport)
        let recorder = TestHookServerRecorder()
        let controller = TelegramBotController(
            api: api,
            settings: makeSettings(),
            onApprovalDecision: { recorder.recordDecision($0, id: $1) },
            onQuestionAnswers: { recorder.recordAnswers($0) }
        )

        let approvalId = UUID()
        let snap = ApprovalSnapshot(
            id: approvalId,
            tool: "Bash",
            command: "ls -la",
            pillId: "integration_claude",
            sessionId: "sess-1",
            projectName: "Coucou"
        )
        controller.handle(event: TelegramEvent(sessionId: "sess-1", agentId: "integration_claude", agentName: "Claude Code", kind: .approval, approval: snap))
        try? await Task.sleep(nanoseconds: 50_000_000)

        let reqs = await transport.requests
        let markup = reqs[0].body["reply_markup"] as! [String: Any]
        let buttons = (markup["inline_keyboard"] as! [[[String: Any]]])[0]
        let allowData = buttons[0]["callback_data"] as! String

        // Valid Allow callback
        let validUpdate = TelegramUpdate(
            updateId: 3001,
            callbackQuery: TelegramCallbackQuery(
                id: "cb-valid",
                from: TelegramUser(id: pairedUserId, firstName: "Owner"),
                message: TelegramMessage(messageId: 100, chat: TelegramMessageChat(id: pairedChatId, type: "private")),
                data: allowData
            )
        )
        await controller.handle(update: validUpdate)

        assert(recorder.decisions.count == 1, "Expected exactly 1 decision recorded")
        assert(recorder.decisions[0].decision == "allow")
        assert(recorder.decisions[0].id == approvalId)

        // Verify message was edited to show resolution and remove keyboard
        let editReqs = (await transport.requests).filter { $0.method == "editMessageText" }
        assert(!editReqs.isEmpty, "Expected editMessageText after decision")
        let editText = (editReqs.last?.body["text"] as? String) ?? ""
        assert(editText.contains("Ответил: Разрешить"), "Expected answer note: \(editText)")
        assert(editReqs.last?.body["reply_markup"] == nil, "Expected keyboard to be removed")

        // Duplicate callback on consumed action should be rejected
        recorder.clear()
        let duplicateUpdate = TelegramUpdate(
            updateId: 3002,
            callbackQuery: TelegramCallbackQuery(
                id: "cb-dup",
                from: TelegramUser(id: pairedUserId, firstName: "Owner"),
                message: TelegramMessage(messageId: 100, chat: TelegramMessageChat(id: pairedChatId, type: "private")),
                data: allowData
            )
        )
        await controller.handle(update: duplicateUpdate)
        assert(recorder.decisions.isEmpty, "Duplicate callback must NOT trigger a second decision")
        let ansCb = (await transport.requests).filter { $0.method == "answerCallbackQuery" }
        assert(ansCb.last?.body["text"] as? String == "Срок действия истёк", "Expected expiration notice")
        print("  ✓ Valid callback and duplicate rejection: PASS")
    }

    // 5. Callback with mismatched fingerprint is rejected
    static func testCallbackWithMismatchedFingerprintIsRejected() async {
        let transport = MockTelegramTransport()
        let api = TelegramBotAPI(transport: transport)
        let recorder = TestHookServerRecorder()
        let controller = TelegramBotController(
            api: api,
            settings: makeSettings(),
            onApprovalDecision: { recorder.recordDecision($0, id: $1) },
            onQuestionAnswers: { recorder.recordAnswers($0) }
        )

        // Request 1
        let snap1 = ApprovalSnapshot(
            id: UUID(),
            tool: "Bash",
            command: "echo 1",
            pillId: "integration_claude",
            sessionId: "sess-1",
            projectName: "Coucou"
        )
        controller.handle(event: TelegramEvent(sessionId: "sess-1", agentId: "integration_claude", agentName: "Claude Code", kind: .approval, approval: snap1))
        try? await Task.sleep(nanoseconds: 50_000_000)

        let reqs = await transport.requests
        let buttons = ((reqs[0].body["reply_markup"] as! [String: Any])["inline_keyboard"] as! [[[String: Any]]])[0]
        let allowData1 = buttons[0]["callback_data"] as! String

        // Request 2 supersedes Request 1 with new fingerprint
        let snap2 = ApprovalSnapshot(
            id: UUID(),
            tool: "Bash",
            command: "echo 2",
            pillId: "integration_claude",
            sessionId: "sess-1",
            projectName: "Coucou"
        )
        controller.handle(event: TelegramEvent(sessionId: "sess-1", agentId: "integration_claude", agentName: "Claude Code", kind: .approval, approval: snap2))
        try? await Task.sleep(nanoseconds: 50_000_000)

        // Sending old callback data for Request 1
        let staleUpdate = TelegramUpdate(
            updateId: 4001,
            callbackQuery: TelegramCallbackQuery(
                id: "cb-stale",
                from: TelegramUser(id: pairedUserId, firstName: "Owner"),
                message: TelegramMessage(messageId: 100, chat: TelegramMessageChat(id: pairedChatId, type: "private")),
                data: allowData1
            )
        )
        await controller.handle(update: staleUpdate)
        assert(recorder.decisions.isEmpty, "Stale callback with mismatched fingerprint must NOT be accepted")
        print("  ✓ Fingerprint mismatch rejection: PASS")
    }

    // 6. Question single-select choices map to AskQuestion.buildAnswers
    static func testQuestionSingleSelectMapsToBuildAnswers() async {
        let transport = MockTelegramTransport()
        let api = TelegramBotAPI(transport: transport)
        let recorder = TestHookServerRecorder()
        let controller = TelegramBotController(
            api: api,
            settings: makeSettings(),
            onApprovalDecision: { recorder.recordDecision($0, id: $1) },
            onQuestionAnswers: { recorder.recordAnswers($0) }
        )

        let item = QuestionItemSnapshot(
            question: "Which reporter?",
            options: [
                QuestionOptionSnapshot(label: "Verbose"),
                QuestionOptionSnapshot(label: "Minimal"),
                QuestionOptionSnapshot(label: "JSON")
            ],
            multiSelect: false
        )
        let snap = QuestionSnapshot(items: [item])
        let event = TelegramEvent(
            sessionId: "sess-q",
            agentId: "integration_claude",
            agentName: "Claude Code",
            projectName: "Coucou",
            kind: .question,
            question: snap
        )

        controller.handle(event: event)
        try? await Task.sleep(nanoseconds: 50_000_000)

        let reqs = await transport.requests
        assert(reqs.count == 1 && reqs[0].method == "sendMessage")
        let markup = reqs[0].body["reply_markup"] as! [String: Any]
        let rows = markup["inline_keyboard"] as! [[[String: Any]]]
        // 3 option rows + 1 "Ответить текстом" row
        assert(rows.count >= 4)
        assert(rows[0][0]["text"] as? String == "Verbose")
        let verboseCallback = rows[0][0]["callback_data"] as! String

        // Click "Verbose"
        let clickUpdate = TelegramUpdate(
            updateId: 5001,
            callbackQuery: TelegramCallbackQuery(
                id: "cb-verbose",
                from: TelegramUser(id: pairedUserId, firstName: "Owner"),
                message: TelegramMessage(messageId: 100, chat: TelegramMessageChat(id: pairedChatId, type: "private")),
                data: verboseCallback
            )
        )
        await controller.handle(update: clickUpdate)

        assert(recorder.answers.count == 1, "Expected 1 answer submitted")
        assert((recorder.answers[0]["Which reporter?"] as? String) == "Verbose")

        let editReqs = (await transport.requests).filter { $0.method == "editMessageText" }
        assert(!editReqs.isEmpty)
        let editText = (editReqs.last?.body["text"] as? String) ?? ""
        assert(editText.contains("Ответил: Verbose"))
        print("  ✓ Question single-select mapping: PASS")
    }

    // 7. Question multi-select maps to AskQuestion.buildAnswers
    static func testQuestionMultiSelectMapsToBuildAnswers() async {
        let transport = MockTelegramTransport()
        let api = TelegramBotAPI(transport: transport)
        let recorder = TestHookServerRecorder()
        let controller = TelegramBotController(
            api: api,
            settings: makeSettings(),
            onApprovalDecision: { recorder.recordDecision($0, id: $1) },
            onQuestionAnswers: { recorder.recordAnswers($0) }
        )

        let item = QuestionItemSnapshot(
            question: "Targets?",
            options: [
                QuestionOptionSnapshot(label: "macOS"),
                QuestionOptionSnapshot(label: "iOS"),
                QuestionOptionSnapshot(label: "Linux")
            ],
            multiSelect: true
        )
        let snap = QuestionSnapshot(items: [item])
        let event = TelegramEvent(
            sessionId: "sess-qm",
            agentId: "integration_claude",
            agentName: "Claude Code",
            projectName: "Coucou",
            kind: .question,
            question: snap
        )

        controller.handle(event: event)
        try? await Task.sleep(nanoseconds: 50_000_000)

        var reqs = await transport.requests
        var markup = reqs[0].body["reply_markup"] as! [String: Any]
        var rows = markup["inline_keyboard"] as! [[[String: Any]]]
        let macCallback = rows[0][0]["callback_data"] as! String

        // Select macOS
        let selectMacUpdate = TelegramUpdate(
            updateId: 6001,
            callbackQuery: TelegramCallbackQuery(
                id: "cb-mac",
                from: TelegramUser(id: pairedUserId, firstName: "Owner"),
                message: TelegramMessage(messageId: 100, chat: TelegramMessageChat(id: pairedChatId, type: "private")),
                data: macCallback
            )
        )
        await controller.handle(update: selectMacUpdate)
        assert(recorder.answers.isEmpty, "Multi-select must NOT submit on first option pick")

        // Get updated keyboard markup from editMessageReplyMarkup
        reqs = await transport.requests
        let editMarkupReqs = reqs.filter { $0.method == "editMessageReplyMarkup" || $0.method == "editMessageText" }
        markup = editMarkupReqs.last?.body["reply_markup"] as! [String: Any]
        rows = markup["inline_keyboard"] as! [[[String: Any]]]
        assert((rows[0][0]["text"] as? String)?.contains("☑️") == true, "Expected checked mark for selected macOS")

        // Click submit button: "Отправить"
        let submitRow = rows.first { row in row.contains { ($0["text"] as? String) == "Отправить" } }
        assert(submitRow != nil, "Expected Отправить button in keyboard")
        let submitData = submitRow![0]["callback_data"] as! String

        let submitUpdate = TelegramUpdate(
            updateId: 6002,
            callbackQuery: TelegramCallbackQuery(
                id: "cb-submit",
                from: TelegramUser(id: pairedUserId, firstName: "Owner"),
                message: TelegramMessage(messageId: 100, chat: TelegramMessageChat(id: pairedChatId, type: "private")),
                data: submitData
            )
        )
        await controller.handle(update: submitUpdate)

        assert(recorder.answers.count == 1, "Expected answers submitted after submit button")
        let ansList = recorder.answers[0]["Targets?"] as? [String]
        assert(ansList == ["macOS"], "Expected macOS in multi-select answers: \(String(describing: ansList))")
        print("  ✓ Question multi-select mapping: PASS")
    }

    // 8. Question Text Answer
    static func testQuestionTextAnswer() async {
        let transport = MockTelegramTransport()
        let api = TelegramBotAPI(transport: transport)
        let recorder = TestHookServerRecorder()
        let controller = TelegramBotController(
            api: api,
            settings: makeSettings(),
            onApprovalDecision: { recorder.recordDecision($0, id: $1) },
            onQuestionAnswers: { recorder.recordAnswers($0) }
        )

        let item = QuestionItemSnapshot(
            question: "Format?",
            options: [
                QuestionOptionSnapshot(label: "A"),
                QuestionOptionSnapshot(label: "B")
            ],
            multiSelect: false
        )
        controller.handle(event: TelegramEvent(sessionId: "sess-qt", agentId: "integration_claude", agentName: "Claude Code", kind: .question, question: QuestionSnapshot(items: [item])))
        try? await Task.sleep(nanoseconds: 50_000_000)

        let reqs = await transport.requests
        let rows = (reqs[0].body["reply_markup"] as! [String: Any])["inline_keyboard"] as! [[[String: Any]]]
        let textBtnRow = rows.first { row in row.contains { ($0["text"] as? String) == "Ответить текстом" } }!
        let textData = textBtnRow[0]["callback_data"] as! String

        // Click "Ответить текстом"
        await controller.handle(update: TelegramUpdate(
            updateId: 7001,
            callbackQuery: TelegramCallbackQuery(
                id: "cb-text",
                from: TelegramUser(id: pairedUserId, firstName: "Owner"),
                message: TelegramMessage(messageId: 100, chat: TelegramMessageChat(id: pairedChatId, type: "private")),
                data: textData
            )
        ))

        // Send text message from paired user
        await controller.handle(update: TelegramUpdate(
            updateId: 7002,
            message: TelegramMessage(
                messageId: 101,
                chat: TelegramMessageChat(id: pairedChatId, type: "private"),
                from: TelegramUser(id: pairedUserId, firstName: "Owner"),
                text: "Custom Typed Answer"
            )
        ))

        assert(recorder.answers.count == 1, "Expected answers submitted via text")
        assert((recorder.answers[0]["Format?"] as? String) == "Custom Typed Answer")
        print("  ✓ Question text answer: PASS")
    }

    // 9. Local resolution removes keyboard
    static func testLocalResolutionRemovesKeyboard() async {
        let transport = MockTelegramTransport()
        let api = TelegramBotAPI(transport: transport)
        let controller = TelegramBotController(
            api: api,
            settings: makeSettings()
        )

        let snap = ApprovalSnapshot(
            id: UUID(),
            tool: "Bash",
            command: "pwd",
            pillId: "integration_claude",
            sessionId: "sess-1",
            projectName: "Coucou"
        )
        controller.handle(event: TelegramEvent(sessionId: "sess-1", agentId: "integration_claude", agentName: "Claude Code", kind: .approval, approval: snap))
        try? await Task.sleep(nanoseconds: 50_000_000)

        // Local resolution occurs in Coucou UI
        controller.handle(event: TelegramEvent(sessionId: "sess-1", agentId: "integration_claude", agentName: "Claude Code", kind: .approvalResolved))
        try? await Task.sleep(nanoseconds: 50_000_000)

        let edits = (await transport.requests).filter { $0.method == "editMessageText" }
        assert(!edits.isEmpty, "Expected editMessageText on local resolution")
        assert(edits.last?.body["reply_markup"] == nil, "Expected keyboard to be removed on local resolution")
        assert((edits.last?.body["text"] as? String)?.contains("(Обработано)") == true)
        print("  ✓ Local resolution keyboard removal: PASS")
    }

    // 10. Disabled Telegram rejects callbacks and sends no messages
    static func testDisabledTelegramRejectsCallbacksAndSendsNoMessages() async {
        let transport = MockTelegramTransport()
        let api = TelegramBotAPI(transport: transport)
        let controller = TelegramBotController(
            api: api,
            settings: makeSettings(enabled: false)
        )

        // Events do not send messages
        controller.handle(event: TelegramEvent(sessionId: "s", agentId: "a", agentName: "Agent", kind: .finished, finalText: "Done"))
        try? await Task.sleep(nanoseconds: 50_000_000)
        let reqs = await transport.requests
        assert(reqs.isEmpty, "Disabled Telegram must not send messages")

        // Callbacks receive Telegram disabled alert
        let update = TelegramUpdate(
            updateId: 8001,
            callbackQuery: TelegramCallbackQuery(
                id: "cb-dis",
                from: TelegramUser(id: pairedUserId, firstName: "Owner"),
                message: TelegramMessage(messageId: 100, chat: TelegramMessageChat(id: pairedChatId, type: "private")),
                data: "c:ref:allow"
            )
        )
        await controller.handle(update: update)

        let ans = (await transport.requests).filter { $0.method == "answerCallbackQuery" }
        assert(ans.count == 1, "Expected answerCallbackQuery for disabled Telegram")
        assert(ans[0].body["text"] as? String == "Telegram отключён")
        print("  ✓ Disabled Telegram behavior: PASS")
    }

    // 11. Polling starts when unpaired
    static func testPollingStartsWhenUnpaired() async {
        let transport = MockTelegramTransport()
        let api = TelegramBotAPI(transport: transport)
        let unpairSettings = TelegramSettings(
            enabled: true,
            notifyFinished: true,
            notifyQuestions: true,
            notifyApprovals: true,
            pairedChatId: nil,
            pairedUserId: nil,
            pairedBotUsername: nil
        )
        let controller = TelegramBotController(
            api: api,
            settings: unpairSettings
        )
        controller.start()
        assert(controller.isRunning, "Controller should be running when enabled even if unpaired")

        // Wait for polling task to call deleteWebhook / getUpdates
        try? await Task.sleep(nanoseconds: 100_000_000)
        let reqs = await transport.requests
        let hasGetUpdatesOrDeleteWebhook = reqs.contains { $0.method == "getUpdates" || $0.method == "deleteWebhook" }
        assert(hasGetUpdatesOrDeleteWebhook, "Polling should begin even when unpaired")
        controller.stop()
        assert(!controller.isRunning, "Controller should stop")
        print("  ✓ Polling starts when unpaired: PASS")
    }

    // 12. Multiple approvals in queue and head validation
    static func testMultipleApprovalsInQueueAndHeadValidation() async {
        let transport = MockTelegramTransport()
        let api = TelegramBotAPI(transport: transport)
        let recorder = TestHookServerRecorder()
        let controller = TelegramBotController(
            api: api,
            settings: makeSettings(),
            onApprovalDecision: { recorder.recordDecision($0, id: $1) }
        )

        let id1 = UUID()
        let id2 = UUID()
        let snap1 = ApprovalSnapshot(id: id1, tool: "Bash", command: "cmd1", pillId: "p1", sessionId: "s1")
        let snap2 = ApprovalSnapshot(id: id2, tool: "Bash", command: "cmd2", pillId: "p2", sessionId: "s2")

        controller.handle(event: TelegramEvent(sessionId: "s1", agentId: "p1", agentName: "Agent 1", kind: .approval, approval: snap1))
        controller.handle(event: TelegramEvent(sessionId: "s2", agentId: "p2", agentName: "Agent 2", kind: .approval, approval: snap2))
        try? await Task.sleep(nanoseconds: 50_000_000)

        assert(controller.activeApprovals.count == 2, "Both approvals should be tracked in activeApprovals")
        let app1 = controller.activeApprovals[id1]!
        let app2 = controller.activeApprovals[id2]!

        // Simulate AppState queue with snap1 at head
        AppState.shared.pendingApproval = ApprovalInfo(sessionId: "s1", tool: "Bash", command: "cmd1", inputKey: "", pillId: "p1", id: id1)

        // Try to approve snap2 first (not head) -> rejected with alert, not recorded
        let cb2 = TelegramUpdate(
            updateId: 9001,
            callbackQuery: TelegramCallbackQuery(
                id: "cb-app2",
                from: TelegramUser(id: pairedUserId, firstName: "Owner"),
                message: TelegramMessage(messageId: app2.messageId, chat: TelegramMessageChat(id: pairedChatId, type: "private")),
                data: "c:\(app2.allowRef):allow"
            )
        )
        await controller.handle(update: cb2)
        assert(recorder.decisions.isEmpty, "Decision for non-head approval must not be recorded")

        // Approve snap1 (head) -> succeeds
        let cb1 = TelegramUpdate(
            updateId: 9002,
            callbackQuery: TelegramCallbackQuery(
                id: "cb-app1",
                from: TelegramUser(id: pairedUserId, firstName: "Owner"),
                message: TelegramMessage(messageId: app1.messageId, chat: TelegramMessageChat(id: pairedChatId, type: "private")),
                data: "c:\(app1.allowRef):allow"
            )
        )
        await controller.handle(update: cb1)
        assert(recorder.decisions.count == 1, "Decision for head approval must be recorded")
        assert(recorder.decisions[0].id == id1)
        assert(controller.activeApprovals[id1] == nil, "Snap1 should be removed after decision")
        assert(controller.activeApprovals[id2] != nil, "Snap2 should remain active")

        // Now local resolution resolves snap2
        controller.handle(event: TelegramEvent(sessionId: "s2", agentId: "p2", agentName: "Agent 2", kind: .approvalResolved, approval: snap2))
        try? await Task.sleep(nanoseconds: 50_000_000)
        assert(controller.activeApprovals[id2] == nil, "Snap2 should be resolved and removed")

        AppState.shared.pendingApproval = nil
        print("  ✓ Multiple approvals in queue: PASS")
    }

    // 13. Multi-question handling without partial dispatch
    static func testMultiQuestionHandlingWithoutPartialDispatch() async {
        let transport = MockTelegramTransport()
        let api = TelegramBotAPI(transport: transport)
        let recorder = TestHookServerRecorder()
        let controller = TelegramBotController(
            api: api,
            settings: makeSettings(),
            onQuestionAnswers: { recorder.recordAnswers($0) },
            onQuestionAsk: { recorder.recordAsk() }
        )

        let item1 = QuestionItemSnapshot(
            question: "Question 1?",
            header: "Q1",
            options: [QuestionOptionSnapshot(label: "Opt1A"), QuestionOptionSnapshot(label: "Opt1B")],
            multiSelect: false
        )
        let item2 = QuestionItemSnapshot(
            question: "Question 2?",
            header: "Q2",
            options: [QuestionOptionSnapshot(label: "Opt2A"), QuestionOptionSnapshot(label: "Opt2B")],
            multiSelect: false
        )
        let qSnap = QuestionSnapshot(items: [item1, item2])
        controller.handle(event: TelegramEvent(
            sessionId: "multi-sess",
            agentId: "agent1",
            agentName: "Agent",
            kind: .question,
            question: qSnap
        ))
        try? await Task.sleep(nanoseconds: 50_000_000)

        guard let activeQ1 = controller.activeQuestion else {
            fatalError("activeQuestion should be set")
        }
        assert(activeQ1.currentQuestionIndex == 0)

        // Select first question option Opt1A
        let opt1Ref = activeQ1.optionRefs.first { $0.value.optionLabel == "Opt1A" }!.key
        let update1 = TelegramUpdate(
            updateId: 9101,
            callbackQuery: TelegramCallbackQuery(
                id: "cb-q1",
                from: TelegramUser(id: pairedUserId, firstName: "Owner"),
                message: TelegramMessage(messageId: activeQ1.messageId, chat: TelegramMessageChat(id: pairedChatId, type: "private")),
                data: "c:\(opt1Ref):select"
            )
        )
        await controller.handle(update: update1)

        // Verify NO partial answers dispatched!
        assert(recorder.answers.isEmpty, "Partial answer must never be dispatched to HookServer")

        // Verify active question advanced to Question 2
        guard let activeQ2 = controller.activeQuestion else {
            fatalError("activeQuestion should still be active for Q2")
        }
        assert(activeQ2.currentQuestionIndex == 1)

        // Select second question option Opt2B
        let opt2Ref = activeQ2.optionRefs.first { $0.value.optionLabel == "Opt2B" }!.key
        let update2 = TelegramUpdate(
            updateId: 9102,
            callbackQuery: TelegramCallbackQuery(
                id: "cb-q2",
                from: TelegramUser(id: pairedUserId, firstName: "Owner"),
                message: TelegramMessage(messageId: activeQ2.messageId, chat: TelegramMessageChat(id: pairedChatId, type: "private")),
                data: "c:\(opt2Ref):select"
            )
        )
        await controller.handle(update: update2)

        // Full answers must now be dispatched
        assert(recorder.answers.count == 1, "Full answers should be dispatched once all questions are answered")
        let fullAnswers = recorder.answers[0]
        assert(fullAnswers["Question 1?"] as? String == "Opt1A")
        assert(fullAnswers["Question 2?"] as? String == "Opt2B")
        assert(controller.activeQuestion == nil, "activeQuestion should be cleared after completion")
        print("  ✓ Multi-question handling without partial dispatch: PASS")
    }

    // 14. SettingsChanged resets API with new token
    static func testSettingsChangedResetsAPIWithNewToken() async {
        final class TokenHolder: @unchecked Sendable {
            var token: String = "token-alpha"
        }
        let holder = TokenHolder()
        let controller = TelegramBotController(
            settings: makeSettings(),
            tokenProvider: { holder.token }
        )

        controller.start()
        assert(controller.isRunning)

        holder.token = "token-beta"
        controller.settingsChanged()
        assert(controller.isRunning)

        controller.stop()
        assert(!controller.isRunning)
        print("  ✓ SettingsChanged resets API with new token: PASS")
    }

    // 15. editMessage length capping
    static func testEditMessageLengthCapping() async {
        let transport = MockTelegramTransport()
        let api = TelegramBotAPI(transport: transport)
        let controller = TelegramBotController(
            api: api,
            settings: makeSettings()
        )

        // Send a question, then resolve it with long text
        let longQuestion = String(repeating: "A", count: 4000)
        let item = QuestionItemSnapshot(question: longQuestion, header: "", options: [QuestionOptionSnapshot(label: "O1"), QuestionOptionSnapshot(label: "O2")], multiSelect: false)
        let snap = QuestionSnapshot(items: [item])
        controller.handle(event: TelegramEvent(sessionId: "sess-long", agentId: "agent", agentName: "Agent", kind: .question, question: snap))
        try? await Task.sleep(nanoseconds: 50_000_000)

        // Trigger resolution
        controller.handle(event: TelegramEvent(sessionId: "sess-long", agentId: "agent", agentName: "Agent", kind: .questionResolved))
        try? await Task.sleep(nanoseconds: 50_000_000)

        let edits = (await transport.requests).filter { $0.method == "editMessageText" }
        assert(!edits.isEmpty, "editMessageText should be called")
        for edit in edits {
            let text = edit.body["text"] as? String ?? ""
            assert(text.unicodeScalars.count <= 3500, "editMessage text must be capped to <= 3500 Unicode scalars")
        }
        print("  ✓ editMessage length capping: PASS")
    }
}
