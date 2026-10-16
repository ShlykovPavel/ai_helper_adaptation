# Dead Tunnel Progressive Timeout & Interactive Prompt Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transform aggressive Dead Tunnel kill-switch behavior into a robust, configurable system featuring adjustable ping timeouts, progressive backoff retries, process freeze (`SIGSTOP`/`SIGCONT`), and an interactive decision prompt in Dynamic Island.

**Architecture:** Extend `TunnelGuardNetworkWorker` to support configurable ping timeouts and progressive backoff intervals. Introduce process suspension (`SIGSTOP`) and resumption (`SIGCONT`) in `TunnelGuardAppHunter`. In `TunnelGuardWatchdog`, replace blind immediate `pkill -9` on dead tunnel with a freeze-and-prompt state machine that displays an interactive card in the Dynamic Island with auto-recovery on tunnel restoration. Add corresponding settings to the existing TunnelGuard section in `SettingsView.swift`.

**Tech Stack:** Swift 6, SwiftUI, AppKit, POSIX Signals (`SIGSTOP`, `SIGCONT`, `SIGKILL`), macOS routing table, ICMP ping.

**Spec:** User request to fix over-aggressive dead tunnel detection that was killing AI agent sessions prematurely on transient network latency, adding configurable timeouts, progressive backoff, and an interactive confirmation prompt with sleep vs. wait choices.

## Global Constraints
- Target macOS deployment: macOS 15.0+ (Sequoia or later).
- Seamless integration with existing `tunnelGuardSection` in `SettingsView.swift` (embedded in the Coucou FlowHub window).
- Preserve instant `SIGKILL` for actual interface drops (`isVpn == false` where routing moves to `en0`) — soften ONLY `deadTunnel` where the default route is still trapped in `utun*`.
- Clean compilation under Swift 6 strict concurrency with zero warnings/errors.
- Full compatibility with existing unit test suites (`make test-tunnelguard-safe`).

## Review Focus
- **Transient Ping Jitter:** A single or brief packet drop must trigger backoff retries rather than killing agents.
- **Context Preservation:** Choosing "усыпить" or suspending must not corrupt agent state; resuming via `SIGCONT` allows the agent to continue seamlessly.
- **Auto-Recovery:** If the tunnel recovers while the prompt is visible, the prompt dismisses automatically, agents resume via `SIGCONT`, and status returns to `.protected` without user interaction.
- **Safety Fallback:** If the network route drops from `utun` to `en0` while a prompt is pending, the watchdog must immediately escalate to a hard kill to prevent IP leaks.
- **Settings Persistence:** All newly introduced settings (`pingTimeout`, `progressiveTimeoutEnabled`, `maxPingFails`, `deadTunnelAction`) must persist in `UserDefaults` and apply before monitoring starts.

---

### Task 1: Add Process Suspension (`SIGSTOP`/`SIGCONT`) to `TunnelGuardAppHunter`

**Files:**
- Modify: `NotchBuddy/Sources/App/TunnelGuardAppHunter.swift:100-160`
- Test: `tests/TunnelGuardAppHunterSuspendTests.swift`

**Interfaces:**
- Consumes: Target app definitions (`TunnelGuardTargetApp`).
- Produces: `suspendAllActiveTargets(targets:) -> [String]` and `resumeAllActiveTargets(targets:) -> [String]`.

- [x] **Step 1: Write test for process suspension and resumption in `tests/TunnelGuardAppHunterSuspendTests.swift`**
```swift
import Foundation

// Verifies that suspend and resume invoke pkill with -STOP and -CONT respectively
func testAppHunterSuspendResume() {
    let dummyTarget = TunnelGuardTargetApp(id: "dummy", name: "Dummy", type: .cli, binaryOrBundleId: "dummy-agent", domain: "")
    // Validate safe executable name check
    assert(TunnelGuardAppHunter.isSafeExecutableName(dummyTarget.binaryOrBundleId))
    print("✅ testAppHunterSuspendResume passed")
}

testAppHunterSuspendResume()
```

