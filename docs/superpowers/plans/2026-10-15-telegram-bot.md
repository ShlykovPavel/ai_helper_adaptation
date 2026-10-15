# Telegram Bot Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Добавить одинаковую Telegram-интеграцию для macOS, Windows и Linux: безопасное подключение своего бота, уведомления о завершении, интерактивные ответы на вопросы и явные решения approval-запросов.

**Architecture:** Telegram Bot API вызывается непосредственно из Coucou. macOS получает Swift-адаптер над существующим `HookServer`, а Windows/Linux используют один Rust/Tauri runtime над существующим `pipe` и `Pending`; обе реализации следуют одному контракту событий, pairing, action registry и TTL. Входящие updates читаются через long polling, поэтому новый публичный relay-сервис не нужен.

**Tech Stack:** Swift 6, SwiftUI, Foundation `URLSession`, Keychain, Rust/Tokio/Reqwest, Tauri 2, `keyring`, TypeScript, Swift XCTest-style standalone tests, Rust unit tests, Node test runner.

**Spec:** `docs/superpowers/specs/2026-10-15-telegram-bot-design.md`

## Global Constraints

- Поддерживаемые платформы: macOS, Windows и Linux; Windows и Linux используют один Rust-код.
- Bot token хранится только в системном secret store: macOS Keychain, Windows Credential Manager или Linux Secret Service; в JSON-настройках сохраняются только флаги и pairing metadata.
- Входящие updates: только Telegram Bot API `getUpdates` с `allowed_updates=["message","callback_query"]`; перед polling вызвать `deleteWebhook(false)`.
- Hook никогда не ждёт сеть Telegram и продолжает работать при выключенном приложении, timeout, 401, 409 или 429.
- Callback data содержит только короткий opaque action ref и операцию; fingerprint, command и текст вопроса в callback data не передаются.
- Удалённое approval действие в V1 ограничено явными `allow` и `deny`; постоянное `always` из Telegram не реализуется.
- Каждый action одноразовый, проверяется по `chat_id`, `user_id`, TTL 120 секунд и текущему fingerprint запроса.
- Не логировать token, полный command/path/prompt/final answer и payload Telegram; для диагностики логировать только вид события, статус HTTP и короткий ref.
- Максимум исходящих pending действий — 64, максимум очереди уведомлений — 32; pending approval/question не выбрасываются из-за обычных `finished`.
- До реализации V2 требуется отдельный feasibility spike для документированного канала отправки текста в конкретную сессию агента.

## Review Focus

- Чужой пользователь или group chat нажимает кнопку: callback подтверждается визуально, но не вызывает решение.
- Просроченная или повторно нажатая кнопка: action отклоняется идемпотентно и не может разрешить другой запрос.
- Одновременно идут две сессии/approval: сообщение и action отвечают только своему `sessionId` и fingerprint.
- Telegram недоступен или возвращает 401/409/429: локальный hook и UI не блокируются, polling восстанавливается или показывает понятный статус.
- Вопрос multi-select/несколько вопросов/«Ответить текстом»: в агент уходит полный валидный набор ответов в правильном порядке либо не уходит ничего.

---

### Task 1: Зафиксировать кросс-платформенный контракт и fixtures

**Files:**
- Modify: `docs/superpowers/specs/2026-10-15-telegram-bot-design.md`
- Create: `tests/fixtures/telegram/get-updates-question.json`
- Create: `tests/fixtures/telegram/get-updates-approval.json`
- Create: `tests/fixtures/telegram/get-updates-pairing.json`
- Create: `tests/fixtures/telegram/get-updates-foreign-chat.json`
- Create: `tests/fixtures/telegram/action-cases.json`

**Interfaces:**
- Produces: canonical event names `finished`, `question`, `approval`, `error`; callback grammar `c:<ref>:<op>`; fixture fields `update_id`, `chat.id`, `from.id`, `message.message_id`, `callback_query.data`.
- Consumes: existing macOS `ApprovalInfo`/`AskQuestion` and Windows `PhoneLinkApproval`/`PhoneLinkQuestion` shapes.

- [ ] **Step 1: Write fixture cases before platform code**

Add fixtures for: valid pairing `/start nonce`, valid approval callback, valid question callback, wrong user, group chat, duplicate callback, expired action and a 409/429 API error envelope. Keep command and answer text synthetic.

