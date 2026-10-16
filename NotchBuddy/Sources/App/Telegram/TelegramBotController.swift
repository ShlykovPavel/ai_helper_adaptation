import Foundation
import Combine

@MainActor
final class TelegramBotController {
    static let shared = TelegramBotController()

    // MARK: - Internal Active State Types

    struct ActiveApprovalContext {
        let id: UUID?
        let fingerprint: String
        let sessionId: String
        let chatId: Int64
        let messageId: Int64
        let promptText: String
    }

    struct ActiveQuestionContext {
        let fingerprint: String
        let sessionId: String
        let items: [AskQuestionItem]
        var selections: [[String]]
        let chatId: Int64
        let messageId: Int64
        let promptText: String
        var awaitingText: Bool
        var optionRefs: [String: (questionIndex: Int, optionLabel: String)]
        var submitRef: String?
        var textRef: String?
        var terminalRef: String?
    }

    // MARK: - Properties

    private(set) var isRunning: Bool = false
    private var polling: TelegramPolling?
    private var api: TelegramBotAPI?
    private let registry: TelegramActionRegistry

    private let settingsProvider: @Sendable () -> TelegramSettings
    private let tokenProvider: @Sendable () -> String?
    private let onApprovalDecision: (@MainActor (String, UUID?) -> Void)?
    private let onQuestionAnswers: (@MainActor ([String: Any]) -> Void)?
    private let onQuestionAsk: (@MainActor () -> Void)?
    private let clock: any TelegramClock

    private var cancellables = Set<AnyCancellable>()

    private(set) var activeApproval: ActiveApprovalContext?
    private(set) var activeQuestion: ActiveQuestionContext?

    private var lastFinishedKey: String?

    // MARK: - Init

    init(
        api: TelegramBotAPI? = nil,
        polling: TelegramPolling? = nil,
        registry: TelegramActionRegistry? = nil,
        settings: TelegramSettings? = nil,
        settingsProvider: (@Sendable () -> TelegramSettings)? = nil,
        tokenProvider: (@Sendable () -> String?)? = nil,
        onApprovalDecision: (@MainActor (String, UUID?) -> Void)? = nil,
        onQuestionAnswers: (@MainActor ([String: Any]) -> Void)? = nil,
        onQuestionAsk: (@MainActor () -> Void)? = nil,
        clock: any TelegramClock = SystemTelegramClock()
    ) {
        self.api = api
        self.polling = polling
        self.clock = clock
        self.registry = registry ?? TelegramActionRegistry(clock: clock)

        if let settings = settings {
            self.settingsProvider = { settings }
        } else if let sp = settingsProvider {
            self.settingsProvider = sp
        } else {
            self.settingsProvider = { Self.loadDefaultSettings() }
        }

        if let tp = tokenProvider {
            self.tokenProvider = tp
        } else {
            self.tokenProvider = { Self.loadDefaultToken() }
        }

        if let onApproval = onApprovalDecision {
            self.onApprovalDecision = onApproval
        } else {
            self.onApprovalDecision = { decision, id in
                HookServer.shared.sendApprovalDecision(decision, for: id)
            }
        }

        if let onAnswers = onQuestionAnswers {
            self.onQuestionAnswers = onAnswers
        } else {
            self.onQuestionAnswers = { answers in
                HookServer.shared.sendQuestionAnswers(answers)
            }
        }

        if let onAsk = onQuestionAsk {
            self.onQuestionAsk = onAsk
        } else {
            self.onQuestionAsk = {
                HookServer.shared.sendQuestionAsk()
            }
        }
    }

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true

        let currentSettings = settingsProvider()
        guard currentSettings.enabled else { return }

        if api == nil, let token = tokenProvider(), !token.isEmpty {
            api = TelegramBotAPI(token: token)
        }

        if let api = api, currentSettings.pairedChatId != nil {
            if polling == nil {
                polling = TelegramPolling(api: api) { [weak self] update in
                    await self?.handle(update: update)
                }
            }
            Task { [weak self] in
                await self?.polling?.start()
            }
        }