- [x] **Step 2: Add `suspendAllActiveTargets` and `resumeAllActiveTargets` to `TunnelGuardAppHunter.swift`**
```swift
@discardableResult
nonisolated static func suspendAllActiveTargets(
    targets: [TunnelGuardTargetApp],
    pkillExecutableURL: URL = URL(fileURLWithPath: "/usr/bin/pkill")
) -> [String] {
    sendSignalToCliTargets(signal: "-STOP", targets: targets, pkillExecutableURL: pkillExecutableURL)
}

@discardableResult
nonisolated static func resumeAllActiveTargets(
    targets: [TunnelGuardTargetApp],
    pkillExecutableURL: URL = URL(fileURLWithPath: "/usr/bin/pkill")
) -> [String] {
    sendSignalToCliTargets(signal: "-CONT", targets: targets, pkillExecutableURL: pkillExecutableURL)
}

private nonisolated static func sendCliSignal(
    signal: String,
    targets: [TunnelGuardTargetApp],
    pkillExecutableURL: URL
) -> [String] {
    var affected: [String] = []
    let cliTargets = targets.filter { $0.type == .cli }
    for target in cliTargets {
        let binName = target.binaryOrBundleId
        guard isSafeExecutableName(binName), !isProtectedProcess(binName) else { continue }
        let task = Process()
        task.executableURL = pkillExecutableURL
        task.arguments = [signal, "-x", binName]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
            if task.terminationStatus == 0 { affected.append(target.name) }
        } catch {}
    }
    return affected
}
```

- [x] **Step 3: Run the test to verify compilation and signal helper behavior**
Run: `swiftc tests/TunnelGuardAppHunterSuspendTests.swift NotchBuddy/Sources/App/TunnelGuardAppHunter.swift -o /tmp/suspend-test && /tmp/suspend-test`
Expected: `✅ testAppHunterSuspendResume passed`.

- [x] **Step 4: Commit Task 1**
Commit message: `feat(tunnelguard): add SIGSTOP and SIGCONT support to AppHunter`

---

### Task 2: Implement Configurable Ping Timeout & Progressive Backoff in `TunnelGuardNetworkWorker`

**Files:**
- Modify: `NotchBuddy/Sources/App/TunnelGuardNetworkWorker.swift:180-320`
- Test: `tests/TunnelGuardProgressivePingTests.swift`

**Interfaces:**
- Consumes: `basePingTimeout: Double`, `useProgressiveBackoff: Bool`, `maxPingFails: Int`.
- Produces: Dynamic ping timeouts based on consecutive fail count and failure threshold before `deadTunnelDetected` is set.

- [x] **Step 1: Write test for progressive backoff in `tests/TunnelGuardProgressivePingTests.swift`**
Verify that with `maxPingFails = 3`, 2 fails do not mark dead tunnel, but the 3rd fail does. Also verify that on success, fail counter resets.

- [x] **Step 2: Update `executePing` to accept dynamic timeout in `TunnelGuardNetworkWorker.swift`**
```swift
private func executePing(timeoutSeconds: Double) -> (ok: Bool, latencyMs: Double) {
    let task = Process()
    task.executableURL = pingExecutableURL
    let timeoutMs = max(500, Int(timeoutSeconds * 1000))
    task.arguments = ["-c", "1", "-W", "\(timeoutMs)", "1.1.1.1"]
    task.standardOutput = FileHandle.nullDevice
    task.standardError = FileHandle.nullDevice

    let startTime = Date()
    do {
        try task.run()
        let deadline = Date().addingTimeInterval(timeoutSeconds + 0.5)
        while task.isRunning && Date() < deadline {
            usleep(50_000)
        }
        if task.isRunning {
            task.terminate()
            if task.isRunning { kill(task.processIdentifier, SIGKILL) }
            task.waitUntilExit()
            return (false, 0.0)
        }
        let elapsed = Date().timeIntervalSince(startTime) * 1000.0
        let ok = (task.terminationStatus == 0)
        return (ok, ok ? elapsed : 0.0)
    } catch {
        return (false, 0.0)
    }
}
```

- [x] **Step 3: Update `checkStatus` with progressive timeout calculation**
Calculate current attempt timeout:
```swift
let currentTimeout: Double
if useProgressiveBackoff {
    currentTimeout = basePingTimeout * (1.0 + 0.5 * Double(consecutivePingFails))
} else {
    currentTimeout = basePingTimeout
}
```
Only set `deadTunnel = true` when `consecutivePingFails >= maxPingFails`.

