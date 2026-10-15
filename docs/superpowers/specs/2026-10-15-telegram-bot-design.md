# Интеграция Telegram-бота в рабочий процесс агента

Статус: черновик для обсуждения. Документ описывает целевую V1 и границы V2; реализацию не запускает.

## Цель

Пользователь включает Telegram в настройках Coucou, создаёт или подключает своего бота, получает уведомления о завершении работы агента и может безопасно ответить из Telegram на вопрос агента или запрос разрешения. Поведение должно быть одинаковым для macOS, Windows и Linux, а секреты и решения не должны проходить через сторонний сервер.

## Границы версий

### V1

- Настройки содержат пошаговый гайд по `@BotFather`, SecureField для bot token, кнопку проверки подключения и pairing чата.
- Coucou сам подключается к Telegram Bot API по HTTPS. Входящие события получает через `getUpdates` с long polling; публичный webhook и отдельный Cloudflare-сервис не требуются.
- Доступ разрешён только одной спаренной private chat и одному `user_id`. Сообщения из групп, каналов и других пользователей игнорируются.
- При `Stop` отправляется сообщение о завершении с агентом, проектом и короткой последней строкой. Повтор одного и того же завершения не создаёт дубль.
- При реальном `AskUserQuestion` отправляется вопрос с inline-кнопками всех вариантов. Single-select отвечает сразу; multi-select позволяет отметить несколько вариантов и подтвердить кнопкой `Отправить`.
- Кнопка `Ответить текстом` переводит вопрос в режим ожидания одного текстового сообщения от спаренного пользователя; значение проходит ту же валидацию, что и ответ из интерфейса Coucou.
- При `PermissionRequest` отправляется карточка с инструментом и целью действия и кнопками `Разрешить`/`Запретить`. В V1 Telegram не получает действие `Always`, чтобы удалённое подтверждение не меняло постоянную политику доступа.
- Нажатие проверяется по чату, пользователю, TTL, одноразовому action id и актуальному fingerprint запроса; просроченное или уже обработанное нажатие ничего не выполняет.
- Остановка интеграции останавливает polling и отзывает все Telegram action id. Локальная карточка Coucou продолжает работать.

### V2

V2 не входит в реализацию V1. Сначала выполняется отдельный feasibility spike для каждого поддерживаемого агента: есть ли документированный способ отправить текст в конкретную живую сессию без эмуляции клавиатуры и без запуска произвольной команды. После подтверждения канала добавляется `AgentInteractionAdapter` с `sendPrompt(sessionId, text)` и capability-флагами. Telegram-команды `/status`, `/stop` и свободный чат появляются только после этого spike; V1 не делает вид, что обычный hook является двусторонним каналом.

## UX и pairing

В разделе Settings → Integrations появляется блок Telegram:

1. Текст объясняет, что бот принадлежит пользователю, а Coucou обращается к Telegram только с этой машины.
2. Ссылка «Как создать бота» открывает инструкцию: открыть `@BotFather`, выполнить `/newbot`, выбрать имя и username, скопировать token.
3. Вставленный token не возвращается в UI после сохранения и записывается в системное хранилище секретов.
4. Кнопка «Проверить token» вызывает `getMe`. Ошибка показывает безопасное сообщение без token и тела ответа целиком.
5. После успешного `getMe` Coucou генерирует 128-битный случайный pairing nonce, кодирует его base64url без `=` и предлагает ссылку `https://t.me/<username>?start=<nonce>`.
6. Пользователь открывает ссылку в Telegram и нажимает Start. Polling получает `/start <nonce>`, проверяет срок (10 минут), private chat и `from.id`, затем сохраняет `chat_id`, `user_id` и username бота.
7. После pairing Coucou отправляет тестовое сообщение «Telegram подключён» и показывает имя бота, chat id в сокращённом виде и время последней проверки.
8. «Отключить» удаляет token, pairing id, pending actions и останавливает сервис. «Перепривязать» оставляет token, но отзывает старый chat/user и создаёт новый nonce.

В настройках есть три независимых переключателя: `Уведомлять о завершении`, `Показывать вопросы`, `Показывать запросы разрешения`. По умолчанию включены все три после успешного pairing. Настройка не влияет на локальные карточки.