        // Subscribe to HookServer events
        HookServer.events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.handle(event: event)
            }
            .store(in: &cancellables)

        // Observe AppState pending approval / question clearing for local resolution
        AppState.shared.$pendingApproval
            .receive(on: DispatchQueue.main)
            .sink { [weak self] pending in
                guard let self = self else { return }
                if pending == nil && self.activeApproval != nil {
                    self.handle(event: TelegramEvent(
                        sessionId: "",
                        agentId: "",
                        agentName: "",
                        kind: .approvalResolved
                    ))
                }
            }
            .store(in: &cancellables)

        AppState.shared.$pendingQuestion
            .receive(on: DispatchQueue.main)
            .sink { [weak self] pending in
                guard let self = self else { return }
                if pending == nil && self.activeQuestion != nil {
                    self.handle(event: TelegramEvent(
                        sessionId: "",
                        agentId: "",
                        agentName: "",
                        kind: .questionResolved
                    ))
                }
            }
            .store(in: &cancellables)
    }

    func stop() {
        cancellables.removeAll()
        if let p = polling {
            Task {
                await p.stop()
            }
        }
        polling = nil
        isRunning = false
        activeApproval = nil
        activeQuestion = nil
    }

    func settingsChanged() {
        stop()
        start()
    }

    // MARK: - Event Handling (from macOS Hooks)

    func handle(event: TelegramEvent) {
        let settings = settingsProvider()
        guard settings.enabled else { return }
        guard let chatId = settings.pairedChatId else { return }

        switch event.kind {
        case .finished:
            guard settings.notifyFinished else { return }
            // Deduplication: Stop creates one finished message; second identical Stop is deduplicated
            let dedupeKey = "\(event.sessionId):\((event.projectName ?? "")):\(event.finalText ?? "")"
            if dedupeKey == lastFinishedKey {
                return
            }
            lastFinishedKey = dedupeKey

            let projectPart = event.projectName.map { " (\($0))" } ?? ""
            let header = "✅ \(event.agentName)\(projectPart)"
            let text: String
            if let final = event.finalText, !final.isEmpty {
                text = "\(header)\n\(final)"
            } else {
                text = header
            }
            let safeText = Self.capText(text)
            Task { [weak self] in
                try? await self?.api?.sendMessage(chatId: chatId, text: safeText)
            }

        case .error:
            let projectPart = event.projectName.map { " (\($0))" } ?? ""
            let header = "❌ \(event.agentName)\(projectPart)"
            let text: String
            if let final = event.finalText, !final.isEmpty {
                text = "\(header)\n\(final)"
            } else {
                text = header
            }
            let safeText = Self.capText(text)
            Task { [weak self] in
                try? await self?.api?.sendMessage(chatId: chatId, text: safeText)
            }

        case .approval:
            guard settings.notifyApprovals else { return }
            guard let approval = event.approval else { return }
            guard let userId = settings.pairedUserId else { return }

            Task { [weak self] in
                guard let self = self, let api = self.api else { return }
                let allowAction = await self.registry.insert(
                    kind: .approvalAllow,
                    fingerprint: approval.fingerprint,
                    sessionId: approval.sessionId,
                    chatId: chatId,
                    userId: userId
                )
                let denyAction = await self.registry.insert(
                    kind: .approvalDeny,
                    fingerprint: approval.fingerprint,
                    sessionId: approval.sessionId,
                    chatId: chatId,
                    userId: userId
                )

                let projectPart = event.projectName.map { " (\($0))" } ?? ""
                let header = "⚠️ \(event.agentName)\(projectPart) requests permission"
                let body = "Tool: \(approval.tool)\n\(approval.command)"
                let promptText = "\(header)\n\(body)"
                let safeText = Self.capText(promptText)

                let keyboard = TelegramInlineKeyboard([
                    [
                        TelegramInlineKeyboardButton(text: "Разрешить", callbackData: "c:\(allowAction.ref):allow"),
                        TelegramInlineKeyboardButton(text: "Запретить", callbackData: "c:\(denyAction.ref):deny")
                    ]
                ])

                do {
                    let msgId = try await api.sendMessage(chatId: chatId, text: safeText, keyboard: keyboard)
                    self.activeApproval = ActiveApprovalContext(
                        id: approval.id,
                        fingerprint: approval.fingerprint,
                        sessionId: approval.sessionId,
                        chatId: chatId,
                        messageId: msgId,
                        promptText: safeText
                    )
                } catch {
                    // Ignored on network error
                }
            }

        case .approvalResolved:
            if let active = activeApproval {
                let msgId = active.messageId
                let chat = active.chatId
                let prompt = active.promptText
                activeApproval = nil
                Task { [weak self] in
                    try? await self?.api?.editMessage(
                        chatId: chat,
                        messageId: msgId,
                        text: prompt + "\n\n(Обработано)",
                        keyboard: nil
                    )
                }
            }

        case .question:
            guard settings.notifyQuestions else { return }
            guard let questionSnap = event.question else { return }
            guard let userId = settings.pairedUserId else { return }

            let items = questionSnap.items.map { it in
                AskQuestionItem(
                    question: it.question,
                    header: it.header,
                    options: it.options.map { AskQuestionOption(label: $0.label, description: $0.description) },
                    multiSelect: it.multiSelect
                )
            }
            guard !items.isEmpty else { return }
            let q0 = items[0]

            Task { [weak self] in
                guard let self = self, let api = self.api else { return }
                var optionRefs: [String: (questionIndex: Int, optionLabel: String)] = [:]
                var buttons: [[TelegramInlineKeyboardButton]] = []

                var row: [TelegramInlineKeyboardButton] = []
                for opt in q0.options {
                    let action = await self.registry.insert(
                        kind: .questionSelect,
                        fingerprint: questionSnap.fingerprint,
                        sessionId: event.sessionId,
                        chatId: chatId,
                        userId: userId
                    )
                    optionRefs[action.ref] = (0, opt.label)
                    let btnText = q0.multiSelect ? "◻️ \(opt.label)" : opt.label
                    row.append(TelegramInlineKeyboardButton(text: btnText, callbackData: "c:\(action.ref):select"))
                    if row.count == 1 || !q0.multiSelect {
                        buttons.append(row)
                        row = []
                    }
                }
                if !row.isEmpty { buttons.append(row) }

                var submitRef: String? = nil
                if q0.multiSelect {
                    let subAction = await self.registry.insert(
                        kind: .questionSubmit,
                        fingerprint: questionSnap.fingerprint,
                        sessionId: event.sessionId,
                        chatId: chatId,
                        userId: userId
                    )
                    submitRef = subAction.ref
                    buttons.append([TelegramInlineKeyboardButton(text: "Отправить", callbackData: "c:\(subAction.ref):submit")])
                }

                let textAction = await self.registry.insert(
                    kind: .questionText,
                    fingerprint: questionSnap.fingerprint,
                    sessionId: event.sessionId,
                    chatId: chatId,
                    userId: userId
                )
                let textRef = textAction.ref
                buttons.append([TelegramInlineKeyboardButton(text: "Ответить текстом", callbackData: "c:\(textAction.ref):text")])

                let projectPart = event.projectName.map { " (\($0))" } ?? ""
                let header = "❓ \(event.agentName)\(projectPart)"
                let promptText = "\(header)\n\(q0.question)"
                let safeText = Self.capText(promptText)

                let keyboard = TelegramInlineKeyboard(buttons)
                do {
                    let msgId = try await api.sendMessage(chatId: chatId, text: safeText, keyboard: keyboard)
                    self.activeQuestion = ActiveQuestionContext(
                        fingerprint: questionSnap.fingerprint,
                        sessionId: event.sessionId,
                        items: items,
                        selections: Array(repeating: [], count: items.count),
                        chatId: chatId,
                        messageId: msgId,
                        promptText: safeText,
                        awaitingText: false,
                        optionRefs: optionRefs,
                        submitRef: submitRef,
                        textRef: textRef,
                        terminalRef: nil
                    )
                } catch {
                    // Ignored
                }
            }

        case .questionResolved:
            if let active = activeQuestion {
                let msgId = active.messageId
                let chat = active.chatId
                let prompt = active.promptText
                activeQuestion = nil
                Task { [weak self] in
                    try? await self?.api?.editMessage(
                        chatId: chat,
                        messageId: msgId,
                        text: prompt + "\n\n(Обработано)",
                        keyboard: nil
                    )
                }
            }
        }
    }

    // MARK: - Update Handling (from Telegram Bot API)

    func handle(update: TelegramUpdate) {
        Task { [weak self] in
            await self?.handle(update: update)
        }
    }

    func handle(update: TelegramUpdate) async {
        let settings = settingsProvider()

        // 1. If Telegram is disabled, reject callbacks and leave local cards untouched
        guard settings.enabled else {
            if let cb = update.callbackQuery {
                try? await api?.answerCallbackQuery(id: cb.id, text: "Telegram отключён", showAlert: false)
            }
            return
        }

        // 2. Handle Message Update
        if let message = update.message {
            await handle(message: message, settings: settings)
            return
        }

        // 3. Handle Callback Query Update
        if let cb = update.callbackQuery {
            await handle(callbackQuery: cb, settings: settings)
            return
        }
    }

    // MARK: - Private Handlers

    private func handle(message: TelegramMessage, settings: TelegramSettings) async {
        let text = message.text ?? ""

        // Pairing command: /start <nonce>
        if text.hasPrefix("/start") {
            let chatType = TelegramChatType(rawValue: message.chat.type) ?? .group
            let chat = TelegramChat(id: message.chat.id, userId: message.from?.id ?? 0, username: message.chat.username, type: chatType)
            let expectedNonce = UserDefaults.standard.string(forKey: "telegram.pairingNonce") ?? ""
            let expectedUserId = message.from?.id ?? 0
            let acceptResult = TelegramPairing.accept(
                start: text,
                expectedNonce: expectedNonce,
                expectedUserId: expectedUserId,
                chat: chat,
                now: clock.now
            )
            if case .success(let pair) = acceptResult {
                UserDefaults.standard.set(pair.chatId, forKey: "telegram.pairedChatId")
                UserDefaults.standard.set(pair.userId, forKey: "telegram.pairedUserId")
                UserDefaults.standard.set(pair.username, forKey: "telegram.pairedBotUsername")
                _ = try? await api?.sendMessage(chatId: pair.chatId, text: "Telegram подключён")
            }
            return
        }

        // Check sender is paired
        guard message.chat.type == "private",
              let pairedChatId = settings.pairedChatId, pairedChatId == message.chat.id,
              let pairedUserId = settings.pairedUserId, pairedUserId == (message.from?.id ?? 0) else {
            return
        }

        // Handle reply to awaiting text question
        if var active = activeQuestion, active.awaitingText {
            active.awaitingText = false
            if active.selections.isEmpty { active.selections = [[]] }
            active.selections[0] = [text]

            let answers = AskQuestion.buildAnswers(questions: active.items, selections: active.selections)
            onQuestionAnswers?(answers)

            let msgId = active.messageId
            let chat = active.chatId
            let prompt = active.promptText
            activeQuestion = nil

            let updatedText = prompt + "\n\nОтветил: \(text)"
            try? await api?.editMessage(chatId: chat, messageId: msgId, text: updatedText, keyboard: nil)
        }
    }

    private func handle(callbackQuery cb: TelegramCallbackQuery, settings: TelegramSettings) async {
        guard let chat = cb.message?.chat else { return }
        guard chat.type == "private" else { return } // reject non-private chat

        let fromId = cb.from.id
        let chatId = chat.id

        // Foreign callback is rejected
        guard let pairedChatId = settings.pairedChatId, pairedChatId == chatId else { return }
        guard let pairedUserId = settings.pairedUserId, pairedUserId == fromId else { return }

        guard let data = cb.data else {
            try? await api?.answerCallbackQuery(id: cb.id, text: "Срок действия истёк", showAlert: false)
            return
        }

        // Parse callback grammar: c:<ref>:<op>
        let parts = data.split(separator: ":").map(String.init)
        guard parts.count == 3, parts[0] == "c" else {
            try? await api?.answerCallbackQuery(id: cb.id, text: "Срок действия истёк", showAlert: false)
            return
        }
        let ref = parts[1]
        let op = parts[2]

        // Approval callback
        if op == "allow" || op == "deny" {
            guard let active = activeApproval else {
                try? await api?.answerCallbackQuery(id: cb.id, text: "Срок действия истёк", showAlert: false)
                return
            }

            let result = await registry.consume(ref: ref, chatId: chatId, userId: fromId, now: clock.now, fingerprint: active.fingerprint)
            switch result {
            case .accepted:
                let decision = (op == "allow") ? "allow" : "deny"
                onApprovalDecision?(decision, active.id)
                try? await api?.answerCallbackQuery(id: cb.id, text: nil, showAlert: false)

                let decisionLabel = (decision == "allow") ? "Разрешить" : "Запретить"
                let updatedText = active.promptText + "\n\nОтветил: \(decisionLabel)"
                let msgId = active.messageId
                activeApproval = nil
                try? await api?.editMessage(chatId: chatId, messageId: msgId, text: updatedText, keyboard: nil)

            case .rejected:
                try? await api?.answerCallbackQuery(id: cb.id, text: "Срок действия истёк", showAlert: false)
            }
            return
        }

        // Question Option Selection
        if op == "select" {
            guard var active = activeQuestion else {
                try? await api?.answerCallbackQuery(id: cb.id, text: "Срок действия истёк", showAlert: false)
                return
            }
            guard let optInfo = active.optionRefs[ref] else {
                try? await api?.answerCallbackQuery(id: cb.id, text: "Срок действия истёк", showAlert: false)
                return
            }

            let result = await registry.consume(ref: ref, chatId: chatId, userId: fromId, now: clock.now, fingerprint: active.fingerprint)
            switch result {
            case .accepted:
                let qIndex = optInfo.questionIndex
                let label = optInfo.optionLabel
                let item = active.items[qIndex]

                if item.multiSelect {
                    // Multi-select: toggle option and re-render keyboard
                    if active.selections[qIndex].contains(label) {
                        active.selections[qIndex].removeAll { $0 == label }
                    } else {
                        active.selections[qIndex].append(label)
                    }

                    try? await api?.answerCallbackQuery(id: cb.id, text: nil, showAlert: false)

                    // Rebuild inline buttons with updated checkbox marks
                    var newOptionRefs: [String: (questionIndex: Int, optionLabel: String)] = [:]
                    var rows: [[TelegramInlineKeyboardButton]] = []
                    var currentRow: [TelegramInlineKeyboardButton] = []
                    for opt in item.options {
                        let isSelected = active.selections[qIndex].contains(opt.label)
                        let newAction = await registry.insert(
                            kind: .questionSelect,
                            fingerprint: active.fingerprint,
                            sessionId: active.sessionId,
                            chatId: chatId,
                            userId: fromId
                        )
                        newOptionRefs[newAction.ref] = (qIndex, opt.label)
                        let icon = isSelected ? "☑️ " : "◻️ "
                        currentRow.append(TelegramInlineKeyboardButton(text: icon + opt.label, callbackData: "c:\(newAction.ref):select"))
                        if currentRow.count == 1 {
                            rows.append(currentRow)
                            currentRow = []
                        }
                    }
                    if !currentRow.isEmpty { rows.append(currentRow) }

                    let newSubmitAction = await registry.insert(
                        kind: .questionSubmit,
                        fingerprint: active.fingerprint,
                        sessionId: active.sessionId,
                        chatId: chatId,
                        userId: fromId
                    )
                    rows.append([TelegramInlineKeyboardButton(text: "Отправить", callbackData: "c:\(newSubmitAction.ref):submit")])

                    let newTextAction = await registry.insert(
                        kind: .questionText,
                        fingerprint: active.fingerprint,
                        sessionId: active.sessionId,
                        chatId: chatId,
                        userId: fromId
                    )
                    rows.append([TelegramInlineKeyboardButton(text: "Ответить текстом", callbackData: "c:\(newTextAction.ref):text")])

                    active.optionRefs = newOptionRefs
                    active.submitRef = newSubmitAction.ref
                    active.textRef = newTextAction.ref
                    activeQuestion = active

                    try? await api?.editMessage(
                        chatId: chatId,
                        messageId: active.messageId,
                        text: active.promptText,
                        keyboard: TelegramInlineKeyboard(rows)
                    )
                } else {
                    // Single-select: immediately resolves
                    active.selections[qIndex] = [label]
                    let answers = AskQuestion.buildAnswers(questions: active.items, selections: active.selections)
                    onQuestionAnswers?(answers)
                    try? await api?.answerCallbackQuery(id: cb.id, text: nil, showAlert: false)

                    let updatedText = active.promptText + "\n\nОтветил: \(label)"
                    let msgId = active.messageId
                    activeQuestion = nil
                    try? await api?.editMessage(chatId: chatId, messageId: msgId, text: updatedText, keyboard: nil)
                }

            case .rejected:
                try? await api?.answerCallbackQuery(id: cb.id, text: "Срок действия истёк", showAlert: false)
            }
            return
        }

        // Question Submit (Multi-select)
        if op == "submit" {
            guard let active = activeQuestion, let submitRef = active.submitRef, submitRef == ref else {
                try? await api?.answerCallbackQuery(id: cb.id, text: "Срок действия истёк", showAlert: false)
                return
            }

            let result = await registry.consume(ref: ref, chatId: chatId, userId: fromId, now: clock.now, fingerprint: active.fingerprint)
            switch result {
            case .accepted:
                let answers = AskQuestion.buildAnswers(questions: active.items, selections: active.selections)
                onQuestionAnswers?(answers)
                try? await api?.answerCallbackQuery(id: cb.id, text: nil, showAlert: false)

                let picked = active.selections.flatMap { $0 }.joined(separator: ", ")
                let updatedText = active.promptText + "\n\nОтветил: \(picked)"
                let msgId = active.messageId
                activeQuestion = nil
                try? await api?.editMessage(chatId: chatId, messageId: msgId, text: updatedText, keyboard: nil)

            case .rejected:
                try? await api?.answerCallbackQuery(id: cb.id, text: "Срок действия истёк", showAlert: false)
            }
            return
        }

        // Question Text
        if op == "text" {
            guard var active = activeQuestion, let textRef = active.textRef, textRef == ref else {
                try? await api?.answerCallbackQuery(id: cb.id, text: "Срок действия истёк", showAlert: false)
                return
            }

            let result = await registry.consume(ref: ref, chatId: chatId, userId: fromId, now: clock.now, fingerprint: active.fingerprint)
            switch result {
            case .accepted:
                active.awaitingText = true
                activeQuestion = active
                try? await api?.answerCallbackQuery(id: cb.id, text: "Отправьте ваш ответ текстовым сообщением", showAlert: false)

            case .rejected:
                try? await api?.answerCallbackQuery(id: cb.id, text: "Срок действия истёк", showAlert: false)
            }
            return
        }

        // Unknown op
        try? await api?.answerCallbackQuery(id: cb.id, text: "Срок действия истёк", showAlert: false)
    }

    // MARK: - Utilities

    private static func capText(_ text: String) -> String {
        String(text.unicodeScalars.prefix(3500))
    }

    nonisolated static func loadDefaultSettings() -> TelegramSettings {
        let defaults = UserDefaults.standard
        let enabled = defaults.bool(forKey: "telegram.enabled")
        let notifyFinished = defaults.object(forKey: "telegram.notifyFinished") as? Bool ?? true
        let notifyQuestions = defaults.object(forKey: "telegram.notifyQuestions") as? Bool ?? true
        let notifyApprovals = defaults.object(forKey: "telegram.notifyApprovals") as? Bool ?? true
        let pairedChatId = defaults.object(forKey: "telegram.pairedChatId") as? Int64
            ?? (defaults.object(forKey: "telegram.pairedChatId") as? NSNumber)?.int64Value
        let pairedUserId = defaults.object(forKey: "telegram.pairedUserId") as? Int64
            ?? (defaults.object(forKey: "telegram.pairedUserId") as? NSNumber)?.int64Value
        let pairedBotUsername = defaults.string(forKey: "telegram.pairedBotUsername")

        return TelegramSettings(
            enabled: enabled,
            notifyFinished: notifyFinished,
            notifyQuestions: notifyQuestions,
            notifyApprovals: notifyApprovals,
            pairedChatId: pairedChatId,
            pairedUserId: pairedUserId,
            pairedBotUsername: pairedBotUsername
        )
    }

    nonisolated static func loadDefaultToken() -> String? {
        KeychainStore.shared.get("telegram-bot-token") ?? Keychain.load(key: "telegram-bot-token")
    }
}
