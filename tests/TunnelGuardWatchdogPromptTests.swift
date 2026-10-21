import Foundation
import AppKit

// Minimal test stubs for AppState and IslandView so Watchdog can be linked cleanly in unit tests
enum IslandView: String, CaseIterable {
    case overview, securityPanic, deadTunnelPrompt
}

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()
    var view: IslandView = .overview
    var securityAlarmText: String = ""
    var deadTunnelPromptText: String = ""
    var triggerCount: Int = 0
    var promptCount: Int = 0
    var dismissCount: Int = 0
    var resetCount: Int = 0

    func triggerSecurityPanic(message: String) {
        triggerCount += 1
        securityAlarmText = message
        view = .securityPanic
    }

    func resetSecurityAlert() {
        resetCount += 1
        securityAlarmText = ""
        view = .overview
    }

    func triggerDeadTunnelPrompt(message: String = "VPN не отвечает (Dead Tunnel). Агенты временно заморожены (SIGSTOP).") {
        promptCount += 1
        deadTunnelPromptText = message
        view = .deadTunnelPrompt
    }

    func dismissDeadTunnelPrompt() {
        dismissCount += 1
        deadTunnelPromptText = ""
        if view == .deadTunnelPrompt {
            view = .overview
        }
    }

    func resetTestCounters() {
        triggerCount = 0
        promptCount = 0
        dismissCount = 0
        resetCount = 0
        securityAlarmText = ""
        deadTunnelPromptText = ""
        view = .overview
    }
}

@main
enum TunnelGuardWatchdogPromptTests {
    @MainActor
    static func main() async throws {
        print("=== TunnelGuardWatchdogPromptTests ===")

        testSettingsPersistence()
        testDeadTunnelPromptTrigger()
        try await testUserRequestedDeadTunnelWait()
        testAutoRecoveryOnHealthyNetwork()
        testUserConfirmedDeadTunnelKill()
        testDeadTunnelActionKillMode()
        testSafetyEscalationFromPromptToHardKill()
        try testDeadPauseDisableResumesProcesses()

        print("TunnelGuardWatchdogPromptTests: all passed")
    }

    // MARK: - 1. Settings persistence
    @MainActor
    static func testSettingsPersistence() {
        let context = TunnelGuardTestContext(prefix: "tg-prompt-settings")
        defer { context.tearDown() }
        let defaults = context.defaults

        // Test defaults
        let fresh = context.makeWatchdog()
        precondition(fresh.basePingTimeout == 2.0, "Default basePingTimeout must be 2.0")
        precondition(fresh.progressiveTimeoutEnabled == true, "Default progressiveTimeoutEnabled must be true")
        precondition(fresh.maxPingFails == 3, "Default maxPingFails must be 3")
        precondition(fresh.deadTunnelAction == "prompt", "Default deadTunnelAction must be 'prompt'")

        // Test custom values
        defaults.set(3.5, forKey: "tunnelGuard.basePingTimeout")
        defaults.set(false, forKey: "tunnelGuard.progressiveTimeoutEnabled")
        defaults.set(5, forKey: "tunnelGuard.maxPingFails")
        defaults.set("kill", forKey: "tunnelGuard.deadTunnelAction")

        let restored = TunnelGuardWatchdog(settingsDefaults: defaults, stateDirectoryURL: context.tempDirectoryURL)
        precondition(restored.basePingTimeout == 3.5, "basePingTimeout must load from UserDefaults")
        precondition(restored.progressiveTimeoutEnabled == false, "progressiveTimeoutEnabled must load from UserDefaults")
        precondition(restored.maxPingFails == 5, "maxPingFails must load from UserDefaults")
        precondition(restored.deadTunnelAction == "kill", "deadTunnelAction must load from UserDefaults")

        print("  ✓ settings persistence for basePingTimeout, progressiveTimeoutEnabled, maxPingFails, deadTunnelAction")
    }