- [ ] **Step 2: Add a contract checklist to the spec**

Record exact limits, TTL, action grammar and state transitions so Swift and Rust tests assert the same behavior.

- [ ] **Step 3: Run fixture validation**

Run: `python3 -m json.tool tests/fixtures/telegram/get-updates-question.json`

Expected: every fixture parses as JSON and contains no real token, path or command.

- [ ] **Step 4: Commit the contract**

```bash
git add docs/superpowers/specs/2026-10-15-telegram-bot-design.md tests/fixtures/telegram
git commit -m "docs: define Telegram integration contract"
```

### Task 2: Implement platform-neutral action and pairing rules in macOS testable models

**Files:**
- Create: `NotchBuddy/Sources/App/Telegram/TelegramModels.swift`
- Create: `NotchBuddy/Sources/App/Telegram/TelegramActionRegistry.swift`
- Create: `NotchBuddy/Sources/App/Telegram/TelegramPairing.swift`
- Test: `tests/TelegramActionRegistryTests.swift`
- Test: `tests/TelegramPairingTests.swift`

**Interfaces:**
- Produces:
  - `struct TelegramSettings: Codable, Equatable, Sendable` with enabled, notification flags, pairing metadata and no token field.
  - `struct TelegramAction: Equatable, Sendable`
  - `actor TelegramActionRegistry { func insert(kind: TelegramActionKind, fingerprint: String, sessionId: String, chatId: Int64, userId: Int64, messageId: Int64) -> TelegramAction; func consume(ref: String, chatId: Int64, userId: Int64, now: Date) -> TelegramActionResult }`
  - `struct TelegramPairing { static func nonce() -> String; static func accept(start: String, expectedNonce: String, chat: TelegramChat, now: Date) -> Result<TelegramPair, PairingError> }`
- Consumes: `QuestionPayload` fingerprint and `ApprovalInfo` fingerprint equivalent.

- [ ] **Step 1: Write failing tests for callback authorization**

```swift
func testForeignUserCannotConsumeAction() async {
    let registry = TelegramActionRegistry(clock: FixedClock(now: Date(timeIntervalSince1970: 1_000)))
    let action = await registry.insert(kind: .approvalAllow, fingerprint: "fp", chatId: 10, userId: 20)
    let result = await registry.consume(ref: action.ref, chatId: 99, userId: 20)
    precondition(result == .rejected(.unauthorized))
}
```

Add cases for duplicate consume, expiry at 120 seconds, wrong fingerprint supplied by the adapter, and nonce acceptance only for private chats.

- [ ] **Step 2: Run the focused tests and verify they fail**

Run: `swiftc NotchBuddy/Sources/App/Telegram/TelegramModels.swift NotchBuddy/Sources/App/Telegram/TelegramActionRegistry.swift NotchBuddy/Sources/App/Telegram/TelegramPairing.swift tests/TelegramActionRegistryTests.swift tests/TelegramPairingTests.swift -o /tmp/coucou-telegram-model-tests && /tmp/coucou-telegram-model-tests`

Expected: compilation fails because the new types and behavior are not implemented.

- [ ] **Step 3: Implement bounded registry and pairing**

Use `UUID`/random bytes for refs, base64url without padding, an injected clock for tests, a 64-entry cap, and atomic consume. Never encode fingerprint or user text into callback data.

- [ ] **Step 4: Run focused tests**

Run the command from Step 2.

Expected: PASS, including all review-focus authorization and expiry cases.

- [ ] **Step 5: Commit**

```bash
git add NotchBuddy/Sources/App/Telegram tests/TelegramActionRegistryTests.swift tests/TelegramPairingTests.swift
git commit -m "feat: add Telegram pairing and action rules"
```

### Task 3: Add the macOS Bot API client and long-poll lifecycle

**Files:**
- Create: `NotchBuddy/Sources/App/Telegram/TelegramBotAPI.swift`
- Create: `NotchBuddy/Sources/App/Telegram/TelegramPolling.swift`
- Test: `tests/TelegramBotAPITests.swift`
- Test: `tests/TelegramPollingTests.swift`

