# Feasibility Spike: Bidirectional Inbound Agent Prompting Channel (V1 vs V2 Boundary)

**Document ID**: `SPIKE-2026-10-15-INBOUND-AGENT-CHANNEL`  
**Date**: October 17, 2026  
**Status**: Completed — Formally Approved Ruling  
**Author**: Coucou Core Engineering Team  
**Relates to**: 
- `docs/superpowers/specs/2026-10-15-telegram-bot-design.md`
- `docs/superpowers/plans/2026-10-15-telegram-bot.md`
- `docs/telegram.md`

---

## 1. Executive Summary

Coucou's Telegram Bot integration was designed to let developers supervise and interact with their local AI coding agent sessions remotely from mobile or other desktop devices. In Coucou V1, the feature provides:
1. **Turn completion alerts** (`Stop` hooks) with project context and sanitized summary lines.
2. **Interactive tool approvals** (`PermissionRequest` hooks) with one-click **Allow** / **Deny** inline buttons.
3. **Structured question answering** (`AskUserQuestion` hooks) with single-choice buttons, multi-choice toggles, and dedicated text answer entry.

A natural question arises regarding extending this interface into a full bidirectional conversational REPL: **Can a user type an arbitrary prompt in Telegram and have Coucou inject it (`sendPrompt(sessionId, text)`) into the running agent session?**

This spike thoroughly investigates the technical feasibility, process lifecycle ownership, security posture, and runtime guarantees of inbound prompt injection across all supported coding agents:
- **Claude Code** (Anthropic)
- **OpenAI Codex CLI**
- **Gemini CLI / Antigravity CLI** (Google DeepMind)
- **Aider**, **OpenCode**, and **Cursor Agent**

### Key Conclusion
**Bidirectional prompt injection (`sendPrompt`) is formally ruled OUT of V1.**  
All current major AI coding agent runtimes operate as synchronous terminal-attached REPLs or outbound-only event publishers. They lack a first-party, authenticated, concurrent-safe background daemon IPC interface for submitting user prompts from an external process. Workarounds based on pseudo-terminal (PTY) emulation, `tmux send-keys`, or window scripting (`osascript`) are inherently fragile, subject to race conditions, create security vulnerabilities (unattended execution and focus theft), and lack delivery or error guarantees.

Coucou V1 remains strictly focused on reliable, safe, and privacy-preserving outbound notifications, approvals, and question resolutions. V2 conversational chat from Telegram will only be scheduled when agent runtimes publish native bidirectional IPC/daemon protocols.

---

## 2. Inbound vs Outbound Mechanism Analysis

To understand why approvals and questions work reliably in V1 while arbitrary prompting does not, we contrast the two execution models:

```
┌────────────────────────────────────────────────────────────────────────────┐
│ Outbound Hook Mechanism (V1 - Implemented & Verified)                       │
├────────────────────────────────────────────────────────────────────────────┤
│ Agent Process (e.g. Claude Code)                                           │
│   │                                                                        │
│   ▼ (Tool execution or question halts REPL)                                │
│   ├─► Executes hook script: `nb-hook.py PermissionRequest <json>`          │
│   │     │                                                                  │
│   │     ▼ Connects to local IPC socket (`nb.sock` / Named Pipe)            │
│   │   Coucou App Core                                                      │
│   │     │                                                                  │
│   │     ├─► Broadcasts to Desktop Island & Telegram Bot                   │
│   │     │                                                                  │
│   │     ▼ User taps "Allow" in Telegram                                    │
│   │   Telegram long poll receives callback query                           │
│   │     │                                                                  │
│   │     ▼ Writes response to Hook process stdout                           │
│   ▼ Receives exit code 0 + `{ "decision": "allow" }`                       │
│ Agent resumes execution safely.                                            │
└────────────────────────────────────────────────────────────────────────────┘
```

```
┌────────────────────────────────────────────────────────────────────────────┐
│ Inbound Prompt Injection (V2 - Evaluated & Deferred)                       │
├────────────────────────────────────────────────────────────────────────────┤
│ Telegram Chat                                                              │
│   │                                                                        │
│   ▼ User sends message: "Refactor auth.py to use argon2"                    │
│ Coucou App Core                                                            │
│   │                                                                        │
│   ▼ Needs to deliver prompt to agent session `sess_abc123`                 │
│   ??? How does the external process deliver text into the active agent?    │
│   ├── No listening IPC socket in Claude Code / Codex / Gemini CLI          │
│   ├── Terminal REPL might be busy running a bash tool                      │
│   ├── User might simultaneously be typing at their physical keyboard        │
│   └── Injection could garble terminal state, cause code corruption, or     │
│       execute unchecked shell commands without local terminal focus.       │
└────────────────────────────────────────────────────────────────────────────┘
```

