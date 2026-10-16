# L1 Hook Gate: Offline App Decoupling & Split Tunnel Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent `nb-hook.py` from killing AI agents (like `agy`) when NotchBuddy/Coucou is closed or TunnelGuard is disabled (Point 1), and support split-tunnel VPNs by verifying routes to target AI domains instead of failing on `1.1.1.1`/`default` (Point 3).

**Architecture:** 
1. **App State Marker (Point 1):** `TunnelGuardWatchdog` maintains a lightweight runtime state file (`~/Library/Application Support/NotchBuddy/tunnelguard-state.json`) with app PID, `enabled` flag, and protected target list, updated on configuration changes and invalidated/cleaned up on application exit. `nb-hook.py` reads this file; if the app is not running (PID dead, socket missing, or state file absent/disabled) or the specific agent is not protected, the TunnelGuard kill-switch is bypassed.
2. **Split Tunnel & Target Domain Routing (Point 3):** `nb-hook.py` maps the invoking agent (`--agent antigravity`, `claude`, etc.) to its primary API endpoint (`generativelanguage.googleapis.com`, `claude.ai`, `chatgpt.com`, etc.). It verifies if the target domain routes through a VPN interface before falling back to `1.1.1.1` and `default`. In addition, VPN interface recognition is expanded beyond `utun*` to include common macOS VPN virtual adapters (`tun*`, `cscotun*`, `ppp*`, `fctun*`).

**Tech Stack:** Swift 6, AppKit, Python 3, macOS `/sbin/route`, POSIX IPC.

**Spec:** Fix user report: "кривой NotchBuddy/nb-hook.py - он просто ебашил процесс с vpn и без" by decoupling the hook when the app is offline and fixing false-positive drops on split-tunnel VPN configurations. (Timeout refactoring is explicitly reserved for another task).

---

## Global Constraints
- Target macOS deployment: macOS 15.0+ (Sequoia or later).
- Code generated in `HookServer.swift` (`nbHookPythonGitHub`) must remain self-contained with no third-party Python dependencies (only standard library: `sys`, `json`, `os`, `socket`, `subprocess`, `signal`).
- Preserves Fail-Closed behavior **only** when TunnelGuard is explicitly enabled and running for the target agent.
- Timeout values (`0.3s`) are left for a separate task per user instruction.
- Zero Swift 6 concurrency warnings or errors.
- Existing tests in `tests/test_tunnelguard_hook_gate.py` and `make test-tunnelguard-safe` must pass.

## Review Focus
1. **App Offline Bypass:** When NotchBuddy is not running (or socket absent / PID dead), running `agy` or `claude` through `nb-hook.py` must never kill the process, regardless of VPN state.
2. **TunnelGuard Disabled in Settings:** When NotchBuddy is running but `tunnelGuard.enabled == false`, `nb-hook.py` must bypass the kill-switch.
3. **Split Tunnel Support:** When `default` route and `1.1.1.1` point to `en0` (local Wi-Fi), but `generativelanguage.googleapis.com` routes through `utun*`, `agy` must NOT be killed.
4. **Extended VPN Adapters:** Virtual interfaces such as `cscotun0` (Cisco) or `ppp0` routing the target domain must be recognized as valid VPN interfaces.
5. **Atomic State File I/O:** Reading `tunnelguard-state.json` in `nb-hook.py` must be non-blocking, tolerant to partial writes/missing files, and fail open if the app state is not confirmed active.

---

### Task 1: Add TunnelGuard Runtime State Synchronization in `TunnelGuardWatchdog`

**Files:**
- Modify: `NotchBuddy/Sources/App/TunnelGuardWatchdog.swift`
- Test: `tests/TunnelGuardStateSyncTests.swift`

