import Foundation
import AppKit

enum IslandView {
    case overview, securityPanic
}

@MainActor
final class AppState {
    static let shared = AppState()
    var view: IslandView = .overview
    var securityAlarmText = ""

    func triggerSecurityPanic(message: String) {
        securityAlarmText = message
        view = .securityPanic
    }

    func resetSecurityAlert() {
        securityAlarmText = ""
        view = .overview
    }
}

@main
enum GestapoPhase1SafeTests {
    @MainActor
    static func main() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("gestapo-phase1-safe-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let route = try makeScript(in: tempDir, name: "route", body: """
        case "$3" in
          1.1.1.1|8.8.8.8) echo 'interface: en0' ;;
          default|203.0.113.10) echo 'interface: utun7' ;;
          203.0.113.11) echo 'interface: en0' ;;
          *) echo 'interface: en0' ;;
        esac
        """)
        let failedPing = try makeScript(in: tempDir, name: "ping-fail", body: "exit 1")
        let curl = try makeScript(in: tempDir, name: "curl", body: "echo 198.51.100.7")

        testPowerGuard()
        try await testSplitTunnel(route: route)
        try await testSplitTunnelLeak(route: route)
        try await testSplitTunnelDNSFailure(route: route)
        try await testDeadTunnel(route: route, ping: failedPing)
        try await testExternalIP(route: route, curl: curl)
        testWatchdogSplitTunnelHealth()

        print("Gestapo Phase 1 safe tests: all passed")
    }

    @MainActor
    static func testPowerGuard() {
        let guarder = GestapoPowerGuard()
        precondition(!guarder.isGracePeriodActive)
        guarder.activateGracePeriod(seconds: 10)
        precondition(guarder.isGracePeriodActive)
        guarder.clearGracePeriod()
        precondition(!guarder.isGracePeriodActive)
        print("  ✓ Power Guard grace period")
    }

    static func testSplitTunnel(route: URL) async throws {
        let worker = GestapoNetworkWorker(routeExecutableURL: route, pingInterval: 0, routeTimeout: 2)
        let snapshot = await worker.checkStatus(
            targetDomains: ["203.0.113.10"],
            enablePing: false
        )
        precondition(snapshot.isVpn == true)
        precondition(snapshot.targetDomainsOk == true)
        print("  ✓ Split tunnel target route")
    }

    static func testSplitTunnelLeak(route: URL) async throws {
        let worker = GestapoNetworkWorker(routeExecutableURL: route, pingInterval: 0, routeTimeout: 2)
        let snapshot = await worker.checkStatus(
            targetDomains: ["203.0.113.11"],
            enablePing: false
        )
        precondition(snapshot.targetDomainsOk == false)
        print("  ✓ Split tunnel leak detection")
    }

    static func testSplitTunnelDNSFailure(route: URL) async throws {
        let worker = GestapoNetworkWorker(routeExecutableURL: route, pingInterval: 0, routeTimeout: 2)
        let snapshot = await worker.checkStatus(targetDomains: [""], enablePing: false)
        precondition(snapshot.targetDomainsOk == false)
        print("  ✓ Split tunnel DNS failure is fail-closed")
    }

    static func testDeadTunnel(route: URL, ping: URL) async throws {
        let worker = GestapoNetworkWorker(
            pingExecutableURL: ping,
            routeExecutableURL: route,
            pingInterval: 0,
            routeTimeout: 2
        )
        let first = await worker.checkStatus(enablePing: true)
        precondition(first.deadTunnelDetected == false)
        let second = await worker.checkStatus(enablePing: true)
        precondition(second.deadTunnelDetected == true)
        print("  ✓ Dead tunnel after two ping failures")
    }

    static func testExternalIP(route: URL, curl: URL) async throws {
        let worker = GestapoNetworkWorker(
            routeExecutableURL: route,
            curlExecutableURL: curl,
            pingInterval: 0,
            routeTimeout: 2
        )
        let result = await worker.probeExternalIp(targetDomain: "203.0.113.10")
        precondition(result.ip == "198.51.100.7")
        precondition(result.iface == "utun7")
        precondition(result.isVpn == true)
        print("  ✓ On-demand external IP probe")
    }

    @MainActor
    static func testWatchdogSplitTunnelHealth() {
        let watchdog = GestapoWatchdog()
        watchdog.splitTunnelCheck = true
        watchdog.targets = [] // этот тест проверяет состояние, но не должен запускать pkill
        let healthySplit = NetworkSnapshot(
            isVpn: false,
            iface: "en0",
            pingOk: true,
            pingLatencyMs: 1,
            deadTunnelDetected: false,
            targetDomainsOk: true
        )
        watchdog.handleNetworkSnapshot(healthySplit, isGrace: false)
        precondition(AppState.shared.view == .overview)

        let leakedSplit = NetworkSnapshot(
            isVpn: false,
            iface: "en0",
            pingOk: true,
            pingLatencyMs: 1,
            deadTunnelDetected: false,
            targetDomainsOk: false
        )
        watchdog.handleNetworkSnapshot(leakedSplit, isGrace: false)
        precondition(AppState.shared.view == .securityPanic)
        print("  ✓ Watchdog accepts healthy split tunnel and rejects leak")
    }

    static func makeScript(in directory: URL, name: String, body: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try "#!/bin/sh\n\(body)\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }
}