**Interfaces:**
- Produces:
  - `protocol TelegramHTTPTransport { func request(_ method: String, body: [String: Any]) async throws -> [String: Any] }`
  - `actor TelegramBotAPI { func getMe() async throws -> TelegramBotIdentity; func getUpdates(offset: Int64?, timeoutSeconds: Int) async throws -> [TelegramUpdate]; func sendMessage(chatId: Int64, text: String, keyboard: TelegramInlineKeyboard?) async throws -> Int64; func answerCallbackQuery(id: String, text: String?, showAlert: Bool) async throws; func editMessage(chatId: Int64, messageId: Int64, text: String?, keyboard: TelegramInlineKeyboard?) async throws }`
  - `actor TelegramPolling { func start(); func stop(); var status: TelegramConnectionStatus { get } }`
- Consumes: `TelegramSettings` and `TelegramUpdate` from Task 2.

- [ ] **Step 1: Write failing request encoding tests**

Assert that `getUpdates` sends `offset`, `timeout=25`, and exact `allowed_updates`; callback data is sent as JSON without token in error strings; `sendMessage` produces an inline keyboard; 401, 409 and 429 map to typed errors.

- [ ] **Step 2: Implement a URLSession transport**

Use base URL `https://api.telegram.org/bot<token>/`, a 10-second request timeout, a 25-second long-poll timeout, strict `ok` response checking and body truncation in errors. Call `deleteWebhook(drop_pending_updates: false)` before the first poll.

- [ ] **Step 3: Implement cancellable polling with backoff**

Advance offset to `update_id + 1` after processing the response, dispatch updates to a handler, sleep with cancellation-aware backoff on network errors, stop permanently on 401, and expose 409 as a conflict status.

- [ ] **Step 4: Run focused tests**

Run: `swiftc NotchBuddy/Sources/App/Telegram/TelegramModels.swift NotchBuddy/Sources/App/Telegram/TelegramBotAPI.swift NotchBuddy/Sources/App/Telegram/TelegramPolling.swift tests/TelegramBotAPITests.swift tests/TelegramPollingTests.swift -o /tmp/coucou-telegram-api-tests && /tmp/coucou-telegram-api-tests`

Expected: PASS with a fake transport; no real Telegram request is made.

- [ ] **Step 5: Commit**

```bash
git add NotchBuddy/Sources/App/Telegram tests/TelegramBotAPITests.swift tests/TelegramPollingTests.swift
git commit -m "feat: add macOS Telegram Bot API client"
```

### Task 4: Connect macOS hooks to Telegram events and actions

**Files:**
- Create: `NotchBuddy/Sources/App/Telegram/TelegramBotController.swift`
- Modify: `NotchBuddy/Sources/App/HookServer.swift` at event/approval/question lifecycle methods
- Modify: `NotchBuddy/Sources/App/AppDelegate.swift`
- Test: `tests/TelegramControllerTests.swift`

**Interfaces:**
- Produces: `@MainActor final class TelegramBotController { func start(); func stop(); func handle(update: TelegramUpdate); func settingsChanged() }`
- Consumes: `HookServer.sendApprovalDecision(_:for:)`, `HookServer.sendQuestionAnswers(_:)`, `AppState.$pendingApproval`, `AppState.$pendingQuestion`, `QuestionPayload`, `ApprovalInfo`.

- [ ] **Step 1: Write failing controller tests**

Cover: `Stop` creates one finished message; second identical `Stop` is deduplicated; approval sends Allow/Deny keyboard; a foreign callback is rejected; a valid callback reaches `HookServer` only while the same approval id/fingerprint is pending; question choices map to `AskQuestion.buildAnswers`.

- [ ] **Step 2: Emit normalized events from HookServer**

Add one internal event publisher at the existing `Stop`, `StopFailure`, approval enqueue/remove and question request/answer points. Keep all local UI transitions unchanged. Do not call Telegram network code from the socket thread or while writing a hook response.

- [ ] **Step 3: Render and send V1 messages**

Use plain text capped at 3,500 Unicode scalars. Build keyboards from labels, keep an opaque ref per button, support multi-select and `Ответить текстом`, and edit the message after a decision. Add a 120-second registry TTL and remove keyboard on local resolution.

- [ ] **Step 4: Wire lifecycle and settings changes**

Start after `HookServer.start()`, restart when enabled/token/pairing changes, and stop on app termination. If Telegram is disabled, reject callbacks and leave local cards untouched.

- [ ] **Step 5: Run tests and macOS build**

Run: `xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`
Run: `xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`