**Interfaces:**
- Produces: `~/Library/Application Support/NotchBuddy/tunnelguard-state.json` containing:
  ```json
  {
    "running": true,
    "enabled": true,
    "pid": 12345,
    "protected_targets": ["claude", "agy", "codex", "gemini", "cursor-agent"],
    "target_domains": {
      "antigravity": "generativelanguage.googleapis.com",
      "gemini": "generativelanguage.googleapis.com",
      "claude": "claude.ai",
      "codex": "chatgpt.com",
      "cursor": "cursor.sh"
    }
  }
  ```
- Lifecycle: written on `start()`, updated when `isEnabled` or `targets` change, updated with `"running": false` and `"enabled": false` on `stop()` / `applicationWillTerminate()`.

- [ ] **Step 1: Write unit test for state file persistence in `tests/TunnelGuardStateSyncTests.swift`**
Verify that `syncRuntimeStateFile()` writes valid JSON with current PID, enabled flag, and targets, and that `cleanupRuntimeStateFile()` marks running/enabled as false.

- [ ] **Step 2: Implement `syncRuntimeStateFile()` and `cleanupRuntimeStateFile()` in `TunnelGuardWatchdog.swift`**
Add state file management methods to `TunnelGuardWatchdog`. Call `syncRuntimeStateFile()` from `start()`, `loadPersistedSettings()`, and property observers for `isEnabled` and `targets`. Call `cleanupRuntimeStateFile()` in `stop()`.

- [ ] **Step 3: Run Swift tests to verify compilation and state sync**
Run: `swiftc tests/TunnelGuardStateSyncTests.swift NotchBuddy/Sources/App/TunnelGuardWatchdog.swift ...` or test script to confirm state file creation and cleanup.

---

### Task 2: Implement App-Offline & Protection Checks in `nb-hook.py` (Point 1)

**Files:**
- Modify: `NotchBuddy/Sources/App/HookServer.swift` (`nbHookPythonGitHub` template: `is_tunnelguard_active()`)
- Test: `tests/test_tunnelguard_hook_gate.py`

**Interfaces:**
- `is_tunnelguard_active(agent_name)`:
  1. Checks if `~/Library/Application Support/NotchBuddy/tunnelguard-state.json` exists.
  2. If missing or unreadable $\to$ returns `False` (app offline $\to$ no kill).
  3. Checks `data.get("running")` and `data.get("enabled")`. If either is `False` $\to$ returns `False`.
  4. Checks if app process is alive: `os.kill(data.get("pid"), 0)`. If `ProcessLookupError` $\to$ returns `False` (app crashed/closed $\to$ no kill).
  5. Checks if `agent_name` (e.g. `antigravity`, `claude`) is in `protected_targets` (or matches targets). If not $\to$ returns `False`.
  6. Checks if socket `~/Library/Application Support/NotchBuddy/nb.sock` exists. If not $\to$ returns `False`.
  7. If all checks pass $\to$ returns `True` (TunnelGuard is active, proceed to VPN verification).

- [ ] **Step 1: Write unit tests in `tests/test_tunnelguard_hook_gate.py` for `is_tunnelguard_active`**
Add tests covering:
- App offline (state file missing): returns `False`.
- App offline (PID dead / process not found): returns `False`.
- App online but `enabled == False`: returns `False`.
- App online and enabled, but agent not in `protected_targets`: returns `False`.
- App online, enabled, and agent protected: returns `True`.

- [ ] **Step 2: Update `main()` and helper functions in `nbHookPythonGitHub` in `HookServer.swift`**
Add `is_tunnelguard_active(agent_name)`. In `main()`:
Extract `--agent <name>` early (or default from argv).
```python
if is_tunnelguard_active(agent):
    if not verify_vpn_route(agent):
        tunnel_guard_kill_agent_and_exit()
```
If `is_tunnelguard_active()` is `False`, skip VPN verification entirely and proceed to normal hook relay execution.

- [ ] **Step 3: Run `python3 tests/test_tunnelguard_hook_gate.py` to confirm offline bypass**
Verify that all existing tests and new offline bypass tests pass.

---

### Task 3: Implement Split Tunnel & Target AI Domain Route Check (Point 3)

