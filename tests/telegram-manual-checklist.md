# Telegram Bot Integration: Cross-Platform Manual Acceptance Checklist

This checklist defines the manual acceptance test matrix for the Coucou Telegram Bot integration across **macOS**, **Windows**, and **Linux**.

All 15 scenarios must yield identical behavior, security guarantees, and user experiences across all supported operating systems.

---

## Test Environment Prerequisites

Before beginning the test suite:
1. A fresh or disposable Telegram bot created via [`@BotFather`](https://t.me/BotFather) with an active HTTP API token.
2. An authorized private Telegram account on iOS, Android, or Telegram Desktop.
3. A secondary Telegram account or test group (for testing rejection rules in TC-03).
4. Coucou installed and running on the target operating system (macOS 15+, Windows 10/11, or Linux).
5. Terminal session with Claude Code, Codex, or Coucou's built-in Demo mode (`Settings → General → Demo`).

---

## Acceptance Matrix Summary

| Test ID | Scenario | macOS | Windows | Linux | Status |
|:---|:---|:---:|:---:|:---:|:---:|
| **TC-01** | Fresh setup & pairing flow | [ ] | [ ] | [ ] | Pending |
| **TC-02** | Invalid / revoked token (401 Unauthorized) | [ ] | [ ] | [ ] | Pending |
| **TC-03** | Non-private chat & unauthorized user rejection | [ ] | [ ] | [ ] | Pending |
| **TC-04** | Turn completion notification (`Stop`) & deduplication | [ ] | [ ] | [ ] | Pending |
| **TC-05** | Single-select question answering & message edit | [ ] | [ ] | [ ] | Pending |
| **TC-06** | Multi-select question toggling & submit | [ ] | [ ] | [ ] | Pending |
| **TC-07** | Text answer fallback mode | [ ] | [ ] | [ ] | Pending |
| **TC-08** | Permission request: Allow | [ ] | [ ] | [ ] | Pending |
| **TC-09** | Permission request: Deny | [ ] | [ ] | [ ] | Pending |
| **TC-10** | Stale / expired callback button click (120s TTL) | [ ] | [ ] | [ ] | Pending |
| **TC-11** | App restart & automatic reconnect | [ ] | [ ] | [ ] | Pending |
| **TC-12** | Network disconnection & backoff recovery | [ ] | [ ] | [ ] | Pending |
| **TC-13** | Duplicate app instance (409 Conflict) | [ ] | [ ] | [ ] | Pending |
| **TC-14** | Re-pair to a new chat/account | [ ] | [ ] | [ ] | Pending |
| **TC-15** | Complete disconnect & keystore cleanup | [ ] | [ ] | [ ] | Pending |

---

## Detailed Test Scenarios

### TC-01: Fresh Setup & Pairing Flow

**Objective**: Verify initial bot token entry, token validation, deep-link generation, and pairing completion.

- **Preconditions**:
  - Telegram integration is not configured.
  - A valid bot token is obtained from `@BotFather`.
- **Steps**:
  1. Navigate to **Settings… → Integrations → Telegram**.
  2. Verify initial status displays **Not configured**.
  3. Paste the bot token into the **Bot Token** field and click **Save**.
  4. Verify the input field clears and shows the placeholder `(stored)`.
  5. Click **Test token**.
  6. Observe successful token validation and bot username resolution.
  7. Click **Pair**.
  8. Open the generated deep link (`https://t.me/<bot_username>?start=<nonce>`) in Telegram on your phone or desktop.
  9. Click **Start** in Telegram.
- **Expected Results**:
  - The bot sends a confirmation message: *"Coucou Telegram bot connected!"*
  - In Settings, status updates immediately to **Connected**.
  - The bot username (e.g. `@my_bot`) and masked chat ID (e.g. `•••••5678`) are displayed.
  - The bot token is stored in the OS keystore (macOS Keychain, Windows Credential Manager, or Linux Secret Service) and is **not** present in `settings.json`.
- **Verification**:
  - [ ] macOS
  - [ ] Windows
  - [ ] Linux

---

### TC-02: Invalid / Revoked Token (401 Unauthorized)

**Objective**: Verify error handling when an invalid, corrupted, or revoked token is supplied.

- **Preconditions**:
  - Bot token is revoked in `@BotFather` (`/revoke`) or an intentionally invalid string is used.
- **Steps**:
  1. Open **Settings… → Integrations → Telegram**.
  2. Enter an invalid token string and click **Save**.
  3. Click **Test token**.
- **Expected Results**:
  - An error badge appears: *"Invalid bot token. Check token in BotFather."*
  - The token is never displayed in plaintext in the error message or console logs.
  - No pairing link is generated.
  - Polling does not start.
- **Verification**:
  - [ ] macOS
  - [ ] Windows
  - [ ] Linux

---

### TC-03: Non-Private Chat & Unauthorized User Rejection

**Objective**: Verify that groups, channels, and unauthenticated third-party accounts cannot interact with the bot.

- **Preconditions**:
  - Bot is paired with User A in a private chat (completed TC-01).
- **Steps**:
  1. From a secondary Telegram account (User B), open the bot and send `/start` or `/help`.
  2. Add the bot to a Telegram group or channel and send `/start <nonce>` or any command.
  3. Send an arbitrary text message from User B to the bot.
- **Expected Results**:
  - The bot does not respond to User B.
  - The bot completely ignores messages from groups, channels, and supergroups.
  - Settings status remains tied exclusively to User A's `chat_id` and `user_id`.
  - No actions or hooks on the host computer are triggered.
- **Verification**:
  - [ ] macOS
  - [ ] Windows
  - [ ] Linux

---

### TC-04: Turn Completion Notification (`Stop`) & Deduplication

**Objective**: Verify that agent turn completions trigger clean notifications with deduplication.

- **Preconditions**:
  - Bot is paired and **Completions and stops** toggle is enabled.
- **Steps**:
  1. In a terminal session, trigger an agent completion (e.g., execute a prompt in Claude Code or Codex that completes, or run Coucou Demo mode).
  2. Observe the message sent to your Telegram private chat.
  3. Trigger an identical duplicate completion event with the same turn/session parameters within 2 seconds.
- **Expected Results**:
  - Telegram receives a formatted completion notification containing:
    - Agent name (e.g., `Claude Code`, `Codex`)
    - Project / working directory name
    - Summary of the final answer or last response line
  - The message text is safe plaintext under 3,500 Unicode scalars.
  - The rapid duplicate event is suppressed by Coucou's event deduplicator; no second message is sent.
- **Verification**:
  - [ ] macOS
  - [ ] Windows
  - [ ] Linux

---

### TC-05: Single-Select Question Answering & Message Edit

**Objective**: Verify interactive single-select `AskUserQuestion` handling.

- **Preconditions**:
  - Bot is paired and **Questions** toggle is enabled.
- **Steps**:
  1. Trigger an agent question prompt containing single-choice options (e.g., via `AskUserQuestion` in Claude Code, or Demo mode).
  2. Check Telegram for the incoming question message with inline choice buttons.
  3. Click one of the inline options in Telegram.
- **Expected Results**:
  - Telegram immediately acknowledges the button tap with no loading spinner hang.
  - The message is edited in place: inline buttons are removed, and the footer shows the selected answer (e.g., *"Answered: <Option Label>"*).
  - The host agent immediately receives the answer through the hook relay and proceeds.
  - The desktop UI card in Coucou is dismissed or marked answered synchronously.
- **Verification**:
  - [ ] macOS
  - [ ] Windows
  - [ ] Linux

---

### TC-06: Multi-Select Question Toggling & Submit

**Objective**: Verify multi-select question checkbox behavior and batch submission.

- **Preconditions**:
  - Bot is paired and **Questions** toggle is enabled.
- **Steps**:
  1. Trigger a multi-select `AskUserQuestion` prompt with multiple options.
  2. In Telegram, verify that options appear with unselected indicators (e.g., `[ ] Option A`, `[ ] Option B`).
  3. Click Option A: verify button re-renders with checked indicator `[✓] Option A`.
  4. Click Option B: verify both `[✓] Option A` and `[✓] Option B` are checked.
  5. Click the inline **Submit** / **Отправить** button.
- **Expected Results**:
  - Checkbox toggles update the keyboard state without sending partial answers to the agent.
  - Clicking Submit dispatches the array of selected options to the agent.
  - The Telegram message is edited to show final answers and remove the buttons.
  - The agent resumes execution with the complete answer set.
- **Verification**:
  - [ ] macOS
  - [ ] Windows
  - [ ] Linux

---

### TC-07: Text Answer Fallback Mode

**Objective**: Verify the free-form text reply flow for questions.

- **Preconditions**:
  - Bot is paired and **Questions** toggle is enabled.
- **Steps**:
  1. Trigger a question prompt with an inline **Reply by text** / **Ответить текстом** button.
  2. Tap **Reply by text**.
  3. Observe the bot's prompt indicating it is awaiting your text response.
  4. Type a custom text message in the Telegram chat (e.g., `Fix issue in auth.ts`) and send it.
- **Expected Results**:
  - Coucou receives the message update from the paired user.
  - The custom text is validated and submitted to the agent as the answer.
  - The Telegram message updates to show that the question was answered with custom text.
  - Subsequent arbitrary messages in the chat are no longer captured as answers.
- **Verification**:
  - [ ] macOS
  - [ ] Windows
  - [ ] Linux

---

### TC-08: Permission Request: Allow

**Objective**: Verify granting a tool execution permission remotely.

- **Preconditions**:
  - Bot is paired and **Approvals** toggle is enabled.
- **Steps**:
  1. Run a command in an agent that triggers a `PermissionRequest` (e.g. bash execution, file modification).
  2. Observe the Telegram approval card displaying tool name, command or target path, and buttons: **Allow** and **Deny**.
  3. Click **Allow**.
- **Expected Results**:
  - The Telegram message edits immediately to show *"Approved"* with the timestamp/user.
  - The agent receives the `allow` decision and executes the requested tool.
  - The Coucou desktop island permission card clears automatically.
- **Verification**:
  - [ ] macOS
  - [ ] Windows
  - [ ] Linux

---

### TC-09: Permission Request: Deny

**Objective**: Verify denying a tool execution permission remotely.

- **Preconditions**:
  - Bot is paired and **Approvals** toggle is enabled.
- **Steps**:
  1. Trigger a `PermissionRequest` from an agent.
  2. Observe the Telegram approval message.
  3. Click **Deny**.
- **Expected Results**:
  - The Telegram message edits immediately to show *"Denied"*.
  - The agent receives the `deny` decision and aborts the tool call.
  - The Coucou desktop island permission card clears.
- **Verification**:
  - [ ] macOS
  - [ ] Windows
  - [ ] Linux

---

### TC-10: Stale / Expired Callback Button Click (120s TTL)

**Objective**: Verify that expired or previously resolved actions cannot be triggered twice.

- **Preconditions**:
  - Bot is paired and interactive permissions/questions are active.
- **Steps**:
  1. Trigger a permission request or question.
  2. Allow 125 seconds to elapse (exceeding the 120-second action TTL), OR resolve the card directly on the computer desktop island.
  3. In Telegram, click any inline button on the older message.
- **Expected Results**:
  - Telegram displays an ephemeral pop-up alert: *"Action expired or already resolved"* (`showAlert: true`).
  - No action is executed on the host computer.
  - The agent state is unaffected.
- **Verification**:
  - [ ] macOS
  - [ ] Windows
  - [ ] Linux

---

### TC-11: App Restart & Automatic Reconnect

**Objective**: Verify persistence of paired settings and seamless polling resumption after app restart.

- **Preconditions**:
  - Bot is paired and functional (completed TC-01).
- **Steps**:
  1. Quit Coucou completely.
  2. Relaunch Coucou.
  3. Open **Settings… → Integrations → Telegram**.
  4. Trigger an agent turn completion or question.
- **Expected Results**:
  - Coucou reads the token from the OS keystore and pairing metadata from settings.
  - Status immediately displays **Connected** with bot username and chat ID.
  - Background polling resumes automatically without clicking any button.
  - The agent notification arrives in the Telegram chat normally.
- **Verification**:
  - [ ] macOS
  - [ ] Windows
  - [ ] Linux

---

### TC-12: Temporary Network Disconnection & Backoff Recovery

**Objective**: Verify resilience to temporary network drops without process crashes.

- **Preconditions**:
  - Bot is paired and polling actively.
- **Steps**:
  1. Disconnect network connectivity (turn off Wi-Fi or unplug ethernet).
  2. Observe Coucou logs: polling enters backoff retries (`1, 2, 4, 8, 16, 30, 60s`).
  3. Wait 30 seconds while offline.
  4. Reconnect network connectivity.
  5. Trigger an agent notification.
- **Expected Results**:
  - Coucou does not crash or display fatal unhandled exception dialogues.
  - Once connectivity returns, the polling loop recovers automatically on the next backoff interval.
  - Outgoing notifications resume delivering without restarting Coucou.
- **Verification**:
  - [ ] macOS
  - [ ] Windows
  - [ ] Linux

---

### TC-13: Duplicate App Instance (409 Conflict)

**Objective**: Verify detection and graceful display of duplicate polling instances.

- **Preconditions**:
  - Coucou is running and paired on Machine A.
- **Steps**:
  1. Launch a second Coucou instance or test script on Machine B configured with the identical bot token.
  2. Both instances attempt long polling `getUpdates`.
  3. Observe the status display in Coucou Settings on both machines.
- **Expected Results**:
  - The conflicting instance receives HTTP 409 Conflict from Telegram.
  - Coucou Settings displays the error badge: *"Another Coucou or bot instance is using this token."*
  - The application remains stable and does not enter a crash loop.
  - Closing the competing instance allows the remaining instance to resume polling cleanly.
- **Verification**:
  - [ ] macOS
  - [ ] Windows
  - [ ] Linux

---

### TC-14: Re-Pair Flow

**Objective**: Verify resetting chat association without re-entering the bot token.

- **Preconditions**:
  - Bot is paired with an existing chat.
- **Steps**:
  1. In Coucou Settings, click **Re-pair**.
  2. Observe the generation of a fresh pairing nonce and new pairing link.
  3. From a new Telegram chat or new device, open the pairing link and send `/start <new_nonce>`.
- **Expected Results**:
  - Previous chat ID is cleared.
  - Existing bot token is retained in the keystore.
  - After clicking Start, the new chat ID is saved and status confirms **Connected**.
  - Subsequent notifications are directed exclusively to the newly paired chat.
- **Verification**:
  - [ ] macOS
  - [ ] Windows
  - [ ] Linux

---

### TC-15: Complete Disconnect & Keystore Cleanup

**Objective**: Verify clean disconnection, background loop termination, and secret deletion.

- **Preconditions**:
  - Bot is paired and active.
- **Steps**:
  1. Open **Settings… → Integrations → Telegram**.
  2. Click **Disconnect**.
  3. Verify status resets to **Not configured**.
  4. Check the OS keystore:
     - macOS: `security find-generic-password -s "telegram-bot-token"` (returns item not found).
     - Windows: Verify `telegram-bot-token` is removed from Windows Credential Manager.
     - Linux: Verify `telegram-bot-token` is removed from Secret Service.
  5. Check `settings.json`: verify `telegramEnabled` is false and chat IDs are cleared.
  6. In Telegram, send a message to the bot.
- **Expected Results**:
  - Polling stops immediately.
  - Keystore secret is completely erased.
  - Local settings are scrubbed of pairing identifiers.
  - The bot does not respond to incoming messages or callbacks.
- **Verification**:
  - [ ] macOS
  - [ ] Windows
  - [ ] Linux
