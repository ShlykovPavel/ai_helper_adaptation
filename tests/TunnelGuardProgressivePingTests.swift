import Foundation
import AppKit

// Minimal test stubs for AppState and IslandView so Watchdog can be linked cleanly in unit tests
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
enum TunnelGuardProgressivePingTests {
    @MainActor
    static func main() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tunnelguard-prog-ping-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let route = try makeScript(in: tempDir, name: "route", body: """
        echo 'interface: utun7'
        """)
        let failPing = try makeScript(in: tempDir, name: "ping-fail", body: """
        exit 1
        """)

        try await testMaxPingFailsThreshold(route: route, failPing: failPing)
        try await testPingSuccessResetsFailureCounter(tempDir: tempDir, route: route)
        try await testResetPingFailsMethod(route: route, failPing: failPing)
        try await testProgressiveBackoffTimeouts(tempDir: tempDir, route: route)
        try await testNonProgressiveBackoffMaintainsBaseTimeout(tempDir: tempDir, route: route)
        try await testGracePeriodSuppressesDeadTunnel(route: route, failPing: failPing)

        print("✅ TunnelGuard Progressive Ping & Backoff tests: all passed")
    }

    /// Проверяет, что при maxPingFails = 3 первые 2 сбоя не триггерят deadTunnelDetected,
    /// а 3-й сбой переводит состояние в deadTunnelDetected = true.
    static func testMaxPingFailsThreshold(route: URL, failPing: URL) async throws {
        let worker = TunnelGuardNetworkWorker(
            pingExecutableURL: failPing,
            routeExecutableURL: route,
            pingInterval: 0,
            routeTimeout: 2
        )

        let snap1 = await worker.checkStatus(enablePing: true, basePingTimeout: 1.5, useProgressiveBackoff: true, maxPingFails: 3)
        precondition(!snap1.pingOk, "1st ping should fail")
        precondition(!snap1.deadTunnelDetected, "1st fail must not trigger dead tunnel when maxPingFails = 3")

        let snap2 = await worker.checkStatus(enablePing: true, basePingTimeout: 1.5, useProgressiveBackoff: true, maxPingFails: 3)
        precondition(!snap2.pingOk, "2nd ping should fail")
        precondition(!snap2.deadTunnelDetected, "2nd fail must not trigger dead tunnel when maxPingFails = 3")

        let snap3 = await worker.checkStatus(enablePing: true, basePingTimeout: 1.5, useProgressiveBackoff: true, maxPingFails: 3)
        precondition(!snap3.pingOk, "3rd ping should fail")
        precondition(snap3.deadTunnelDetected, "3rd fail must trigger dead tunnel when maxPingFails = 3")

        let snap4 = await worker.checkStatus(enablePing: true, basePingTimeout: 1.5, useProgressiveBackoff: true, maxPingFails: 3)
        precondition(!snap4.pingOk, "4th ping should fail")
        precondition(snap4.deadTunnelDetected, "Subsequent fail must keep dead tunnel active")

        print("  ✓ maxPingFails threshold triggers dead tunnel on exact failure count")
    }

    /// Проверяет, что успешный пинг после 2 сбоев сбрасывает счетчик,
    /// и для повторного срабатывания dead tunnel требуются новые 3 сбоя.
    static func testPingSuccessResetsFailureCounter(tempDir: URL, route: URL) async throws {
        let toggleFile = tempDir.appendingPathComponent("ping-succeed.flag")
        let togglePing = try makeScript(in: tempDir, name: "ping-toggle", body: """
        if [ -f "\(toggleFile.path)" ]; then
            exit 0
        else
            exit 1
        fi
        """)

        let worker = TunnelGuardNetworkWorker(
            pingExecutableURL: togglePing,
            routeExecutableURL: route,
            pingInterval: 0,
            routeTimeout: 2
        )

        _ = await worker.checkStatus(enablePing: true, maxPingFails: 3)
        _ = await worker.checkStatus(enablePing: true, maxPingFails: 3)

        // Активируем флаг успешного пинга
        try "".write(to: toggleFile, atomically: true, encoding: .utf8)
        let snapSuccess = await worker.checkStatus(enablePing: true, maxPingFails: 3)
        precondition(snapSuccess.pingOk, "Ping must succeed")
        precondition(!snapSuccess.deadTunnelDetected, "Dead tunnel must be false on success")

        // Удаляем флаг — снова сбои
        try? FileManager.default.removeItem(at: toggleFile)
        let retry1 = await worker.checkStatus(enablePing: true, maxPingFails: 3)
        precondition(!retry1.deadTunnelDetected, "After reset, 1st fail must not trigger dead tunnel")
        let retry2 = await worker.checkStatus(enablePing: true, maxPingFails: 3)
        precondition(!retry2.deadTunnelDetected, "After reset, 2nd fail must not trigger dead tunnel")
        let retry3 = await worker.checkStatus(enablePing: true, maxPingFails: 3)
        precondition(retry3.deadTunnelDetected, "After reset, 3rd fail must trigger dead tunnel")

        print("  ✓ successful ping resets failure counter back to 0")
    }

    /// Проверяет явный вызов resetPingFails().
    static func testResetPingFailsMethod(route: URL, failPing: URL) async throws {
        let worker = TunnelGuardNetworkWorker(
            pingExecutableURL: failPing,
            routeExecutableURL: route,
            pingInterval: 0,
            routeTimeout: 2
        )

        _ = await worker.checkStatus(enablePing: true, maxPingFails: 3)
        _ = await worker.checkStatus(enablePing: true, maxPingFails: 3)

        await worker.resetPingFails()

        let nextFail = await worker.checkStatus(enablePing: true, maxPingFails: 3)
        precondition(!nextFail.deadTunnelDetected, "resetPingFails must reset counter so 1st subsequent fail is not dead tunnel")

        print("  ✓ resetPingFails() clears consecutive fail counter")
    }

    /// Проверяет, что при progressive backoff timeout увеличивается с каждой неудачной попыткой.
    static func testProgressiveBackoffTimeouts(tempDir: URL, route: URL) async throws {
        let logFile = tempDir.appendingPathComponent("ping-args-prog.log")
        let script = try makeScript(in: tempDir, name: "ping-spy-prog", body: """
        echo "$@" >> "\(logFile.path)"
        exit 1
        """)

        let worker = TunnelGuardNetworkWorker(
            pingExecutableURL: script,
            routeExecutableURL: route,
            pingInterval: 0,
            routeTimeout: 2
        )

        // Attempt 1: consecutivePingFails == 0 -> basePingTimeout * (1.0 + 0) = 1.0s -> 1000ms
        _ = await worker.checkStatus(enablePing: true, basePingTimeout: 1.0, useProgressiveBackoff: true, maxPingFails: 4)
        // Attempt 2: consecutivePingFails == 1 -> basePingTimeout * (1.0 + 0.5 * 1) = 1.5s -> 1500ms
        _ = await worker.checkStatus(enablePing: true, basePingTimeout: 1.0, useProgressiveBackoff: true, maxPingFails: 4)
        // Attempt 3: consecutivePingFails == 2 -> basePingTimeout * (1.0 + 0.5 * 2) = 2.0s -> 2000ms
        _ = await worker.checkStatus(enablePing: true, basePingTimeout: 1.0, useProgressiveBackoff: true, maxPingFails: 4)
        // Attempt 4: consecutivePingFails == 3 -> basePingTimeout * (1.0 + 0.5 * 3) = 2.5s -> 2500ms
        _ = await worker.checkStatus(enablePing: true, basePingTimeout: 1.0, useProgressiveBackoff: true, maxPingFails: 4)

        let logContent = try String(contentsOf: logFile, encoding: .utf8)
        let lines = logContent.split(separator: "\n").map(String.init)
        precondition(lines.count == 4, "Expected 4 ping attempts, got \(lines.count)")

        precondition(lines[0].contains("-W 1000"), "Attempt 1 should use 1000ms (-W 1000), got: \(lines[0])")
        precondition(lines[1].contains("-W 1500"), "Attempt 2 should use 1500ms (-W 1500), got: \(lines[1])")
        precondition(lines[2].contains("-W 2000"), "Attempt 3 should use 2000ms (-W 2000), got: \(lines[2])")
        precondition(lines[3].contains("-W 2500"), "Attempt 4 should use 2500ms (-W 2500), got: \(lines[3])")

        print("  ✓ progressive backoff increments timeout linearly (1000ms -> 1500ms -> 2000ms -> 2500ms)")
    }

    /// Проверяет, что при useProgressiveBackoff = false таймаут остается постоянным.
    static func testNonProgressiveBackoffMaintainsBaseTimeout(tempDir: URL, route: URL) async throws {
        let logFile = tempDir.appendingPathComponent("ping-args-const.log")
        let script = try makeScript(in: tempDir, name: "ping-spy-const", body: """
        echo "$@" >> "\(logFile.path)"
        exit 1
        """)

        let worker = TunnelGuardNetworkWorker(
            pingExecutableURL: script,
            routeExecutableURL: route,
            pingInterval: 0,
            routeTimeout: 2
        )

        _ = await worker.checkStatus(enablePing: true, basePingTimeout: 2.0, useProgressiveBackoff: false, maxPingFails: 3)
        _ = await worker.checkStatus(enablePing: true, basePingTimeout: 2.0, useProgressiveBackoff: false, maxPingFails: 3)

        let logContent = try String(contentsOf: logFile, encoding: .utf8)
        let lines = logContent.split(separator: "\n").map(String.init)
        precondition(lines.count == 2, "Expected 2 ping attempts, got \(lines.count)")

        precondition(lines[0].contains("-W 2000"), "Attempt 1 should use 2000ms, got: \(lines[0])")
        precondition(lines[1].contains("-W 2000"), "Attempt 2 should maintain 2000ms without backoff, got: \(lines[1])")

        print("  ✓ non-progressive mode maintains constant timeout (-W 2000)")
    }

    /// Проверяет, что в grace period dead tunnel подавляется.
    static func testGracePeriodSuppressesDeadTunnel(route: URL, failPing: URL) async throws {
        let worker = TunnelGuardNetworkWorker(
            pingExecutableURL: failPing,
            routeExecutableURL: route,
            pingInterval: 0,
            routeTimeout: 2
        )

        let snap = await worker.checkStatus(enablePing: true, isGracePeriod: true, maxPingFails: 1)
        precondition(snap.pingOk, "Grace period treats ping as OK")
        precondition(!snap.deadTunnelDetected, "Grace period suppresses dead tunnel")

        print("  ✓ grace period suppresses dead tunnel")
    }

    private static func makeScript(in directory: URL, name: String, body: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try "#!/bin/sh\n\(body)\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }
}
