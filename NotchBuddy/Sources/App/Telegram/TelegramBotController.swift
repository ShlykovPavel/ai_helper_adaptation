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
        let allowRef: String
        let denyRef: String
    }

    struct ActiveQuestionContext {
        let fingerprint: String
        let sessionId: String
        let agentName: String
        let projectPart: String
        let items: [AskQuestionItem]
        var selections: [[String]]
        var currentQuestionIndex: Int
        let chatId: Int64
        let messageId: Int64
        let basePromptText: String
        var promptText: String
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
    private let isCustomAPI: Bool
    private let isCustomPolling: Bool
    private let registry: TelegramActionRegistry

    private let settingsProvider: @Sendable () -> TelegramSettings
    private let tokenProvider: @Sendable () -> String?
    private let onApprovalDecision: (@MainActor (String, UUID?) -> Void)?
    private let onQuestionAnswers: (@MainActor ([String: Any]) -> Void)?
    private let onQuestionAsk: (@MainActor () -> Void)?
    private let clock: any TelegramClock

    private var cancellables = Set<AnyCancellable>()

    private(set) var activeApprovals: [UUID: ActiveApprovalContext] = [:]
    private var activeApprovalsBySession: [String: ActiveApprovalContext] = [:]
    private var approvalSessionByRef: [String: String] = [:]
    private var approvalRefs: [String: UUID] = [:]

    var activeApproval: ActiveApprovalContext? {
        activeApprovals.values.first
    }

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
        self.isCustomAPI = (api != nil)
        self.polling = polling
        self.isCustomPolling = (polling != nil)
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

        let currentSettings = settingsProvider()
        guard currentSettings.enabled else { return }

        isRunning = true

        if api == nil, let token = tokenProvider(), !token.isEmpty {
            api = TelegramBotAPI(token: token)
        }

        if let api = api {
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
                if pending == nil && !self.activeApprovals.isEmpty {
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
        if !isCustomPolling {
            polling = nil
        }
        if !isCustomAPI {
            api = nil
        }
        isRunning = false
        activeApprovals.removeAll()
        activeApprovalsBySession.removeAll()
        approvalSessionByRef.removeAll()
        approvalRefs.removeAll()
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
                    let approvalId = approval.id ?? UUID()
                    let context = ActiveApprovalContext(
                        id: approval.id,
                        fingerprint: approval.fingerprint,
                        sessionId: approval.sessionId,
                        chatId: chatId,
                        messageId: msgId,
                        promptText: safeText,
                        allowRef: allowAction.ref,
                        denyRef: denyAction.ref
                    )
                    self.activeApprovals[approvalId] = context
                    self.activeApprovalsBySession[approval.sessionId] = context
                    self.approvalRefs[allowAction.ref] = approvalId
                    self.approvalRefs[denyAction.ref] = approvalId
                    self.approvalSessionByRef[allowAction.ref] = approval.sessionId
                    self.approvalSessionByRef[denyAction.ref] = approval.sessionId
                } catch {
                    // Ignored on network error
                }
            }

        case .approvalResolved:
            let targetId = event.approval?.id
            let toResolve: [ActiveApprovalContext]
            if let targetId = targetId, let active = activeApprovals.removeValue(forKey: targetId) {
                if activeApprovalsBySession[active.sessionId]?.id == targetId {
                    activeApprovalsBySession.removeValue(forKey: active.sessionId)
                }
                toResolve = [active]
            } else if targetId == nil {
                toResolve = Array(activeApprovals.values)
                activeApprovals.removeAll()
                activeApprovalsBySession.removeAll()
            } else {
                toResolve = []
            }

            for active in toResolve {
                approvalRefs.removeValue(forKey: active.allowRef)
                approvalRefs.removeValue(forKey: active.denyRef)
                approvalSessionByRef.removeValue(forKey: active.allowRef)
                approvalSessionByRef.removeValue(forKey: active.denyRef)
                let msgId = active.messageId
                let chat = active.chatId
                let prompt = active.promptText
                Task { [weak self] in
                    let updatedText = Self.capText(prompt + "\n\n(Обработано)")
                    try? await self?.api?.editMessage(
                        chatId: chat,
                        messageId: msgId,
                        text: updatedText,
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

            let projectPart = event.projectName.map { " (\($0))" } ?? ""
            let baseHeader = "❓ \(event.agentName)\(projectPart)"

            Task { [weak self] in
                guard let self = self, let api = self.api else { return }

                var context = ActiveQuestionContext(
                    fingerprint: questionSnap.fingerprint,
                    sessionId: event.sessionId,
                    agentName: event.agentName,
                    projectPart: projectPart,
                    items: items,
                    selections: Array(repeating: [], count: items.count),
                    currentQuestionIndex: 0,
                    chatId: chatId,
                    messageId: 0,
                    basePromptText: baseHeader,
                    promptText: "",
                    awaitingText: false,
                    optionRefs: [:],
                    submitRef: nil,
                    textRef: nil,
                    terminalRef: nil
                )

                let ui = await self.buildQuestionUI(for: &context, chatId: chatId, userId: userId)

                do {
                    let msgId = try await api.sendMessage(chatId: chatId, text: ui.text, keyboard: ui.keyboard)
                    let updatedContext = ActiveQuestionContext(
                        fingerprint: context.fingerprint,
                        sessionId: context.sessionId,
                        agentName: context.agentName,
                        projectPart: context.projectPart,
                        items: context.items,
                        selections: context.selections,
                        currentQuestionIndex: context.currentQuestionIndex,
                        chatId: chatId,
                        messageId: msgId,
                        basePromptText: context.basePromptText,
                        promptText: ui.text,
                        awaitingText: false,
                        optionRefs: context.optionRefs,
                        submitRef: context.submitRef,
                        textRef: context.textRef,
                        terminalRef: context.terminalRef
                    )
                    self.activeQuestion = updatedContext
                } catch {
                    // Ignored on network error
                }
            }

        case .questionResolved:
            if let active = activeQuestion {
                let msgId = active.messageId
                let chat = active.chatId
                let prompt = active.promptText
                activeQuestion = nil
                Task { [weak self] in
                    let updatedText = Self.capText(prompt + "\n\n(Обработано)")
                    try? await self?.api?.editMessage(
                        chatId: chat,
                        messageId: msgId,
                        text: updatedText,
                        keyboard: nil
                    )
                }
            }
        }
    }

    // MARK: - UI Builder for Questions

    private func buildQuestionUI(
        for active: inout ActiveQuestionContext,
        chatId: Int64,
        userId: Int64
    ) async -> (text: String, keyboard: TelegramInlineKeyboard) {
        let qIndex = active.currentQuestionIndex
        let item = active.items[qIndex]

        var optionRefs: [String: (questionIndex: Int, optionLabel: String)] = [:]
        var buttons: [[TelegramInlineKeyboardButton]] = []

        var row: [TelegramInlineKeyboardButton] = []
        for opt in item.options {
            let action = await registry.insert(
                kind: .questionSelect,
                fingerprint: active.fingerprint,
                sessionId: active.sessionId,
                chatId: chatId,
                userId: userId
            )
            optionRefs[action.ref] = (qIndex, opt.label)
            let isSelected = active.selections[qIndex].contains(opt.label)
            let btnText = item.multiSelect ? (isSelected ? "☑️ \(opt.label)" : "◻️ \(opt.label)") : opt.label
            row.append(TelegramInlineKeyboardButton(text: btnText, callbackData: "c:\(action.ref):select"))
            if row.count == 1 || !item.multiSelect {
                buttons.append(row)
                row = []
            }
        }
        if !row.isEmpty { buttons.append(row) }

        var submitRef: String? = nil
        if item.multiSelect {
            let subAction = await registry.insert(
                kind: .questionSubmit,
                fingerprint: active.fingerprint,
                sessionId: active.sessionId,
                chatId: chatId,
                userId: userId
            )
            submitRef = subAction.ref
            buttons.append([TelegramInlineKeyboardButton(text: "Отправить", callbackData: "c:\(subAction.ref):submit")])
        }

        let textAction = await registry.insert(
            kind: .questionText,
            fingerprint: active.fingerprint,
            sessionId: active.sessionId,
            chatId: chatId,
            userId: userId
        )
        let textRef = textAction.ref
        buttons.append([TelegramInlineKeyboardButton(text: "Ответить текстом", callbackData: "c:\(textAction.ref):text")])

        let termAction = await registry.insert(
            kind: .questionTerminal,
            fingerprint: active.fingerprint,
            sessionId: active.sessionId,
            chatId: chatId,
            userId: userId
        )
        let terminalRef = termAction.ref
        buttons.append([TelegramInlineKeyboardButton(text: "Ответить в терминале", callbackData: "c:\(termAction.ref):terminal")])

        active.optionRefs = optionRefs
        active.submitRef = submitRef
        active.textRef = textRef
        active.terminalRef = terminalRef

        let countPart = active.items.count > 1 ? " [\(qIndex + 1)/\(active.items.count)]" : ""
        let header = "❓ \(active.agentName)\(active.projectPart)\(countPart)"
        let promptText = "\(header)\n\(item.question)"
        let safeText = Self.capText(promptText)
        active.promptText = safeText

        return (safeText, TelegramInlineKeyboard(buttons))
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
            let expectedUserId = (UserDefaults.standard.object(forKey: "telegram.expectedUserId") as? NSNumber)?.int64Value ?? (message.from?.id ?? 0)
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
            let qIndex = active.currentQuestionIndex
            while active.selections.count <= qIndex {
                active.selections.append([])
            }
            active.selections[qIndex] = [text]

            if qIndex + 1 < active.items.count {
                // Advance to next question
                active.currentQuestionIndex = qIndex + 1
                let ui = await buildQuestionUI(for: &active, chatId: active.chatId, userId: pairedUserId)
                activeQuestion = active
                try? await api?.editMessage(chatId: active.chatId, messageId: active.messageId, text: ui.text, keyboard: ui.keyboard)
            } else {
                // All questions completed!
                let answers = AskQuestion.buildAnswers(questions: active.items, selections: active.selections)
                onQuestionAnswers?(answers)

                let msgId = active.messageId
                let chat = active.chatId
                let prompt = active.promptText
                activeQuestion = nil

                let updatedText = Self.capText(prompt + "\n\nОтветил: \(text)")
                try? await api?.editMessage(chatId: chat, messageId: msgId, text: updatedText, keyboard: nil)
            }
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
            guard let sess = approvalSessionByRef[ref],
                  let active = activeApprovalsBySession[sess] else {
                try? await api?.answerCallbackQuery(id: cb.id, text: "Срок действия истёк", showAlert: false)
                return
            }

            // Ensure decision matches approvals.head if a head approval is active
            if let headId = AppState.shared.pendingApproval?.id, let thisId = active.id, headId != thisId {
                try? await api?.answerCallbackQuery(id: cb.id, text: "Сначала ответьте на текущий запрос", showAlert: true)
                return
            }

            let result = await registry.consume(ref: ref, chatId: chatId, userId: fromId, now: clock.now, fingerprint: active.fingerprint)
            switch result {
            case .accepted:
                let decision = (op == "allow") ? "allow" : "deny"
                onApprovalDecision?(decision, active.id)
                try? await api?.answerCallbackQuery(id: cb.id, text: nil, showAlert: false)

                let decisionLabel = (decision == "allow") ? "Разрешить" : "Запретить"
                let updatedText = Self.capText(active.promptText + "\n\nОтветил: \(decisionLabel)")
                let msgId = active.messageId
                if let approvalId = active.id {
                    activeApprovals.removeValue(forKey: approvalId)
                }
                activeApprovalsBySession.removeValue(forKey: sess)
                approvalRefs.removeValue(forKey: active.allowRef)
                approvalRefs.removeValue(forKey: active.denyRef)
                approvalSessionByRef.removeValue(forKey: active.allowRef)
                approvalSessionByRef.removeValue(forKey: active.denyRef)
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

                    let ui = await buildQuestionUI(for: &active, chatId: chatId, userId: fromId)
                    activeQuestion = active

                    try? await api?.editMessage(
                        chatId: chatId,
                        messageId: active.messageId,
                        text: ui.text,
                        keyboard: ui.keyboard
                    )
                } else {
                    // Single-select: record selection
                    active.selections[qIndex] = [label]
                    try? await api?.answerCallbackQuery(id: cb.id, text: nil, showAlert: false)

                    if qIndex + 1 < active.items.count {
                        // Advance to next question!
                        active.currentQuestionIndex = qIndex + 1
                        let ui = await buildQuestionUI(for: &active, chatId: chatId, userId: fromId)
                        activeQuestion = active
                        try? await api?.editMessage(
                            chatId: chatId,
                            messageId: active.messageId,
                            text: ui.text,
                            keyboard: ui.keyboard
                        )
                    } else {
                        // All questions answered!
                        let answers = AskQuestion.buildAnswers(questions: active.items, selections: active.selections)
                        onQuestionAnswers?(answers)

                        let summary: String
                        if active.items.count == 1 {
                            summary = label
                        } else {
                            summary = active.selections.map { $0.joined(separator: ", ") }.joined(separator: "; ")
                        }
                        let updatedText = Self.capText(active.promptText + "\n\nОтветил: \(summary)")
                        let msgId = active.messageId
                        activeQuestion = nil
                        try? await api?.editMessage(chatId: chatId, messageId: msgId, text: updatedText, keyboard: nil)
                    }
                }

            case .rejected:
                try? await api?.answerCallbackQuery(id: cb.id, text: "Срок действия истёк", showAlert: false)
            }
            return
        }

        // Question Submit (Multi-select)
        if op == "submit" {
            guard var active = activeQuestion, let submitRef = active.submitRef, submitRef == ref else {
                try? await api?.answerCallbackQuery(id: cb.id, text: "Срок действия истёк", showAlert: false)
                return
            }

            let qIndex = active.currentQuestionIndex
            if active.selections[qIndex].isEmpty {
                try? await api?.answerCallbackQuery(id: cb.id, text: "Выберите хотя бы один вариант", showAlert: true)
                return
            }

            let result = await registry.consume(ref: ref, chatId: chatId, userId: fromId, now: clock.now, fingerprint: active.fingerprint)
            switch result {
            case .accepted:
                try? await api?.answerCallbackQuery(id: cb.id, text: nil, showAlert: false)

                if qIndex + 1 < active.items.count {
                    // Advance to next question
                    active.currentQuestionIndex = qIndex + 1
                    let ui = await buildQuestionUI(for: &active, chatId: chatId, userId: fromId)
                    activeQuestion = active
                    try? await api?.editMessage(
                        chatId: chatId,
                        messageId: active.messageId,
                        text: ui.text,
                        keyboard: ui.keyboard
                    )
                } else {
                    // All questions completed!
                    let answers = AskQuestion.buildAnswers(questions: active.items, selections: active.selections)
                    onQuestionAnswers?(answers)

                    let summary = active.selections.map { $0.joined(separator: ", ") }.joined(separator: "; ")
                    let updatedText = Self.capText(active.promptText + "\n\nОтветил: \(summary)")
                    let msgId = active.messageId
                    activeQuestion = nil
                    try? await api?.editMessage(chatId: chatId, messageId: msgId, text: updatedText, keyboard: nil)
                }

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

        // Question Terminal
        if op == "terminal" {
            guard let active = activeQuestion, let terminalRef = active.terminalRef, terminalRef == ref else {
                try? await api?.answerCallbackQuery(id: cb.id, text: "Срок действия истёк", showAlert: false)
                return
            }

            let result = await registry.consume(ref: ref, chatId: chatId, userId: fromId, now: clock.now, fingerprint: active.fingerprint)
            switch result {
            case .accepted:
                onQuestionAsk?()
                try? await api?.answerCallbackQuery(id: cb.id, text: nil, showAlert: false)

                let updatedText = Self.capText(active.promptText + "\n\n(Отвечено в терминале)")
                let msgId = active.messageId
                activeQuestion = nil
                try? await api?.editMessage(chatId: chatId, messageId: msgId, text: updatedText, keyboard: nil)

            case .rejected:
                try? await api?.answerCallbackQuery(id: cb.id, text: "Срок действия истёк", showAlert: false)
            }
            return
        }

        // Unknown op
        try? await api?.answerCallbackQuery(id: cb.id, text: "Срок действия истёк", showAlert: false)
    }

    // MARK: - Utilities

    static func capText(_ text: String) -> String {
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