Expected: the macOS build succeeds without a network dependency or new third-party package; controller behavior is covered by the fake-transport tests included in the Xcode test target.

- [ ] **Step 6: Commit**

```bash
git add NotchBuddy/Sources/App/Telegram NotchBuddy/Sources/App/HookServer.swift NotchBuddy/Sources/App/AppDelegate.swift tests/TelegramControllerTests.swift
git commit -m "feat: route macOS agent events to Telegram"
```

### Task 5: Add macOS Telegram settings, Keychain entry and in-app guide

**Files:**
- Modify: `NotchBuddy/Sources/App/ClaudeService.swift` (`KeychainStore.allKeys`)
- Modify: `NotchBuddy/Sources/App/SettingsView.swift`
- Modify: `NotchBuddy/Resources/Localizable.xcstrings`
- Create: `NotchBuddy/Sources/App/Telegram/TelegramSettingsStore.swift`
- Test: `tests/TelegramSettingsTests.swift`

**Interfaces:**
- Produces: `TelegramSettingsStore` with `load`, `save`, `clear`, `pairingLink`, and status projection that never returns the token; the `TelegramSettings` value type itself comes from Task 2.
- Consumes: `KeychainStore`, `UserDefaults`, `TelegramBotController`.

- [ ] **Step 1: Write failing persistence tests**

Use an isolated `UserDefaults` suite and fake keychain. Assert enabled/notification flags round-trip, clear removes token and pairing metadata, and serialized settings never contains the token.

- [ ] **Step 2: Add Keychain key and store model**

Register `telegram-bot-token` in the existing macOS keychain cache. Keep `pairedChatId`, `pairedUserId`, `pairedBotUsername`, `pairingNonce`, and expiry in `UserDefaults` under `telegram.*`.

- [ ] **Step 3: Build the guide and pairing UI**

Add the BotFather steps, `https://t.me/BotFather` link, SecureField, Test button, Pair button, connection state, notification toggles, Re-pair and Disconnect actions. Use the current Settings style and localization keys; no existing settings are restyled.

- [ ] **Step 4: Run focused tests and build**

Run: `swiftc NotchBuddy/Sources/App/Telegram/TelegramModels.swift NotchBuddy/Sources/App/Telegram/TelegramPairing.swift NotchBuddy/Sources/App/Telegram/TelegramSettingsStore.swift tests/TelegramSettingsTests.swift -o /tmp/coucou-telegram-settings-tests && /tmp/coucou-telegram-settings-tests`
Run the macOS build from Task 4.

Expected: PASS; the UI exposes only token-present state after save.

- [ ] **Step 5: Commit**

```bash
git add NotchBuddy/Sources/App/ClaudeService.swift NotchBuddy/Sources/App/SettingsView.swift NotchBuddy/Resources/Localizable.xcstrings NotchBuddy/Sources/App/Telegram/TelegramSettingsStore.swift tests/TelegramSettingsTests.swift
git commit -m "feat: add Telegram settings on macOS"
```

### Task 6: Implement the shared Rust/Tauri Telegram runtime for Windows and Linux

**Files:**
- Create: `windows/src-tauri/src/telegram_api.rs`
- Create: `windows/src-tauri/src/telegram.rs`
- Modify: `windows/src-tauri/src/secrets.rs`
- Modify: `windows/src-tauri/src/settings.rs`
- Modify: `windows/src-tauri/src/lib.rs`
- Test: Rust unit tests in `windows/src-tauri/src/telegram_api.rs` and `windows/src-tauri/src/telegram.rs`

**Interfaces:**
- Produces:
  - `pub struct TelegramService`
  - `pub fn start(app: AppHandle)` / `pub fn stop(app: &AppHandle)`
  - `pub fn on_hook(app: &AppHandle, payload: serde_json::Value)`
  - `pub fn on_pending_approval(app: &AppHandle, payload: &serde_json::Value)`
  - `pub async fn handle_update(app: &AppHandle, update: Update)`
  - Tauri commands `telegram_status`, `telegram_test_token`, `telegram_set_enabled`, `telegram_new_pairing`, `telegram_disconnect`.
- Consumes: `pipe::answer`, `pipe::answer_question`, `pipe::decline`, `settings::Settings`, `secrets` and existing Tauri `AppHandle` state.

- [ ] **Step 1: Write Rust tests for API and registry**