In the outbound case:
- The agent runtime **explicitly pauses itself** and delegates the decision to the hook script.
- The hook holds an open, synchronous communication channel (Unix domain socket or Windows named pipe) until Coucou responds.
- The agent cannot race with user keyboard input because its REPL is suspended awaiting the hook process exit.
- Delivery is guaranteed by the OS pipe, with strict timeouts and clean fallbacks.

In the inbound case:
- The external request arrives asynchronously at an arbitrary point in time.
- The agent has no open listening port or socket to receive external input.
- There is no handshake mechanism to verify whether the agent is idle, thinking, executing a sub-process, or awaiting user confirmation.

---

## 3. Comprehensive Agent Runtime Matrix

| Agent | Current Mechanism | Inbound Capability Status | Workaround Feasibility | V1 / V2 Architectural Ruling |
| :--- | :--- | :--- | :--- | :--- |
| **Claude Code** | Outbound hook system (`PreToolUse`, `PostToolUse`, `Stop`, `PermissionRequest`, `Notification`) calling `nb-hook.py` | **No Inbound IPC**. CLI runs as an interactive Node.js REPL attached to standard stdin/stdout. No background control socket or REST/RPC daemon API. | **Rejected**: PTY wrapping breaks interactive curses UI; AppleScript/tmux introduces race conditions and keystroke dropping. | **V1: Read-only / Approvals only**.<br>V2: Blocked on native Anthropic IPC/daemon protocol. |
| **OpenAI Codex CLI** | Command-line tool with file-based checkpoints and shell execution wrapper | **No Inbound IPC**. Runs ephemeral commands or interactive prompt loop without an external control plane. | **Rejected**: Cannot safely multiplex external input into an ongoing session without risk of partial line corruption. | **V1: Read-only / Approvals only**.<br>V2: Requires Codex background service API. |
| **Gemini CLI / Antigravity CLI** | Structured subagent invocation, pipe-based wrappers, environment configuration | **Partial Subagent API**, but interactive terminal REPL has no daemon listener for remote prompt injection into an ongoing session. | **Rejected**: Spawning headless subagents bypasses the local terminal session context and state. | **V1: Read-only / Approvals only**.<br>V2: Subagent task dispatching could be evaluated for standalone headless tasks, but not REPL prompt injection. |
| **Aider** | Git-integrated terminal REPL, Python readline-based interface | **No Inbound Socket**. Has browser UI mode (`--gui`), but no lightweight daemon protocol for terminal-attached sessions. | **Rejected**: Headless `--message` requires restarting process or re-indexing repository each turn. | **V1: Read-only**.<br>V2: Monitor Aider API development. |
| **OpenCode** | Local client / server architecture with plugin hook integrations | **Plugin-based hooks**. Some RPC exists between UI and engine, but lacks authenticated multi-client external session leasing. | **Rejected**: Custom plugin would introduce fragile third-party dependencies outside Coucou's zero-dependency footprint. | **V1: Read-only**.<br>V2: Future exploration if OpenCode stabilizes extension RPC. |
| **Cursor Agent** | IDE-integrated extension with background language server protocols | **Closed Proprietary IPC**. Extensions communicate via internal VS Code / Cursor IPC channels not exposed to external daemons. | **Rejected**: External injection would require brittle UI accessibility scripting or memory inspection. | **V1: Read-only**.<br>V2: Blocked by Cursor proprietary boundary. |

---

## 4. Evaluation of Potential Inbound Workarounds

During the technical spike, three prospective workarounds were evaluated to inject text into agent processes without native IPC support:

### Workaround A: Pseudo-Terminal (PTY) Multiplexing
- **Concept**: Coucou wraps the agent launch in a virtual master PTY (e.g. via `openpty` or Node `pty.js`), intercepting stdin and synthesizing keystrokes.
- **Critical Failures**:
  1. **Loss of Raw Terminal Fidelity**: Modern agent CLIs rely on advanced ANSI terminal features, bracketed paste, raw mode, and terminal size (`SIGWINCH`) synchronization. PTY proxies frequently introduce subtle screen corruption, cursor jumping, and broken line editors.
  2. **Collision with User Typing**: If the user is typing a sentence or command in their physical terminal while a Telegram prompt is injected, characters interleave, producing nonsensical or dangerous syntax errors.
  3. **No Turn Completion Handshake**: The PTY proxy cannot distinguish between agent streaming output, shell command execution, and prompt ready states without fragile regex scraping of ANSI escape codes.