    // MARK: - 2. Dead tunnel edge & level trigger
    @MainActor
    static func testDeadTunnelPromptTrigger() {
        AppState.shared.resetTestCounters()
        let context = TunnelGuardTestContext(prefix: "tg-prompt-trigger")
        defer { context.tearDown() }
        let watchdog = context.makeWatchdog()
        watchdog.targets = []
        watchdog.alarmSoundEnabled = false
        watchdog.macNotificationsEnabled = false
        watchdog.deadTunnelAction = "prompt"

        precondition(watchdog.isDeadTunnelPromptActive == false)
        precondition(AppState.shared.view == .overview)

        // Snapshot with dead tunnel
        let deadSnapshot = NetworkSnapshot(
            isVpn: true,
            iface: "utun7",
            pingOk: false,
            pingLatencyMs: 0.0,
            deadTunnelDetected: true,
            targetDomainsOk: true,
            gateway: "10.0.0.1"
        )

        watchdog.handleNetworkSnapshot(deadSnapshot, isGrace: false)

        precondition(watchdog.isDeadTunnelPromptActive == true, "isDeadTunnelPromptActive must be true")
        precondition(watchdog.protectionStatus == .deadTunnel, "protectionStatus must be .deadTunnel")
        precondition(AppState.shared.view == .deadTunnelPrompt, "AppState.view must be .deadTunnelPrompt")
        precondition(AppState.shared.promptCount == 1, "promptCount must be 1")
        precondition(!AppState.shared.deadTunnelPromptText.isEmpty, "deadTunnelPromptText must not be empty")

        // Level trigger: second tick while still dead should NOT kill or re-trigger prompt
        watchdog.handleNetworkSnapshot(deadSnapshot, isGrace: false)
        precondition(watchdog.isDeadTunnelPromptActive == true)
        precondition(AppState.shared.promptCount == 1, "Prompt must not re-trigger on level ticks")
        precondition(AppState.shared.view == .deadTunnelPrompt)

        print("  ✓ dead tunnel prompt triggers on edge, suspends and holds state on level")
    }

    // MARK: - 3. User requested wait
    @MainActor
    static func testUserRequestedDeadTunnelWait() async throws {
        AppState.shared.resetTestCounters()
        let context = TunnelGuardTestContext(prefix: "tg-prompt-wait")
        defer { context.tearDown() }
        let watchdog = context.makeWatchdog()
        watchdog.targets = []
        watchdog.alarmSoundEnabled = false
        watchdog.macNotificationsEnabled = false
        watchdog.deadTunnelAction = "prompt"

        let deadSnapshot = NetworkSnapshot(
            isVpn: true,
            iface: "utun7",
            pingOk: false,
            pingLatencyMs: 0.0,
            deadTunnelDetected: true,
            targetDomainsOk: true
        )
        watchdog.handleNetworkSnapshot(deadSnapshot, isGrace: false)
        precondition(watchdog.isDeadTunnelPromptActive == true)
        precondition(AppState.shared.view == .deadTunnelPrompt)

        // User clicks wait
        watchdog.userRequestedDeadTunnelWait()

        precondition(watchdog.isDeadTunnelPromptActive == false, "Prompt active must be reset to false")
        precondition(AppState.shared.view == .overview, "AppState view must return to .overview")
        precondition(watchdog.protectionStatus == .protected, "protectionStatus must be reset to .protected")

        print("  ✓ userRequestedDeadTunnelWait dismisses prompt and restores protected status")
    }

    // MARK: - 4. Auto recovery on healthy network
    @MainActor
    static func testAutoRecoveryOnHealthyNetwork() {
        AppState.shared.resetTestCounters()
        let context = TunnelGuardTestContext(prefix: "tg-prompt-recovery")
        defer { context.tearDown() }
        let watchdog = context.makeWatchdog()
        watchdog.targets = []
        watchdog.alarmSoundEnabled = false
        watchdog.macNotificationsEnabled = false
        watchdog.deadTunnelAction = "prompt"

        // 1. Enter dead tunnel state
        let deadSnapshot = NetworkSnapshot(
            isVpn: true,
            iface: "utun7",
            pingOk: false,
            pingLatencyMs: 0.0,
            deadTunnelDetected: true,
            targetDomainsOk: true
        )
        watchdog.handleNetworkSnapshot(deadSnapshot, isGrace: false)
        precondition(watchdog.isDeadTunnelPromptActive == true)
        precondition(AppState.shared.view == .deadTunnelPrompt)

        // 2. Tunnel recovers (healthy snapshot)
        let healthySnapshot = NetworkSnapshot(
            isVpn: true,
            iface: "utun7",
            pingOk: true,
            pingLatencyMs: 25.0,
            deadTunnelDetected: false,
            targetDomainsOk: true
        )
        watchdog.handleNetworkSnapshot(healthySnapshot, isGrace: false)

        precondition(watchdog.isDeadTunnelPromptActive == false, "isDeadTunnelPromptActive must be false on recovery")
        precondition(AppState.shared.view == .overview, "AppState view must be dismissed back to .overview")
        precondition(watchdog.protectionStatus == .protected, "protectionStatus must be .protected")

        print("  ✓ auto-recovery dismisses prompt and resumes normal operation on network recovery")
    }