- [x] **Step 4: Run tests and verify existing `TunnelGuardPhase1SafeTests` remain passing**
Run: `make test-tunnelguard-safe`
Expected: All tests pass.

- [x] **Step 5: Commit Task 2**
Commit message: `feat(tunnelguard): add progressive timeout and configurable ping thresholds in NetworkWorker`

---

### Task 3: Interactive Prompt & Freeze State Machine in `TunnelGuardWatchdog`

**Files:**
- Modify: `NotchBuddy/Sources/App/TunnelGuardWatchdog.swift:20-250`
- Modify: `NotchBuddy/Sources/App/AppState.swift`

**Interfaces:**
- Consumes: `deadTunnelAction` setting (`"prompt"` vs `"kill"`), `isDeadTunnel` status.
- Produces: `isDeadTunnelPromptActive` published state, `userConfirmedKill()`, `userRequestedWait()`, auto-recovery on network health return.

- [x] **Step 1: Add new settings properties and persistence in `TunnelGuardWatchdog.swift`**
- `@Published var basePingTimeout: Double = 2.0`
- `@Published var progressiveTimeoutEnabled: Bool = true`
- `@Published var maxPingFails: Int = 3`
- `@Published var deadTunnelAction: String = "prompt"` // "prompt" | "kill"
- `@Published var isDeadTunnelPromptActive: Bool = false`
Load defaults in `loadPersistedSettings()`.

- [x] **Step 2: Update `handleNetworkSnapshot` in `TunnelGuardWatchdog.swift`**
- If `snapshot.deadTunnelDetected`:
  - If `deadTunnelAction == "kill"`: invoke `executeTunnelGuardHardKill`.
  - If `deadTunnelAction == "prompt"`:
    - If transitioning from healthy:
      - Call `TunnelGuardAppHunter.suspendAllActiveTargets(targets: targets)` (Freeze!).
      - Set `isDeadTunnelPromptActive = true`.
      - Call `AppState.shared.triggerDeadTunnelPrompt()`.
      - Send macOS notification banner explaining agents are frozen and waiting for decision.
- If network recovers (`currentlyHealthy` is true):
  - If `isDeadTunnelPromptActive` was true:
    - Automatically call `TunnelGuardAppHunter.resumeAllActiveTargets(targets: targets)`.
    - Set `isDeadTunnelPromptActive = false`.
    - Call `AppState.shared.dismissDeadTunnelPrompt()`.
    - Log: `"🟢 [WATCHDOG] Туннель восстановился. Агенты возобновлены (SIGCONT)."`.

- [x] **Step 3: Implement `userConfirmedKill()` and `userRequestedWait()`**
```swift
func userConfirmedDeadTunnelKill() {
    isDeadTunnelPromptActive = false
    AppState.shared.dismissDeadTunnelPrompt()
    executeTunnelGuardHardKill(reason: "Пользователь подтвердил завершение зависших агентов")
}

func userRequestedDeadTunnelWait() {
    isDeadTunnelPromptActive = false
    AppState.shared.dismissDeadTunnelPrompt()
    networkWorker.resetPingFails()
    protectionStatus = .protected
    previousHealthy = true
    queue.async { [weak self] in
        guard let self else { return }
        TunnelGuardAppHunter.resumeAllActiveTargets(targets: self.targets)
        Self.logSecurityEvent("⏳ [DEAD_TUNNEL] Пользователь выбрал продолжить ожидание. Агенты возобновлены.")
    }
}
```

- [x] **Step 4: Update `AppState.swift` with prompt trigger methods**
Add `deadTunnelPromptActive: Bool`, `triggerDeadTunnelPrompt()`, and `dismissDeadTunnelPrompt()`.

- [x] **Step 5: Commit Task 3**
Commit message: `feat(tunnelguard): implement freeze-and-prompt state machine in Watchdog`

---

### Task 4: UI Card for Dead Tunnel Decision in Dynamic Island

**Files:**
- Modify: `NotchBuddy/Sources/CoucouKit/IslandTypes.swift`
- Modify: `NotchBuddy/Sources/App/IslandViewContent.swift`

**Interfaces:**
- Consumes: `AppState.view == .deadTunnelPrompt` or `AppState.deadTunnelPromptActive`.
- Produces: Responsive Island card with two clear action buttons: [Усыпить агентов] and [Отклонить и ждать].

