import Foundation
import AppKit

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
enum TunnelGuardSplitLeakSafetyTests {
    @MainActor
    static func main() async throws {
        print("=== TunnelGuardSplitLeakSafetyTests ===")

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tunnelguard-splitleak-safety-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try await testSplitTunnelDNSFailureDoesNotLeak(tempDir: tempDir)
        try await testSplitTunnelRouteTimeoutDoesNotLeak(tempDir: tempDir)
        try await testSplitTunnelGenuineLeakFlagsUnprotected(tempDir: tempDir)
        testDeadTunnelPromptPersistentOnRepeatedTicksWithSplitCheck()
        testDeadTunnelPromptEscalatesIfInterfaceActuallyDrops()
        testDeadTunnelPromptEscalatesIfInterfaceDropsWithSplitCheck()

        print("TunnelGuardSplitLeakSafetyTests: all passed")
    }

    // MARK: - Test 1: DNS failure does not trigger leak
    static func testSplitTunnelDNSFailureDoesNotLeak(tempDir: URL) async throws {
        let vpnRoute = try makeScript(in: tempDir, name: "route-vpn", body: """
        echo 'interface: utun3'
        """)
        let worker = TunnelGuardNetworkWorker(routeExecutableURL: vpnRoute, pingInterval: 0, routeTimeout: 2)
        let snapshot = await worker.checkStatus(
            targetDomains: ["unresolvable-test-domain-12345.example.test"],
            enablePing: false
        )
        precondition(snapshot.targetDomainsOk == true, "DNS lookup failure must not be classified as a split-tunnel leak")
        precondition(snapshot.isVpn == true, "Primary interface should be identified as VPN")
        print("  ✓ testSplitTunnelDNSFailureDoesNotLeak passed")
    }

    // MARK: - Test 2: Route timeout does not trigger leak
    static func testSplitTunnelRouteTimeoutDoesNotLeak(tempDir: URL) async throws {
        let timeoutRoute = try makeScript(in: tempDir, name: "route-timeout", body: """
        case "$3" in
          1.1.1.1|8.8.8.8|default) echo 'interface: utun3' ;;
          *) exit 1 ;;
        esac
        """)
        let worker = TunnelGuardNetworkWorker(routeExecutableURL: timeoutRoute, pingInterval: 0, routeTimeout: 1)
        let snapshot = await worker.checkStatus(
            targetDomains: ["203.0.113.50"],
            enablePing: false
        )
        precondition(snapshot.targetDomainsOk == true, "Empty or failed route resolution must not count as a split leak")
        precondition(snapshot.isVpn == true, "Primary interface should remain utun3")
        print("  ✓ testSplitTunnelRouteTimeoutDoesNotLeak passed")
    }

    // MARK: - Test 3: Genuine leak flags unprotected
    static func testSplitTunnelGenuineLeakFlagsUnprotected(tempDir: URL) async throws {
        let leakRoute = try makeScript(in: tempDir, name: "route-leak", body: """
        case "$3" in
          1.1.1.1|8.8.8.8|default) echo 'interface: utun3' ;;
          203.0.113.99) echo 'interface: en0' ;;
          *) echo 'interface: en0' ;;
        esac
        """)
        let worker = TunnelGuardNetworkWorker(routeExecutableURL: leakRoute, pingInterval: 0, routeTimeout: 1)
        let snapshot = await worker.checkStatus(
            targetDomains: ["203.0.113.99"],
            enablePing: false
        )
        precondition(snapshot.targetDomainsOk == false, "Route explicitly resolving to en0 must trigger split-tunnel leak")
        precondition(snapshot.isVpn == true, "Primary interface is still VPN utun3")
        print("  ✓ testSplitTunnelGenuineLeakFlagsUnprotected passed")
    }

    // MARK: - Test 4: Dead tunnel prompt persistent on repeated ticks with splitCheck
    @MainActor
    static func testDeadTunnelPromptPersistentOnRepeatedTicksWithSplitCheck() {
        AppState.shared.resetTestCounters()
        let watchdog = TunnelGuardWatchdog()
        watchdog.targets = []
        watchdog.alarmSoundEnabled = false
        watchdog.macNotificationsEnabled = false
        watchdog.deadTunnelAction = "prompt"
        watchdog.splitTunnelCheck = true

        // First snapshot: dead tunnel detected, VPN active, utun3, targetDomainsOk = true
        let firstSnapshot = NetworkSnapshot(
            isVpn: true,
            iface: "utun3",
            pingOk: false,
            pingLatencyMs: 0.0,
            deadTunnelDetected: true,
            targetDomainsOk: true
        )
        watchdog.handleNetworkSnapshot(firstSnapshot, isGrace: false)

        precondition(watchdog.isDeadTunnelPromptActive == true, "Prompt must be active after first dead tunnel snapshot")
        precondition(watchdog.protectionStatus == .deadTunnel, "Protection status must be .deadTunnel")
        precondition(AppState.shared.view == .deadTunnelPrompt, "Island view must be .deadTunnelPrompt")
        precondition(AppState.shared.promptCount == 1, "Prompt count must be 1")

        // Second snapshot (repeated tick): deadTunnelDetected = true, isVpn = true, iface = "utun3", targetDomainsOk = false (transient timeout)
        let secondSnapshot = NetworkSnapshot(
            isVpn: true,
            iface: "utun3",
            pingOk: false,
            pingLatencyMs: 0.0,
            deadTunnelDetected: true,
            targetDomainsOk: false
        )
        watchdog.handleNetworkSnapshot(secondSnapshot, isGrace: false)

        precondition(watchdog.isDeadTunnelPromptActive == true, "Prompt must remain active on repeated tick with targetDomainsOk == false")
        precondition(watchdog.protectionStatus == .deadTunnel, "Protection status must remain .deadTunnel")
        precondition(AppState.shared.view == .deadTunnelPrompt, "Island view must stay .deadTunnelPrompt")
        precondition(AppState.shared.triggerCount == 0, "No panic kill must be triggered on dead tunnel tick")
        precondition(AppState.shared.dismissCount == 0, "Prompt must not be dismissed")
        print("  ✓ testDeadTunnelPromptPersistentOnRepeatedTicksWithSplitCheck passed")
    }