    // MARK: - 5. User confirmed kill
    @MainActor
    static func testUserConfirmedDeadTunnelKill() {
        AppState.shared.resetTestCounters()
        let context = TunnelGuardTestContext(prefix: "tg-prompt-kill")
        defer { context.tearDown() }
        let watchdog = context.makeWatchdog()
        watchdog.targets = []
        watchdog.alarmSoundEnabled = false
        watchdog.macNotificationsEnabled = false
        watchdog.deadTunnelAction = "prompt"

        let deadSnapshot = NetworkSnapshot(
            isVpn: true,
            iface: "utun7",
            pingOk: false,
            pingLatencyMs: 0.0,
            deadTunnelDetected: true,
            targetDomainsOk: true
        )
        watchdog.handleNetworkSnapshot(deadSnapshot, isGrace: false)
        precondition(watchdog.isDeadTunnelPromptActive == true)

        watchdog.userConfirmedDeadTunnelKill()

        precondition(watchdog.isDeadTunnelPromptActive == false)
        precondition(AppState.shared.view == .securityPanic, "Hard kill must switch view to .securityPanic")
        precondition(AppState.shared.triggerCount == 1, "Panic must be triggered on hard kill confirmation")

        print("  ✓ userConfirmedDeadTunnelKill executes hard kill and triggers panic card")
    }

    // MARK: - 6. Dead tunnel action "kill" mode
    @MainActor
    static func testDeadTunnelActionKillMode() {
        AppState.shared.resetTestCounters()
        let context = TunnelGuardTestContext(prefix: "tg-prompt-killmode")
        defer { context.tearDown() }
        let watchdog = context.makeWatchdog()
        watchdog.targets = []
        watchdog.alarmSoundEnabled = false
        watchdog.macNotificationsEnabled = false
        watchdog.deadTunnelAction = "kill"

        let deadSnapshot = NetworkSnapshot(
            isVpn: true,
            iface: "utun7",
            pingOk: false,
            pingLatencyMs: 0.0,
            deadTunnelDetected: true,
            targetDomainsOk: true
        )
        watchdog.handleNetworkSnapshot(deadSnapshot, isGrace: false)

        precondition(watchdog.isDeadTunnelPromptActive == false, "Prompt must not be active in kill mode")
        precondition(AppState.shared.view == .securityPanic, "Kill mode must trigger securityPanic immediately")
        precondition(watchdog.protectionStatus == .deadTunnel)

        print("  ✓ deadTunnelAction == 'kill' triggers hard kill immediately without prompt")
    }

    // MARK: - 7. Safety escalation from prompt to hard kill
    @MainActor
    static func testSafetyEscalationFromPromptToHardKill() {
        AppState.shared.resetTestCounters()
        let context = TunnelGuardTestContext(prefix: "tg-prompt-escalate")
        defer { context.tearDown() }
        let watchdog = context.makeWatchdog()
        watchdog.targets = []
        watchdog.alarmSoundEnabled = false
        watchdog.macNotificationsEnabled = false
        watchdog.deadTunnelAction = "prompt"

        // 1. Dead tunnel triggered
        let deadSnapshot = NetworkSnapshot(
            isVpn: true,
            iface: "utun7",
            pingOk: false,
            pingLatencyMs: 0.0,
            deadTunnelDetected: true,
            targetDomainsOk: true
        )
        watchdog.handleNetworkSnapshot(deadSnapshot, isGrace: false)
        precondition(watchdog.isDeadTunnelPromptActive == true)
        precondition(AppState.shared.view == .deadTunnelPrompt)

        // 2. Next tick: interface dropped to en0 (isVpn = false) while prompt pending
        let dropSnapshot = NetworkSnapshot(
            isVpn: false,
            iface: "en0",
            pingOk: false,
            pingLatencyMs: 0.0,
            deadTunnelDetected: false,
            targetDomainsOk: false
        )
        watchdog.handleNetworkSnapshot(dropSnapshot, isGrace: false)

        precondition(watchdog.isDeadTunnelPromptActive == false, "Prompt must be dismissed on escalation")
        precondition(AppState.shared.view == .securityPanic, "Escalation must trigger securityPanic hard kill")
        precondition(watchdog.protectionStatus == .vpnInactive)

        print("  ✓ safety escalation to hard kill when interface drops from utun to en0 during pending prompt")
    }

