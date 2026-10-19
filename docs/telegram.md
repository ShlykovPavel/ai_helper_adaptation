# Coucou Telegram Bot

Coucou connects directly to your own personal Telegram bot so you can step away from your desk while your AI coding agents (Claude Code, Codex, and others) are working. Get notified when an agent finishes, answer questions with interactive choices or free-form text, and approve or deny permission requests right from your phone.

Coucou runs with the exact same capabilities and privacy guarantees across **macOS**, **Windows**, and **Linux**.

---

## Architecture & How It Works

```
┌──────────────────────────────────────────────┐
│ Your Computer (macOS / Windows / Linux)      │
│                                              │
│  ┌───────────────┐     ┌──────────────────┐  │
│  │ Coding Agent  │────►│ Coucou Runtime   │  │
│  │ (Claude/Codex)│◄────│ (macOS / Tauri)  │  │
│  └───────────────┘     └────────┬─────────┘  │
│                                 │            │
│                  Direct HTTPS   │ Long Poll  │
│                  (outbound only)│ getUpdates │
└─────────────────────────────────┼────────────┘
                                  ▼
                   ┌────────────────────────────┐
                   │  https://api.telegram.org  │
                   └──────────────┬─────────────┘
                                  │
                                  ▼
                   ┌────────────────────────────┐
                   │ Your Phone / Telegram App  │
                   │ (iOS, Android, Desktop)    │
                   └────────────────────────────┘
```

- **Direct outbound connection**: Coucou communicates directly from your machine to `https://api.telegram.org` over HTTPS.
- **No intermediary servers**: No Coucou backend, cloud proxy, relay server, or webhook forwarder is involved.
- **Long polling**: Updates are retrieved using standard Telegram Bot API `getUpdates` long polling. You do not need a public IP, domain name, or open router ports.

---

## Getting Started

### 1. Create a Bot with @BotFather