**Files:**
- Modify: `NotchBuddy/Sources/App/HookServer.swift` (`nbHookPythonGitHub` template: `verify_vpn_route`)
- Modify: `NotchBuddy/Sources/App/TunnelGuardWatchdog.swift` (`isVpnInterface`)
- Test: `tests/test_tunnelguard_hook_gate.py`

**Interfaces:**
- `is_vpn_interface(iface)`: Returns `True` if `iface.startswith(("utun", "tun", "tap", "ppp", "cscotun", "fctun", "ipsec"))`.
- `verify_vpn_route(agent_name)`:
  1. Determine target domain for agent:
     - `antigravity` / `gemini`: `generativelanguage.googleapis.com`
     - `claude` / `claude-desktop`: `claude.ai`
     - `codex`: `chatgpt.com`
     - `cursor`: `cursor.sh`
     (or lookup from `target_domains` in `tunnelguard-state.json`).
  2. If target domain is known:
     `iface = _get_route_interface(target_domain)`
     If `is_vpn_interface(iface)` $\to$ return `True` (Split tunnel protects this agent!).
  3. Fallback 1: `iface = _get_route_interface("1.1.1.1")`. If `is_vpn_interface(iface)` $\to$ return `True`.
  4. Fallback 2: `iface = _get_route_interface("default")`. If `is_vpn_interface(iface)` $\to$ return `True`.
  5. Return `False` (Traffic would leak over unprotected interface).

- [ ] **Step 1: Write unit tests in `tests/test_tunnelguard_hook_gate.py` for split-tunnel routing**
Add tests:
- `test_split_tunnel_target_domain_utun_default_en0`:
  `1.1.1.1` $\to$ `en0`, `default` $\to$ `en0`, but `generativelanguage.googleapis.com` $\to$ `utun3`.
  `verify_vpn_route("antigravity")` MUST return `True`.
- `test_extended_vpn_interfaces`:
  Test recognition of `cscotun0`, `ppp0`, `tun0` as valid VPN interfaces.
- `test_split_tunnel_leak_detected`:
  `generativelanguage.googleapis.com` $\to$ `en0` and `default` $\to$ `en0`.
  `verify_vpn_route("antigravity")` MUST return `False`.

- [ ] **Step 2: Update `verify_vpn_route` and `is_vpn_interface` in `nbHookPythonGitHub` (`HookServer.swift`)**
Implement target domain mapping, extended interface prefix checks, and prioritized route resolution.

- [ ] **Step 3: Update `isVpnInterface` in `TunnelGuardWatchdog.swift`**
Keep Swift L2 Watchdog and Python L1 Gate interface prefixes synchronized:
```swift
nonisolated static func isVpnInterface(_ iface: String) -> Bool {
    let prefixes = ["utun", "tun", "tap", "ppp", "cscotun", "fctun", "ipsec"]
    return prefixes.contains { iface.hasPrefix($0) }
}
```

- [ ] **Step 4: Run full test suite**
Run:
`python3 tests/test_tunnelguard_hook_gate.py`
`make test-tunnelguard-safe`

---

### Task 4: Hook File Regeneration & End-to-End Verification

**Files:**
- Verify: `HookServer.swift` write methods (`writeAgyHooks`, `installAndWriteClaudeHooksAppStore`, etc.)
- Test: Interactive/CLI test of `nb-hook.py` directly with mock inputs.

- [ ] **Step 1: Test hook generation with new Python template**
Ensure `HookServer.swift` compiles cleanly and generates the updated `nb-hook.py`.

- [ ] **Step 2: Run End-to-End simulation with offline app and split tunnel**
Run test simulating:
1. `nb-hook.py` executed by `agy` with NotchBuddy closed $\to$ Process continues normally (no SIGKILL).
2. `nb-hook.py` executed by `agy` with NotchBuddy open, split-tunnel active (`generativelanguage.googleapis.com` on `utun`) $\to$ Process continues normally (no SIGKILL).
3. `nb-hook.py` executed with NotchBuddy open, VPN fully down (`en0`) $\to$ Process denied and killed as intended.