    // MARK: - 8. R14: Dead tunnel pause -> disable/stop guarantees resume (SIGCONT)
    @MainActor
    static func testDeadPauseDisableResumesProcesses() throws {
        AppState.shared.resetTestCounters()
        let context = TunnelGuardTestContext(prefix: "tg-prompt-r14")
        defer { context.tearDown() }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tg-mock-scripts-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let pkillLog = directory.appendingPathComponent("pkill-log.txt")
        let scriptPkill = directory.appendingPathComponent("mock-pkill.sh")
        let pkillLogEscaped = pkillLog.path.replacingOccurrences(of: "'", with: "'\\''")
        try "#!/bin/sh\nprintf '%s|%s|%s\\n' \"$1\" \"$2\" \"$3\" >> '\(pkillLogEscaped)'\nexit 0\n"
            .write(to: scriptPkill, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPkill.path)

        let scriptPgrep = directory.appendingPathComponent("mock-pgrep.sh")
        try "#!/bin/sh\necho 9876\nexit 0\n"
            .write(to: scriptPgrep, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPgrep.path)

        let watchdog = context.makeWatchdog()
        watchdog.pkillExecutableURL = scriptPkill
        watchdog.pgrepExecutableURL = scriptPgrep
        watchdog.alarmSoundEnabled = false
        watchdog.macNotificationsEnabled = false
        watchdog.deadTunnelAction = "prompt"
        watchdog.targets = [
            TunnelGuardTargetApp(id: "claude-cli", name: "Claude CLI", type: .cli, binaryOrBundleId: "claude", domain: "claude.ai")
        ]

        precondition(watchdog.isDeadTunnelPromptActive == false)
        precondition(watchdog.suspendedPIDs.isEmpty)

        // 1. Появление dead tunnel -> процессы замораживаются по SIGSTOP
        let deadSnapshot = NetworkSnapshot(
            isVpn: true,
            iface: "utun7",
            pingOk: false,
            pingLatencyMs: 0.0,
            deadTunnelDetected: true,
            targetDomainsOk: true
        )
        watchdog.handleNetworkSnapshot(deadSnapshot, isGrace: false)
        watchdog.flushWorkerQueue()

        precondition(watchdog.isDeadTunnelPromptActive == true, "Prompt must be active after dead tunnel")
        precondition(watchdog.suspendedPIDs.contains(9876), "Watchdog must record suspended PID 9876")

        let pkillContent1 = try String(contentsOf: pkillLog, encoding: .utf8)
        precondition(pkillContent1.contains("-STOP|-x|claude"), "Processes must be suspended via pkill -STOP -x claude")

        // 2. Пользователь выключает защиту: isEnabled = false
        // Обязан произойти вызов SIGCONT для возобновления процессов!
        watchdog.isEnabled = false
        watchdog.flushWorkerQueue()

        precondition(watchdog.isDeadTunnelPromptActive == false, "Prompt must be dismissed when disabled")
        precondition(watchdog.protectionStatus == .disabled, "Protection status must be disabled")
        precondition(watchdog.suspendedPIDs.isEmpty, "suspendedPIDs must be cleared on resume")

        let pkillContent2 = try String(contentsOf: pkillLog, encoding: .utf8)
        precondition(pkillContent2.contains("-CONT|-x|claude"), "SIGCONT must be sent to resume processes on disable")

        // 3. Проверка: при штатной работе без паузы отключение не шлет лишний CONT
        try "".write(to: pkillLog, atomically: true, encoding: .utf8)
        watchdog.isEnabled = true
        let healthySnapshot = NetworkSnapshot(
            isVpn: true,
            iface: "utun7",
            pingOk: true,
            pingLatencyMs: 15.0,
            deadTunnelDetected: false,
            targetDomainsOk: true
        )
        watchdog.handleNetworkSnapshot(healthySnapshot, isGrace: false)
        watchdog.flushWorkerQueue()

        watchdog.isEnabled = false
        watchdog.flushWorkerQueue()

        let pkillContent3 = try String(contentsOf: pkillLog, encoding: .utf8)
        precondition(pkillContent3.isEmpty, "Disabling watchdog when not suspended must not send CONT signals")

        // 4. Проверка stop(): если остановлен во время паузы dead tunnel, SIGCONT также отправляется
        watchdog.isEnabled = true
        watchdog.handleNetworkSnapshot(deadSnapshot, isGrace: false)
        watchdog.flushWorkerQueue()
        precondition(watchdog.isDeadTunnelPromptActive == true)

        try "".write(to: pkillLog, atomically: true, encoding: .utf8)
        watchdog.stop()
        watchdog.flushWorkerQueue()

        let pkillContent4 = try String(contentsOf: pkillLog, encoding: .utf8)
        precondition(pkillContent4.contains("-CONT|-x|claude"), "stop() must resume suspended processes via SIGCONT")

        print("  ✓ R14: dead -> pause -> disable/stop guarantees SIGCONT resume of suspended processes")
    }
}
