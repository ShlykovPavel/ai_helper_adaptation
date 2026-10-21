import Foundation
import AppKit

enum IslandView { case overview, securityPanic, deadTunnelPrompt }

@MainActor
final class AppState {
    static let shared = AppState()
    var view: IslandView = .overview
    var securityAlarmText = ""
    var deadTunnelPromptText = ""
    func triggerSecurityPanic(message: String) { securityAlarmText = message; view = .securityPanic }
    func resetSecurityAlert() { securityAlarmText = ""; view = .overview }
    func triggerDeadTunnelPrompt(message: String = "VPN не отвечает (Dead Tunnel). Агенты временно заморожены (SIGSTOP).") {
        deadTunnelPromptText = message
        view = .deadTunnelPrompt
    }
    func dismissDeadTunnelPrompt() {
        deadTunnelPromptText = ""
        if view == .deadTunnelPrompt {
            view = .overview
        }
    }
}

@main
enum TunnelGuardPhase3SafeTests {
    @MainActor
    static func main() async throws {
        testPersistedSettingsBeforeStartup()
        testProtectionStatusAndResetEligibility()
        try await testSelectedRouteGateway()
        try await testExternalIpProbeExplainsRoute()
        print("TunnelGuard Phase 3 safe tests: all passed")
    }

    @MainActor
    static func testPersistedSettingsBeforeStartup() {
        let context = TunnelGuardTestContext(prefix: "tg-phase3-settings")
        defer { context.tearDown() }
        let defaults = context.defaults
        let fresh = context.makeWatchdog()
        precondition(fresh.isEnabled && fresh.continuousKill && !fresh.splitTunnelCheck)
        precondition(fresh.targets == TunnelGuardAppHunter.defaultTargets)
        for key in ["enabled", "continuousKill", "pingCheckEnabled", "preventSleep",
                    "sleepWakeGuardEnabled", "alarmSoundEnabled", "macNotificationsEnabled"] {
            defaults.set(false, forKey: "tunnelGuard.\(key)")
        }
        defaults.set(true, forKey: "tunnelGuard.splitTunnelCheck")
        defaults.set(false, forKey: "tunnelGuard.target.antigravity-ide")
        let restored = TunnelGuardWatchdog(settingsDefaults: defaults, stateDirectoryURL: context.tempDirectoryURL)
        precondition(!restored.isEnabled && !restored.continuousKill && !restored.pingCheckEnabled)
        precondition(!restored.preventSleep && !restored.sleepWakeGuardEnabled)
        precondition(!restored.alarmSoundEnabled && !restored.macNotificationsEnabled)
        precondition(restored.splitTunnelCheck)
        precondition(!restored.targets.contains { $0.id == "antigravity-ide" })
        precondition(restored.targets.contains { $0.id == "antigravity-desktop" })
        restored.start() // Disabled policy prevents networking and process termination.
        precondition(restored.protectionStatus == .disabled)
        restored.stop()

        // Immediate reactivity & clearIpProbeResult verification
        fresh.isEnabled = false
        precondition(fresh.protectionStatus == .disabled)
        fresh.clearIpProbeResult()
        precondition(fresh.ipProbeResult == nil && fresh.externalIp.isEmpty)

        print("  ✓ persisted policy and IDE target applied before monitoring starts")
    }

    @MainActor
    static func testProtectionStatusAndResetEligibility() {
        let context = TunnelGuardTestContext(prefix: "tg-phase3-status")
        defer { context.tearDown() }
        let watchdog = context.makeWatchdog()
        watchdog.targets = []

        watchdog.handleNetworkSnapshot(NetworkSnapshot(isVpn: true, iface: "utun3", pingOk: true,
            pingLatencyMs: 8, deadTunnelDetected: false, targetDomainsOk: true), isGrace: false)
        precondition(watchdog.protectionStatus == .protected && watchdog.canResetSecurityAlert)

        watchdog.handleNetworkSnapshot(NetworkSnapshot(isVpn: true, iface: "utun3", pingOk: false,
            pingLatencyMs: 0, deadTunnelDetected: true, targetDomainsOk: true), isGrace: false)
        precondition(watchdog.protectionStatus == .deadTunnel && !watchdog.canResetSecurityAlert)

        watchdog.splitTunnelCheck = true
        watchdog.handleNetworkSnapshot(NetworkSnapshot(isVpn: true, iface: "utun3", pingOk: true,
            pingLatencyMs: 8, deadTunnelDetected: false, targetDomainsOk: false), isGrace: false)
        precondition(watchdog.protectionStatus == .splitTunnelLeak && !watchdog.canResetSecurityAlert)

        watchdog.handleNetworkSnapshot(NetworkSnapshot(isVpn: true, iface: "utun3", pingOk: true,
            pingLatencyMs: 8, deadTunnelDetected: false, targetDomainsOk: true), isGrace: true)
        precondition(watchdog.protectionStatus == .grace && !watchdog.canResetSecurityAlert)

        watchdog.isEnabled = false
        watchdog.handleNetworkSnapshot(NetworkSnapshot(isVpn: true, iface: "utun3", pingOk: true,
            pingLatencyMs: 8, deadTunnelDetected: false, targetDomainsOk: true), isGrace: false)
        precondition(watchdog.protectionStatus == .disabled && !watchdog.canResetSecurityAlert)
        print("  ✓ unified protection status covers dead tunnel, split leak, grace and disabled")
    }