Use a fake HTTP transport. Assert JSON encoding, offset progression, callback length ≤64 bytes, pairing checks, duplicate/expired callbacks and no token in `Debug`/error output.

- [ ] **Step 2: Add `telegram-bot-token` to the OS secret allowlist**

Extend `secrets::KNOWN_KEYS`; keep the value inaccessible to the webview except through write-only/status commands.

- [ ] **Step 3: Add serializable Telegram settings**

Add fields with defaults so older settings files load unchanged: enabled, three notification flags, paired chat/user ids, bot username, pairing expiry/status. Follow the existing `serde(rename_all = "camelCase", default)` pattern.

- [ ] **Step 4: Implement the Tokio service**

Use one runtime for Windows and Linux, `reqwest`/Tokio timeouts, long polling, deleteWebhook, backoff, 401/409/429 handling, action registry, plain-text truncation and message editing. The service owns no UI state and calls existing pipe decision functions only after validation.

- [ ] **Step 5: Register commands and lifecycle**

Register the module and commands in `lib.rs`, start it after the hook pipe starts, stop it on app exit, and make settings commands trigger restart/reconfiguration without exposing the token.

- [ ] **Step 6: Run Rust tests**

Run: `cargo test --manifest-path windows/src-tauri/Cargo.toml telegram`

Expected: PASS on both Windows and Linux toolchains; tests use no live network.

- [ ] **Step 7: Commit**

```bash
git add windows/src-tauri/src/telegram_api.rs windows/src-tauri/src/telegram.rs windows/src-tauri/src/secrets.rs windows/src-tauri/src/settings.rs windows/src-tauri/src/lib.rs
git commit -m "feat: add cross-platform Rust Telegram runtime"
```

### Task 7: Feed Windows/Linux hook events and pending approvals into the runtime

**Files:**
- Modify: `windows/src-tauri/src/pipe.rs`
- Modify: `windows/src/island/hooks.ts`
- Modify: `windows/src/core/bridge.ts`
- Test: `windows/tests/telegram-hook-bridge.test.mjs`
- Test: Rust tests in `windows/src-tauri/src/pipe.rs`

**Interfaces:**
- Produces: a hook event stream with the same canonical payload fields as macOS; Telegram decisions call `pipe::answer`/`answer_question` for the exact `request_id`.
- Consumes: `TelegramService::on_hook`, `TelegramService::on_pending_approval`, existing `Pending` map and `Bridge.approval*` semantics.

- [ ] **Step 1: Write failing bridge tests**

Assert that `Stop` is forwarded once, a `PermissionRequest` is registered before the UI event, a question preserves all options, and a Telegram decision for an unknown request id is ignored.

- [ ] **Step 2: Register hooks before emitting to the webview**

In `pipe::handle`, keep the current local ack/decision behavior and additionally pass a sanitized payload to the Telegram runtime. The runtime failure path must not alter the pipe response.

- [ ] **Step 3: Keep the browser UI behavior unchanged**

Do not duplicate decisions in TypeScript. Existing island clicks keep using `Bridge.approvalDecision`/`approvalAnswer`; Telegram calls the same Rust-level pending map.

- [ ] **Step 4: Run frontend and Rust tests**

Run: `cd windows && npm test -- --test-name-pattern=telegram`
Run: `cargo test --manifest-path windows/src-tauri/Cargo.toml pipe`

Expected: existing hook tests and new bridge tests pass.

- [ ] **Step 5: Commit**

```bash
git add windows/src-tauri/src/pipe.rs windows/src/island/hooks.ts windows/src/core/bridge.ts windows/tests/telegram-hook-bridge.test.mjs
git commit -m "feat: connect Windows and Linux hooks to Telegram"
```

### Task 8: Add the Windows/Linux Settings UI and localization

**Files:**
- Modify: `windows/src/settings/integrations.ts`
- Modify: `windows/src/settings/settings.css`
- Modify: `windows/src/core/bridge.ts`
- Modify: `windows/src/core/state.ts`
- Modify: `windows/src/i18n/strings.json`
- Modify: `windows/src/i18n/extra.json`
- Test: `windows/tests/telegram-settings.test.mjs`

**Interfaces:**
- Produces: the same user-visible flow as macOS: token entry, BotFather guide, Test token, pairing link, connected status, notification toggles, Re-pair and Disconnect.
- Consumes: Tauri commands from Task 6 and `Bridge.secretPresent/secretSet/secretClear` patterns.