    // MARK: - Test 5: Dead tunnel prompt escalates if interface actually drops
    @MainActor
    static func testDeadTunnelPromptEscalatesIfInterfaceActuallyDrops() {
        AppState.shared.resetTestCounters()
        let watchdog = TunnelGuardWatchdog()
        watchdog.targets = []
        watchdog.alarmSoundEnabled = false
        watchdog.macNotificationsEnabled = false
        watchdog.deadTunnelAction = "prompt"

        // 1. First snapshot: dead tunnel detected
        let deadSnapshot = NetworkSnapshot(
            isVpn: true,
            iface: "utun3",
            pingOk: false,
            pingLatencyMs: 0.0,
            deadTunnelDetected: true,
            targetDomainsOk: true
        )
        watchdog.handleNetworkSnapshot(deadSnapshot, isGrace: false)
        precondition(watchdog.isDeadTunnelPromptActive == true)
        precondition(AppState.shared.view == .deadTunnelPrompt)

        // 2. Next snapshot: connection dropped to en0 (isVpn = false, iface = "en0")
        let dropSnapshot = NetworkSnapshot(
            isVpn: false,
            iface: "en0",
            pingOk: false,
            pingLatencyMs: 0.0,
            deadTunnelDetected: false,
            targetDomainsOk: true
        )
        watchdog.handleNetworkSnapshot(dropSnapshot, isGrace: false)

        precondition(watchdog.isDeadTunnelPromptActive == false, "Prompt must be dismissed on interface drop escalation")
        precondition(watchdog.protectionStatus == .vpnInactive, "Protection status must escalate to .vpnInactive")
        precondition(AppState.shared.view == .securityPanic, "Hard kill must switch view to .securityPanic")
        precondition(AppState.shared.triggerCount == 1, "Panic must be triggered on interface drop")
        print("  ✓ testDeadTunnelPromptEscalatesIfInterfaceActuallyDrops passed")
    }

    // MARK: - Test 6: Dead tunnel prompt escalates even if splitTunnelCheck is true when interface drops to en0
    @MainActor
    static func testDeadTunnelPromptEscalatesIfInterfaceDropsWithSplitCheck() {
        AppState.shared.resetTestCounters()
        let watchdog = TunnelGuardWatchdog()
        watchdog.targets = []
        watchdog.alarmSoundEnabled = false
        watchdog.macNotificationsEnabled = false
        watchdog.deadTunnelAction = "prompt"
        watchdog.splitTunnelCheck = true

        // 1. First snapshot: dead tunnel detected in utun
        let deadSnapshot = NetworkSnapshot(
            isVpn: true,
            iface: "utun3",
            pingOk: false,
            pingLatencyMs: 0.0,
            deadTunnelDetected: true,
            targetDomainsOk: true
        )
        watchdog.handleNetworkSnapshot(deadSnapshot, isGrace: false)
        precondition(watchdog.isDeadTunnelPromptActive == true)
        precondition(AppState.shared.view == .deadTunnelPrompt)

        // 2. Next snapshot: connection dropped to en0 (isVpn = false, iface = "en0")
        // Note: DNS may be broken or unresolvable, so targetDomainsOk is true
        let dropSnapshot = NetworkSnapshot(
            isVpn: false,
            iface: "en0",
            pingOk: false,
            pingLatencyMs: 0.0,
            deadTunnelDetected: false,
            targetDomainsOk: true
        )
        watchdog.handleNetworkSnapshot(dropSnapshot, isGrace: false)

        precondition(watchdog.isDeadTunnelPromptActive == false, "Prompt must be dismissed on interface drop escalation even with splitTunnelCheck=true")
        precondition(watchdog.protectionStatus == .vpnInactive, "Protection status must escalate to .vpnInactive")
        precondition(AppState.shared.view == .securityPanic, "Hard kill must switch view to .securityPanic")
        precondition(AppState.shared.triggerCount == 1, "Panic must be triggered on interface drop")
        print("  ✓ testDeadTunnelPromptEscalatesIfInterfaceDropsWithSplitCheck passed")
    }

    // MARK: - Helper
    static func makeScript(in directory: URL, name: String, body: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try "#!/bin/sh\n\(body)\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }
}