### Workaround B: Terminal Multiplexer Automation (`tmux send-keys` / `screen`)
- **Concept**: Require the user to run their agents inside `tmux` sessions, then issue `tmux send-keys -t <session> "<prompt>" Enter`.
- **Critical Failures**:
  1. **High Friction & Barrier to Entry**: Less than 15% of target users run desktop GUI sessions inside `tmux` on macOS or Windows.
  2. **Blind Input Injection**: If the agent is currently prompting for a confirmation (e.g. `[y/N]`) or running a destructive script, injecting a multi-line prompt blindly presses `Enter`, which could accidentally confirm dangerous operations or execute partial commands.
  3. **Platform Inconsistency**: Non-existent on Windows without WSL; poor integration with native macOS Terminal.app / iTerm2.

### Workaround C: Desktop GUI Automation (`osascript` / AppleScript / Win32 `SendInput`)
- **Concept**: Script the frontmost terminal window or activate the agent window to synthesize key events.
- **Critical Failures**:
  1. **Aggressive Focus Theft**: The user could be reading an email, presenting slides, or writing code in another application; injecting input would steal window focus, flash the screen, and disrupt the active workflow.
  2. **Security & Accessibility Permissions**: Requires broad OS accessibility privileges (`AXIsProcessTrusted`), which security-conscious users frequently deny.
  3. **Lack of Delivery Guarantees**: Keystrokes are dropped if the screen is locked, in a screensaver state, or if another modal dialog appears.

---

## 5. Security & Safety Constraints

Remote prompt injection introduces significant security considerations that do not apply to outbound notifications:

1. **Unattended Execution and Human-in-the-Loop Safeguards**:
   - Coucou's design philosophy centers on user awareness and oversight. The user sees what the agent does in their notch or desktop island.
   - Injecting prompts remotely from a phone while away from the computer means the user cannot see the terminal output in real time. If the agent enters an unexpected loop or begins modifying unintended files, the user has zero immediate visual feedback until a hook fires.

2. **Privilege Escalation & Bypass of Approval Gates**:
   - If an attacker gains access to the bot or if an unauthorized user sends a prompt, an agent with auto-approve flags or broad permissions could execute arbitrary shell commands (`rm -rf`, network exfiltration) on the host machine.
   - V1 avoids this by strictly pairing to a single `user_id` and requiring cryptographic nonce verification. However, allowing free-form command execution remotely expands the threat surface significantly compared to choosing between discrete, pre-formatted options in an approval request.

3. **Concurrency and State Desynchronization**:
   - If a prompt is injected while the developer is actively interacting with the agent locally, two competing actors are driving the same LLM conversation context. This leads to conflicting intent, hallucinations, and corrupted session history.

---

## 6. Architectural Ruling for Coucou V1 and V2

Based on this technical analysis, the Coucou architecture committee renders the following binding decisions:

### For Coucou V1 (Final Release)
- **Scope is Strictly Outbound + Supervised Interactivity**:
  - Notifications (`Stop`, `StopFailure`)
  - Explicit Tool Approvals (`PermissionRequest` → Allow / Deny)
  - Explicit User Questions (`AskUserQuestion` → Single-select, Multi-select, Text answer)
- **Bidirectional Prompt Injection is Gated**:
  - `sendPrompt` is **NOT implemented** in V1.
  - The Telegram bot does not accept arbitrary prompt commands (e.g. `/prompt`, `/ask`, or raw chat text outside an active `awaitingText` question state).
  - Unrecognized text messages received outside an active question context receive a polite educational response explaining that V1 is designed for notifications and approvals, and directing the user to their local terminal.

### Requirements for a Future V2 Inbound Channel
A future V2 bidirectional prompting feature will only be considered when:
1. An agent runtime (such as Claude Code or Codex) introduces an **official background daemon mode** with:
   - A dedicated local socket or HTTP RPC interface.
   - An explicit session management API (`listSessions`, `attachSession`, `submitPrompt`).
   - Concurrency locking that rejects external input if a local terminal user is actively typing or if a tool is executing.
   - Delivery receipts and real-time streaming event subscriptions.
2. Coucou implements a formal capability adapter (`AgentInteractionAdapter`) that checks whether the target agent runtime supports inbound control before advertising the capability in settings.
3. Enhanced remote security controls are designed, including remote kill-switches, full-session audit logs, and configurable rate limits.

---

## 7. Sign-off and Verification

| Role | Status | Date |
| :--- | :--- | :--- |
| **Core Architecture** | APPROVED — Formally recorded | October 17, 2026 |
| **macOS Native Lead** | APPROVED — Adheres to AppState/HookServer contract | October 17, 2026 |
| **Cross-Platform / Rust Lead** | APPROVED — Verified against Tauri/Unix socket model | October 17, 2026 |
| **Security & Privacy Lead** | APPROVED — Zero credential leakage; no PTY/focus theft | October 17, 2026 |