- [ ] **Step 1: Write failing UI/bridge tests**

Use the existing Tauri stubs to assert token input calls `secretSet` only after submit, status never contains token, pairing link is rendered as a link, and disable calls `telegram_set_enabled(false)`.

- [ ] **Step 2: Add typed Bridge methods and state fields**

Mirror the Rust command names and status shape; keep secrets write-only. Do not let `save_settings` accept or overwrite Telegram token.

- [ ] **Step 3: Render the shared settings block**

Reuse existing Integration settings layout, add localized strings for setup, pairing, statuses and errors, and keep the three notification toggles independent from `active_integrations` slot limits.

- [ ] **Step 4: Run tests and typecheck**

Run: `cd windows && npm test -- --test-name-pattern=telegram && npm run build`

Expected: PASS; TypeScript has no new errors.

- [ ] **Step 5: Commit**

```bash
git add windows/src/settings/integrations.ts windows/src/settings/settings.css windows/src/core/bridge.ts windows/src/core/state.ts windows/src/i18n/strings.json windows/src/i18n/extra.json windows/tests/telegram-settings.test.mjs
git commit -m "feat: add Telegram settings to Tauri UI"
```

### Task 9: Add documentation, privacy copy and manual acceptance matrix

**Files:**
- Modify: `docs/INTEGRATIONS.md`
- Modify: `README.md`
- Modify: `windows/README.md`
- Create: `docs/telegram.md`
- Test: `tests/telegram-manual-checklist.md`

**Interfaces:**
- Produces: user guide for BotFather/token/pairing, troubleshooting for 401/409/429, and identical acceptance steps for macOS, Windows and Linux.
- Consumes: final UI labels and status names from Tasks 5 and 8.

- [ ] **Step 1: Write the end-user guide**

Document `/newbot`, token placement, pairing link, how to revoke a token in BotFather, what data is sent in finished/question/approval messages, and how to disconnect.

- [ ] **Step 2: Add the manual matrix**

Include cases: fresh setup, bad token, pair from another account, finish notification, single-select, multi-select, text answer, allow, deny, stale button, app restart, network loss, duplicate app instance and disable while a request is pending.

- [ ] **Step 3: Run link and copy checks**

Run: `rg -n "YOUR_BOT|placeholder credential|token" docs/telegram.md docs/INTEGRATIONS.md windows/README.md README.md`

Expected: no placeholder credentials; only instructional use of the word token remains.

- [ ] **Step 4: Commit**

```bash
git add docs/telegram.md docs/INTEGRATIONS.md README.md windows/README.md tests/telegram-manual-checklist.md
git commit -m "docs: describe Telegram setup and acceptance checks"
```

### Task 10: Validate the complete feature and record the V2 spike boundary

**Files:**
- Create: `docs/superpowers/spikes/2026-10-15-agent-inbound-channel.md`
- Modify: `CHANGELOG.md` when the feature is released
- Modify: `README.md` feature list when the feature is released

**Interfaces:**
- Produces: a written V2 spike result for Claude Code, Codex, Gemini CLI and the other supported agents; no V2 chat implementation is included in the V1 branch.

- [ ] **Step 1: Run all automated checks**

Run: `make test`
Run: `cd windows && npm test && npm run build`
Run: `cargo test --manifest-path windows/src-tauri/Cargo.toml`
Run: `xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`

Expected: no new Telegram test or build failure. Existing baseline failures are recorded separately instead of being attributed to Telegram.

- [ ] **Step 2: Execute manual Telegram matrix on each OS**

Use a disposable bot token and private test chat. Capture only statuses and screenshots; never commit token or raw messages.

- [ ] **Step 3: Verify privacy and failure properties**

Inspect settings JSON and logs, terminate Telegram network access, click stale buttons, run two app instances with one bot token, and confirm local approval remains usable.

- [ ] **Step 4: Write the V2 spike**

For each agent, record the supported inbound mechanism, lifecycle ownership, security constraints, and whether a per-session `sendPrompt` adapter can be implemented without terminal automation. If no stable mechanism exists, leave that agent read-only and keep V2 unimplemented.

- [ ] **Step 5: Final review**

Check every spec section against Tasks 1–10, search the plan for placeholders, confirm Swift/Rust callback grammars match, and ensure all review-focus inputs have automated or manual coverage.

