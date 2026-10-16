# Fix Dead Tunnel Prompt Overridden by False-Positive Split Tunnel Leak

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent transient DNS timeouts and route lookup delays during VPN network packet loss from falsely triggering Split-Tunnel Leak kill-switch, and ensure Dead Tunnel prompt is reliably displayed and held open in Dynamic Island without premature termination of agent processes.

**Architecture:** Refine `TunnelGuardNetworkWorker` so unresolvable domains or empty route lookups do not trigger split-tunnel leak warnings; update `TunnelGuardWatchdog` so dead tunnel freeze and prompt takes precedence and is not aborted by network timeouts; update `IslandWindowController` so `fsm.isHeldOpen` preserves the prompt window until user action.

**Tech Stack:** Swift 6, AppKit, SwiftUI, Dynamic Island / NotchBuddy.

## Global Constraints
- Instant `SIGKILL` must be preserved for genuine leaks (`isVpn == false` where default route points to `en0`, or a target domain route explicitly resolves to a non-VPN interface like `en0`).
- Transient DNS lookup failures or route timeouts must never be classified as split-tunnel leaks.
- While `isDeadTunnelPromptActive == true`, agents are already frozen via `SIGSTOP`. The prompt must stay open in Dynamic Island until the user clicks an action or the tunnel recovers.
- All existing tests in `make test-tunnelguard-safe` must remain 100% green.

## Review Focus
- DNS lookup failures during packet loss must not set `targetDomainsOk = false`.
- Route timeout (`iface == ""`) must not set `targetDomainsOk = false`.
- Dead tunnel detection must take precedence over split-tunnel timeouts.
- Dynamic Island state machine (`fsm.isHeldOpen`) must keep `.deadTunnelPrompt` visible without auto-collapsing.

---

### Task 1: Fix Split-Tunnel Leak Detection in `TunnelGuardNetworkWorker`

**Files:**
- Modify: `NotchBuddy/Sources/App/TunnelGuardNetworkWorker.swift:250-265`

- [ ] Step 1: Update Split-Tunnel domain check in `TunnelGuardNetworkWorker.checkStatus`:
  - When iterating over `targetDomains`:
    - Call `resolveDomain(domain)`.
    - If `resolvedIp.isEmpty`, use any existing cached IP from `dnsCache[domain]`.
    - If `resolvedIp` is still empty, do NOT mark `targetDomainsOk = false`. An unresolvable domain cannot leak traffic. Continue to next domain.
    - If `resolvedIp` is present, check `domainIface = getRouteInterface(dest: resolvedIp, timeoutSeconds: routeTimeout)`.
    - Only mark `targetDomainsOk = false` if `!domainIface.isEmpty && !TunnelGuardWatchdog.isVpnInterface(domainIface)`. If `domainIface.isEmpty` (route lookup timed out or failed), do not treat it as a leak.
- [ ] Step 2: In `resolveDomain`, retain the cached IP indefinitely as fallback if subsequent `getaddrinfo` calls fail during network hiccups.
- [ ] Step 3: Run `make test-tunnelguard-safe` in worktree to verify existing tests pass.
- [ ] Step 4: Commit changes:
  `git commit -m "fix(tunnelguard): do not treat DNS failure or route timeout as split-tunnel leak"`

---

### Task 2: Prevent Split-Tunnel Timeouts from Aborting Dead Tunnel Prompt in `TunnelGuardWatchdog`

**Files:**
- Modify: `NotchBuddy/Sources/App/TunnelGuardWatchdog.swift:240-310`

- [ ] Step 1: In `handleNetworkSnapshot`:
  - Priority ordering:
    - If `snapshot.deadTunnelDetected`: `failureReason = "Завис VPN туннель (нет ответа на пинг)"`.
    - Else if `splitTunnelCheck && !snapshot.targetDomainsOk`: `failureReason = "Утечка трафика целевых AI-доменов в незащищенный интерфейс"`.
    - Else if `!splitTunnelCheck && !snapshot.isVpn`: `failureReason = "VPN отключен! Обнаружен интерфейс: ..."`
