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

        print("TunnelGuardWatchdogPromptTests: all passed")
    }

    // MARK: - 1. Settings persistence
    @MainActor
    static func testSettingsPersistence() {
        let suite = "tunnelguard-prompt-settings-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        // Test defaults
        let fresh = TunnelGuardWatchdog(settingsDefaults: defaults)
        precondition(fresh.basePingTimeout == 2.0, "Default basePingTimeout must be 2.0")
        precondition(fresh.progressiveTimeoutEnabled == true, "Default progressiveTimeoutEnabled must be true")
        precondition(fresh.maxPingFails == 3, "Default maxPingFails must be 3")
        precondition(fresh.deadTunnelAction == "prompt", "Default deadTunnelAction must be 'prompt'")

        // Test custom values
        defaults.set(3.5, forKey: "tunnelGuard.basePingTimeout")
        defaults.set(false, forKey: "tunnelGuard.progressiveTimeoutEnabled")
        defaults.set(5, forKey: "tunnelGuard.maxPingFails")
        defaults.set("kill", forKey: "tunnelGuard.deadTunnelAction")

        let restored = TunnelGuardWatchdog(settingsDefaults: defaults)
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
        let watchdog = TunnelGuardWatchdog()
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
        let watchdog = TunnelGuardWatchdog()
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
        let watchdog = TunnelGuardWatchdog()
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
        let watchdog = TunnelGuardWatchdog()
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
        let watchdog = TunnelGuardWatchdog()
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
        let watchdog = TunnelGuardWatchdog()
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
}