1. Open Telegram and search for the official [`@BotFather`](https://t.me/BotFather) bot (verified checkmark).
2. Send the command:
   ```text
   /newbot
   ```
3. Follow the prompts:
   - Enter a display name for your bot (for example, `Mochi Agent Companion`).
   - Enter a unique username ending in `bot` (for example, `my_coucou_agent_bot`).
4. `@BotFather` will reply with a confirmation message containing the **HTTP API token**.
   > Keep this token private. It grants access to control your bot.

---

### 2. Configure the Token in Coucou

1. Open Coucou Settings:
   - **macOS**: Click the Coucou icon in the menu bar or island → **Settings…** → **Integrations** → **Telegram**.
   - **Windows & Linux**: Open Coucou → **Settings…** → **Integrations** → **Telegram**.
2. Paste the HTTP API token into the **Bot Token** field.
3. Click **Save**.
4. Once saved:
   - The token is securely stored in your operating system's native keystore.
   - The input field shows `(stored)` and clears the plaintext value. The token is write-only and cannot be read back by the UI.

---

### 3. Test the Token

Click the **Test token** button next to the input field:
- Coucou calls `getMe` against the Telegram Bot API to confirm token validity and fetch the bot's username.
- A success indicator confirms that the token is valid and displays your bot's username (for example, `@my_coucou_agent_bot`).
- If invalid or revoked, a safe error badge appears without leaking the token or raw API response.

---

### 4. Pair Your Private Chat via Deep Link

To ensure only you can interact with your agents, Coucou requires an explicit one-time pairing step:

1. Click the **Pair** button in Settings.
2. Coucou generates a single-use, cryptographically secure 128-bit random nonce (base64url-encoded) and generates a pairing link:
   ```text
   https://t.me/<bot_username>?start=<nonce>
   ```
3. Coucou opens this link in your default browser/Telegram client, or you can click **Copy link** to open it on your phone.
4. In your Telegram chat with the bot, click the **Start** button (which sends `/start <nonce>`).
5. Coucou verifies the incoming update:
   - **Validity period**: The nonce is valid for **10 minutes**.
   - **Private chat restriction**: The request must originate from a private direct chat (`chat.type == "private"`). Channels, groups, and supergroups are immediately ignored and rejected.
   - **Single-use**: Once consumed, the nonce is invalidated.
6. Upon successful verification:
   - Your bot sends a confirmation message to your chat: *"Coucou Telegram bot connected!"*
   - Coucou Settings updates to **Connected**, displaying your bot's username and your masked chat ID (for example, `Chat: •••••1234`).

---

## Privacy & Security Guarantees

Coucou was designed from the ground up for strict local-first privacy:

| Security Property | Implementation Guarantee |
|---|---|
| **User Ownership** | The bot is entirely yours. Coucou uses no shared bot tokens, shared databases, or third-party cloud infrastructure. |
| **No Middleman** | All HTTPS requests go directly from your local machine to `https://api.telegram.org`. No proxy, telemetry, or analytics. |
| **OS Secure Keystore** | The bot token is stored exclusively in OS credential storage: macOS Keychain (`telegram-bot-token`), Windows Credential Manager, or Linux Secret Service (GNOME Keyring / KWallet). |
| **Never Written to Disk** | The bot token is never saved to `settings.json`, never logged to stdout/stderr, never included in crash reports, and never exposed in the front-end DOM. |
| **Opaque Action References** | Inline action buttons use an opaque 16-byte base64url random reference (`c:<ref>:<op>`) fitting within Telegram's 64-byte `callback_data` limit. Commands, file paths, and auth tokens are never placed in callback data. |
| **120-Second Action TTL** | Interactive actions are kept in an in-memory registry of at most 64 items, each expiring after 120 seconds. Once answered or expired, subsequent button presses show an alert and perform no action. |
| **Safe Message Truncation** | Outgoing notifications are capped at 3,500 Unicode scalars (well within Telegram's 4,096 character limit) to prevent API payload errors. Formatted text avoids unsafe HTML/Markdown injection. |
| **Private Chat Isolation** | Only messages and callbacks from your paired `chat_id` and `user_id` are processed. Updates from unauthorized users or group chats are silently dropped. |

---

## Notification Preferences

In **Settings… → Integrations → Telegram**, you can independently toggle the types of notifications sent to Telegram:

- **Completions and stops** (`notifyFinished`):
  Sends a message when an agent completes a turn (`Stop`), containing the agent name, project directory, and a concise summary of the outcome. Repeated identical completions are automatically deduplicated.
- **Questions** (`notifyQuestions`):
  Sends prompts for `AskUserQuestion` with inline keyboard buttons.
  - **Single-select**: Tapping an option immediately submits the answer to the agent and edits the Telegram message to display the chosen response.
  - **Multi-select**: Allows toggling checkboxes on multiple options, followed by an inline **Submit** button.
  - **Text fallback**: An inline **Reply by text** option puts the bot into awaiting-text mode for one message from your paired account, passing your typed response back to the agent.
- **Approvals** (`notifyApprovals`):
  Sends permission requests (`PermissionRequest`) showing the requested tool and command/path with **Allow** and **Deny** buttons. Tapping a button transmits the decision to your agent and updates the message in place.

> [!NOTE]
> **No Slot Limit Impact**: Telegram notification toggles operate independently in the background. Unlike active pills in the notch / island (which are limited to four active slots), Telegram does not consume an integration slot.

---

## Troubleshooting

### 401 Unauthorized (Invalid or Revoked Token)

- **Symptom**: Settings displays `Invalid bot token. Check token in BotFather.` or test token fails.
- **Cause**: The token was mistyped, revoked in BotFather, or deleted.
- **Resolution**:
  1. Open `@BotFather` in Telegram.
  2. Send `/mybots`, select your bot, and navigate to **API Token**.
  3. If revoked, generate a new token via `/revoke` or `/token`.
  4. Paste the new token into Coucou Settings and click **Save**.

---

### 409 Conflict (Multiple Instances Running)

- **Symptom**: Settings displays `Another Coucou or bot instance is using this token.`
- **Cause**: Telegram Bot API permits only one active `getUpdates` long-polling connection per bot token. This error occurs if:
  - Coucou is open simultaneously on two different computers with the same bot token.
  - Another script or application is polling the same bot token.
- **Resolution**:
  - Close the other Coucou instance or script.
  - If you use Coucou on multiple computers (for example, a Mac and a Windows desktop), create a dedicated bot via `@BotFather` for each machine.

---

### 429 Too Many Requests (Rate Limited)

- **Symptom**: Log shows rate limiting or notifications are briefly delayed.
- **Cause**: Exceeded Telegram's message rate limit (typically 30 messages per second across chats, or 1 message per second in a single chat).
- **Resolution**:
  - Coucou automatically detects the `retry_after` parameter in Telegram's response and pauses outgoing requests for the requested number of seconds.
  - No user intervention is required; normal delivery resumes automatically.

---

### Network Disconnection & Automatic Recovery

- **Symptom**: Internet connectivity is lost while Coucou is running.
- **Behavior**:
  - Coucou handles network errors gracefully without crashing.
  - Polling enters an exponential backoff schedule:
    `1 → 2 → 4 → 8 → 16 → 30 → 60` seconds.
  - When connectivity returns, Coucou automatically reconnects and resumes polling without requiring an app restart.

---

### macOS Keychain Password Prompt on Launch or Update

- **Symptom**: macOS displays a system dialog: `«Coucou» wants to use confidential information stored in «fr.louisraille.NotchBuddy» in your keychain.`
- **Cause**: The bot token is securely stored in the macOS Login Keychain. When Coucou is updated or recompiled locally, its binary signature changes. macOS security prompts for permission to ensure that you trust the updated application to access the existing Keychain entry.
- **Resolution**:
  - Enter your Mac login password and click **Always Allow** (or **Allow**).
  - macOS will record the permission for the updated binary and will not prompt again.

---

## Managing Your Connection

### Re-pairing to a New Chat or Account

If you switch phones, change Telegram accounts, or want to refresh your pairing:
1. Open **Settings… → Integrations → Telegram**.
2. Click **Re-pair**.
3. Coucou clears the current `chat_id` and `user_id` while preserving your stored bot token.
4. A new 10-minute pairing link is generated.
5. Open the link from your new Telegram account and click **Start**.

---

### Disconnecting the Bot

To completely remove the Telegram bot integration:
1. Open **Settings… → Integrations → Telegram**.
2. Click **Disconnect**.
3. Coucou will:
   - Terminate the background polling worker.
   - Invalidate all pending in-memory action references.
   - Delete the bot token from your operating system's keystore (macOS Keychain, Windows Credential Manager, or Linux Secret Service).
   - Clear saved chat IDs and bot username from local settings.
   - Reset the integration status to **Not configured**.