- [ ] Step 2: In Level-Trigger (`!wasHealthy && !currentlyHealthy`):
  - In `if isDeadTunnelPromptActive`:
    - Only abort prompt and escalate to hard kill if the connection actually dropped to a non-VPN interface (`!snapshot.isVpn` or `snapshot.iface == "en0"`), OR if `splitTunnelCheck && !snapshot.targetDomainsOk && !snapshot.deadTunnelDetected`.
    - If `snapshot.deadTunnelDetected == true`, do NOT dismiss the prompt or execute hard kill on repeated ticks! Keep the agents suspended (`SIGSTOP`) and prompt active.
- [ ] Step 3: Run `make test-tunnelguard-safe` in worktree to verify Watchdog prompt tests pass.
- [ ] Step 4: Commit changes:
  `git commit -m "fix(tunnelguard): prevent dead tunnel prompt from being aborted on level-triggered ticks"`

---

### Task 3: Keep Prompt Open in Dynamic Island (`IslandWindowController`)

**Files:**
- Modify: `NotchBuddy/Sources/App/IslandWindowController.swift:329-331`
- Modify: `NotchBuddy/Sources/App/AppState.swift:32-37`

- [ ] Step 1: In `IslandWindowController.swift`:
  - Update `fsm.isHeldOpen` to include `.deadTunnelPrompt` and `.securityPanic`:
    ```swift
    fsm.isHeldOpen = {
        AppState.shared.pendingApproval != nil ||
        AppState.shared.voiceMailDraft != nil ||
        AppState.shared.view == .deadTunnelPrompt ||
        AppState.shared.view == .securityPanic
    }
    ```
- [ ] Step 2: In `AppState.swift`:
  - In `triggerDeadTunnelPrompt(...)`, post notification or ensure `fsm.openedExternally()` is synchronized so FSM does not collapse the island.
- [ ] Step 3: Run `make build` in worktree.
- [ ] Step 4: Commit changes:
  `git commit -m "fix(island): hold island open for deadTunnelPrompt and securityPanic"`

---

### Task 4: Add Automated Unit Tests for Dead Tunnel Prompt & Split-Tunnel Safety

**Files:**
- Create: `tests/TunnelGuardSplitLeakSafetyTests.swift`
- Modify: `scripts/test-tunnelguard-phase3-safe.sh`

- [ ] Step 1: Write `tests/TunnelGuardSplitLeakSafetyTests.swift`:
  - Verify that when DNS fails (`resolveDomain` returns `""`), `checkStatus` returns `targetDomainsOk == true`.
  - Verify that when route query returns empty string (`""`), `checkStatus` returns `targetDomainsOk == true`.
  - Verify that only when `domainIface == "en0"` does `checkStatus` return `targetDomainsOk == false`.
  - Verify that when `isDeadTunnelPromptActive == true` and repeated ticks occur with `deadTunnelDetected == true`, the prompt remains active and processes are NOT killed.
- [ ] Step 2: Wire `tests/TunnelGuardSplitLeakSafetyTests.swift` into `scripts/test-tunnelguard-phase3-safe.sh`.
- [ ] Step 3: Run `make test-tunnelguard-safe` and verify that all test suites pass.
- [ ] Step 4: Commit changes:
  `git commit -m "test(tunnelguard): add unit tests for DNS failure safety and prompt persistence"`

---

### Task 5: End-to-End Build and Verification

- [ ] Step 1: Run `make test-tunnelguard-safe` in worktree and confirm all 9 safe test suites pass.
- [ ] Step 2: Run `make build` and verify clean build with `** BUILD SUCCEEDED **`.
- [ ] Step 3: Mark all plan checkboxes complete in `docs/superpowers/plans/2026-10-16-fix-dead-tunnel-split-leak-override.md`.
- [ ] Step 4: Commit documentation updates:
  `git commit -m "docs: complete dead tunnel split leak override plan"`