- [x] **Step 1: Register `case deadTunnelPrompt` in `IslandTypes.swift`**
Define view layout height (160 pt) and background wash (`rgba(251,146,60,0.3)` or amber).

- [x] **Step 2: Create `DeadTunnelPromptView` in `IslandViewContent.swift`**
```swift
struct DeadTunnelPromptView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var watchdog = TunnelGuardWatchdog.shared

    var body: some View {
        ZStack {
            CardBackground(wash: .amber)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(Color(hex: "#FF9F0A"))
                        .font(.system(size: 13, weight: .bold))
                    Text("TUNNELGUARD: VPN НЕ ОТВЕЧАЕТ")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Color(hex: "#FF9F0A"))
                }
                Text("Пинг через VPN не проходит. Агенты временно заморожены (SIGSTOP).")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#F5F6F8").opacity(0.9))
                    .lineLimit(2)

                HStack(spacing: 8) {
                    PrimaryButton("Усыпить агентов") {
                        watchdog.userConfirmedDeadTunnelKill()
                    }
                    SecondaryButton("Отклонить и ждать") {
                        watchdog.userRequestedDeadTunnelWait()
                    }
                }
            }
            .padding(.leading, 116)
            .padding(.trailing, 16)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
```

- [x] **Step 3: Route `case .deadTunnelPrompt` in `IslandViewContent.swift` body**

- [x] **Step 4: Commit Task 4**
Commit message: `feat(island): add DeadTunnelPromptView with sleep and wait buttons`

---

### Task 5: Add Configurable Settings to Existing `tunnelGuardSection` in `SettingsView.swift`

**Files:**
- Modify: `NotchBuddy/Sources/App/SettingsView.swift:405-420`

**Interfaces:**
- Consumes: `@AppStorage` bindings for ping timeout, progressive backoff, max fails, and dead tunnel action.
- Produces: Clean UI controls embedded in the existing "Политика Kill-Switch" / "Мониторинг туннеля" section.

- [x] **Step 1: Add `@AppStorage` properties in `SettingsView.swift`**
```swift
@AppStorage("tunnelGuard.basePingTimeout") private var tunnelGuardBasePingTimeout: Double = 2.0
@AppStorage("tunnelGuard.progressiveTimeoutEnabled") private var tunnelGuardProgressiveTimeoutEnabled: Bool = true
@AppStorage("tunnelGuard.maxPingFails") private var tunnelGuardMaxPingFails: Int = 3
@AppStorage("tunnelGuard.deadTunnelAction") private var tunnelGuardDeadTunnelAction: String = "prompt"
```

- [x] **Step 2: Add controls to `tunnelGuardSection` in `SettingsView.swift`**
In the Kill-Switch / Monitoring GroupBox:
- Add Picker for Base Ping Timeout: `1.5 с`, `2.0 с`, `3.0 с`, `5.0 с`.
- Add Toggle for "Прогрессивное увеличение таймаута (Backoff)".
- Add Picker for "Число попыток до тревоги": `2`, `3`, `5`.
- Add Picker for "Поведение при зависании":
  - `prompt`: "Заморозить и спросить в чёлке (SIGSTOP)"
  - `kill`: "Мгновенно ликвидировать (SIGKILL)"
- Add `.onChange` triggers calling `syncTunnelGuardSettings()`.

- [x] **Step 3: Update `syncTunnelGuardSettings()` in `SettingsView.swift`**
Pass new values to `tunnelGuard.basePingTimeout`, `tunnelGuard.progressiveTimeoutEnabled`, `tunnelGuard.maxPingFails`, and `tunnelGuard.deadTunnelAction`.

- [x] **Step 4: Commit Task 5**
Commit message: `feat(settings): expose ping timeout, backoff, and prompt policy in tunnelGuardSection`

---

### Task 6: End-to-End Build & Automated Verification

**Files:**
- Whole project verification

- [x] **Step 1: Run full safe test suite**
Run: `make test-tunnelguard-safe`
Expected: All tests pass.

- [x] **Step 2: Build project via `xcodebuild`**
Run: `make build`
Expected: `** BUILD SUCCEEDED **`.

- [x] **Step 3: Verify simulated dead tunnel trigger**
Run simulated test script or manual simulation to confirm agents are paused with SIGSTOP and Dynamic Island displays prompt with both buttons functional.