    static func testSelectedRouteGateway() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tunnelguard-phase3-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let route = dir.appendingPathComponent("route")
        try """
        #!/bin/sh
        case "$3" in
          1.1.1.1) echo 'gateway: 192.0.2.1'; echo 'interface: en0' ;;
          8.8.8.8) echo 'gateway: 192.0.2.2'; echo 'interface: utun9' ;;
          default) echo 'gateway: 192.0.2.3'; echo 'interface: en0' ;;
        esac
        """.write(to: route, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: route.path)
        let worker = TunnelGuardNetworkWorker(routeExecutableURL: route, pingInterval: 0, routeTimeout: 2)
        let snapshot = await worker.checkStatus(enablePing: false)
        precondition(snapshot.isVpn && snapshot.iface == "utun9")
        precondition(snapshot.gateway == "192.0.2.2", "gateway must come from selected VPN route")
        print("  ✓ selected route keeps interface and gateway together")
    }

    static func testExternalIpProbeExplainsRoute() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tunnelguard-phase3-ip-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let route = dir.appendingPathComponent("route")
        try """
        #!/bin/sh
        case "$3" in
          203.0.113.10) echo 'gateway: 192.0.2.10'; echo 'interface: utun7' ;;
          198.51.100.10) echo 'gateway: 192.0.2.20'; echo 'interface: en0' ;;
          198.51.100.11) echo 'gateway: 192.0.2.10'; echo 'interface: utun7' ;;
          *) echo 'gateway: 192.0.2.1'; echo 'interface: en0' ;;
        esac
        """.write(to: route, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: route.path)

        let curl = dir.appendingPathComponent("curl")
        try """
        #!/bin/sh
        echo '198.51.100.77'
        """.write(to: curl, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: curl.path)

        let worker = TunnelGuardNetworkWorker(
            routeExecutableURL: route,
            curlExecutableURL: curl,
            pingInterval: 0,
            routeTimeout: 5,
            ipProbeServices: ["198.51.100.10", "198.51.100.11"]
        )
        let result = await worker.probeExternalIp(targetDomain: "203.0.113.10")
        precondition(result.ip == "198.51.100.77", "Expected 198.51.100.77, got '\(result.ip)', error: '\(result.errorMessage)'")
        precondition(result.targetIp == "203.0.113.10")
        precondition(result.targetInterface == "utun7")
        precondition(result.ipService == "198.51.100.11")
        precondition(result.ipServiceInterface == "utun7")
        precondition(result.isVpn)
        print("  ✓ IP probe reports target route and matching IP service")

        let invalidCurl = dir.appendingPathComponent("curl-invalid")
        try """
        #!/bin/sh
        echo '<html>not an ip</html>'
        """.write(to: invalidCurl, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: invalidCurl.path)
        let invalidWorker = TunnelGuardNetworkWorker(
            routeExecutableURL: route,
            curlExecutableURL: invalidCurl,
            pingInterval: 0,
            routeTimeout: 2,
            ipProbeServices: ["198.51.100.11"]
        )
        let invalidResult = await invalidWorker.probeExternalIp(targetDomain: "203.0.113.10")
        precondition(!invalidResult.isSuccessful)
        precondition(invalidResult.ip.isEmpty)
        print("  ✓ IP probe rejects non-IP response")
    }
}