## Архитектура

### Общий контракт

Поведение фиксируется в кросс-платформенном контракте, а не в конкретном UI:

```text
TelegramSettings
  enabled: Bool
  notifyFinished: Bool
  notifyQuestions: Bool
  notifyApprovals: Bool
  pairedChatId: Int64?
  pairedUserId: Int64?
  pairedBotUsername: String?

TelegramEvent
  sessionId: String
  agentId: String
  agentName: String
  projectName: String?
  kind: finished | question | approval | error
  finalText: String?
  approval: ApprovalSnapshot?
  question: QuestionSnapshot?

TelegramAction
  ref: String                 // 16 random bytes, base64url; never a fingerprint
  kind: approvalAllow | approvalDeny | questionSelect | questionSubmit | questionText | questionTerminal
  requestFingerprint: String
  expiresAt: Instant
  chatId: Int64
  userId: Int64
  messageId: Int64
```

`ref` — непрозрачный одноразовый ключ, а не команда и не полный hash в callback data. Callback data имеет формат `c:<ref>:<op>` и остаётся короче лимита Telegram в 64 байта. Реальное соответствие `ref → pending request` хранится только в памяти процесса и проверяется перед действием.

### Telegram Bot API client

Платформенный клиент реализует один и тот же набор операций:

```text
getMe() -> BotIdentity
deleteWebhook(dropPendingUpdates: Bool) -> Void
getUpdates(offset: Int64?, timeoutSeconds: Int) -> [Update]
sendMessage(chatId, text, inlineKeyboard?) -> MessageId
answerCallbackQuery(callbackId, text?, showAlert: Bool) -> Void
editMessage(chatId, messageId, text?, inlineKeyboard?) -> Void
```

При старте polling сначала вызывается `deleteWebhook(false)`, потому что Telegram не выдаёт `getUpdates`, пока у бота установлен outgoing webhook. Затем цикл запрашивает только `message` и `callback_query`, подтверждает update повышением `offset` после каждого ответа и восстанавливается с backoff 1, 2, 4, 8, 16, 30, 60 секунд. Один процесс Coucou владеет polling; ошибка `409 Conflict` отображается как «бот используется другим экземпляром».

Polling — фоновая задача/actor, отменяемая при disable или завершении приложения. HTTP timeout на обычный запрос — 10 секунд, long poll — 25 секунд. Никакая операция Bot API не выполняется внутри hook-соединения: hook должен получить локальный ответ в рамках своего существующего тайм-аута.

### Action registry и защита от гонок

`TelegramActionRegistry` хранит до 64 активных actions, каждый с TTL 120 секунд. При создании approval/question action сохраняются fingerprint, session id, chat/user, message id и одноразовое состояние `pending`. При callback:

1. Проверяются `from.id` и `message.chat.id` против pairing.
2. Парсится только известный формат `c:<ref>:<op>`; неизвестные значения получают `answerCallbackQuery("Срок действия истёк")`.
3. Registry атомарно переводит action из `pending` в `consumed`.
4. Платформенный adapter ещё раз сверяет fingerprint с текущим pending request.
5. Только после этого вызывается существующий ответный API.
6. Сообщение редактируется: кнопки убираются, внизу появляется «Ответил: …». Повторный callback получает короткое уведомление и не повторяет действие.

Для вопроса multi-select выбор кнопки только обновляет `selected` в registry и перерисовывает клавиатуру. Действие к агенту уходит на `questionSubmit`, когда для каждого вопроса есть допустимый выбор. Для single-select последний выбор сразу отправляет весь набор ответов. `questionText` использует Telegram message update, но принимает только сообщение от спаренного пользователя, пока соответствующий action находится в режиме `awaitingText`.

### macOS adapter

Swift-слой использует текущие `HookServer`, `AppState`, `ApprovalQueue`, `AskQuestion` и `KeychainStore`:

- `HookServer` публикует нормализованные `TelegramEvent` для `Stop`, `StopFailure`, `processQuestionRequest` и добавления/снятия approval; текущие методы `sendQuestionAnswers` и `sendApprovalDecision` остаются единственной точкой применения решения.
- `TelegramBotController` подписывается на эти события и на изменения `pendingApproval`/`pendingQuestion`, но не изменяет UI-состояние острова.
- token хранится в `KeychainStore` под ключом `telegram-bot-token`; параметры pairing и переключатели — в `UserDefaults` с префиксом `telegram.`.
- `AppDelegate` запускает контроллер после `HookServer.start()` и останавливает его при завершении; настройка enabled вызывает тот же lifecycle без перезапуска приложения.

### Windows/Linux adapter

Для Tauri-версии общий Telegram runtime находится в Rust, поэтому Windows и Linux используют один код и разные системные backend-ы только внутри уже существующего `keyring` crate:

- `windows/src-tauri/src/telegram.rs` владеет settings, polling task, registry и маршрутизацией action.
- `windows/src-tauri/src/telegram_api.rs` содержит типизированные Bot API requests/responses и сетевые ограничения.
- `windows/src-tauri/src/pipe.rs` передаёт в runtime нормализованные hook events; для `PermissionRequest` сначала регистрирует `request_id`, затем Telegram runtime может вызвать существующие `pipe::answer`, `pipe::answer_question` или `pipe::decline`.
- Tauri commands не раскрывают token: UI получает только статус, pairing link и ошибки; секрет читается/пишется через `secrets.rs`.
- `Settings` получает сериализуемые флаги Telegram и pairing metadata; token добавляется в `secrets::KNOWN_KEYS` как `telegram-bot-token`.
- Web UI получает единый `Bridge.telegram*` API и отображает тот же блок настроек, что и macOS.

### Что считается завершением

`Stop` с несколькими параллельными сессиями отправляет сообщение только когда текущая сессия действительно завершила turn и `PillSessionRegistry`/Tauri state больше не считает её working. Ошибки сети Telegram не меняют состояние агента. Если Telegram выключен, question/approval остаются доступными в Coucou и терминале.

## Приватность и отказоустойчивость

- Token никогда не хранится в settings JSON, логах, crash message или callback data.
- В логах не пишутся полный command, path, prompt, final answer и token; разрешены только тип события, agent id, HTTP status и короткий request id.
- Сообщение ограничивается безопасным текстом до 3 500 Unicode-символов; переносы сохраняются, форматирование Telegram не используется, чтобы пользовательский текст не стал HTML/Markdown.
- Отправка уведомления имеет очередь максимум 32 элементов; при переполнении удаляется самый старый `finished`, но никогда не удаляется pending approval/question.
- На `401 Unauthorized` polling останавливается и статус предлагает перепроверить token. На `403 Forbidden` pairing помечается как недоступный. На `429` применяется `retry_after`.
- Удалённый клик не продлевает срок жизни hook: если локальная очередь уже отдала запрос терминалу или Coucou, действие отклоняется.
- Все сетевые запросы идут только к `https://api.telegram.org`; пользовательский proxy/TLS настройками V1 не добавляется.

## Тестовая стратегия

Общий контракт должен иметь fixture JSON, который прогоняется в Swift unit tests и Rust tests для одинакового разбора updates, action data, truncation и pairing. Платформенные тесты дополнительно проверяют:

- pairing принимает только правильный nonce, private chat и user id;
- чужой chat/user и group update не вызывают `sendApprovalDecision`/`sendQuestionAnswers`;
- повторный/просроченный callback идемпотентен;
- multi-select не отправляет неполный ответ и сохраняет порядок вопросов;
- сетевой timeout/401/409/429 не блокирует hook и корректно меняет статус;
- Stop для параллельных сессий не создаёт преждевременное уведомление;
- token отсутствует в settings JSON и логах.

## Официальные ограничения Telegram, на которых основан дизайн

- `getUpdates` поддерживает long polling, offset и `allowed_updates`; он недоступен, пока активен outgoing webhook.
- `callback_data` inline-кнопки ограничен 1–64 байтами, поэтому в нём используется короткий opaque ref.
- После callback нужно вызвать `answerCallbackQuery`, иначе клиент Telegram показывает бесконечный progress indicator.
- Deep-link `/start` принимает параметр длиной до 64 base64url-символов и подходит для одноразового pairing nonce.

Источники: [Telegram Bot API](https://core.telegram.org/bots/api), [Bot features and deep linking](https://core.telegram.org/bots/features).
