import Foundation
import AppKit

enum IslandView { case overview, securityPanic }

@MainActor
final class AppState {
    static let shared = AppState()
    var view: IslandView = .overview
    var securityAlarmText = ""
    func triggerSecurityPanic(message: String) { securityAlarmText = message; view = .securityPanic }
    func resetSecurityAlert() { securityAlarmText = ""; view = .overview }
}

@main
enum GestapoPhase3SafeTests {
    @MainActor
    static func main() async throws {
        testProtectionStatusAndResetEligibility()
        try await testSelectedRouteGateway()
        try await testExternalIpProbeExplainsRoute()
        print("Gestapo Phase 3 safe tests: all passed")
    }

    @MainActor
    static func testProtectionStatusAndResetEligibility() {
        let watchdog = GestapoWatchdog()
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
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gestapo-phase3-\(UUID().uuidString)")
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
        let worker = GestapoNetworkWorker(routeExecutableURL: route, pingInterval: 0, routeTimeout: 2)
        let snapshot = await worker.checkStatus(enablePing: false)
        precondition(snapshot.isVpn && snapshot.iface == "utun9")
        precondition(snapshot.gateway == "192.0.2.2", "gateway must come from selected VPN route")
        print("  ✓ selected route keeps interface and gateway together")
    }

    static func testExternalIpProbeExplainsRoute() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gestapo-phase3-ip-\(UUID().uuidString)")
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

        let worker = GestapoNetworkWorker(
            routeExecutableURL: route,
            curlExecutableURL: curl,
            pingInterval: 0,
            routeTimeout: 2,
            ipProbeServices: ["198.51.100.10", "198.51.100.11"]
        )
        let result = await worker.probeExternalIp(targetDomain: "203.0.113.10")
        precondition(result.ip == "198.51.100.77")
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
        let invalidWorker = GestapoNetworkWorker(
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
