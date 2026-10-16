import Foundation
import AppKit

enum IslandView: String, CaseIterable {
    case overview, empty, approval, question, error, finished
    case confused, upload, uploading, choose, mail, prompt
    case searching, result, note, settings, greeting, wardrobe, recap
    case listening
    case voiceResult
    case securityPanic
    case deadTunnelPrompt
}

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()
    var view: IslandView = .overview
    var securityAlarmText: String = ""
    var deadTunnelPromptText: String = ""
    var triggerCount: Int = 0
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
        deadTunnelPromptText = message
        view = .deadTunnelPrompt
    }

    func dismissDeadTunnelPrompt() {
        deadTunnelPromptText = ""
        if view == .deadTunnelPrompt {
            view = .overview
        }
    }

    func resetTestCounters() {
        triggerCount = 0
        resetCount = 0
        securityAlarmText = ""
        deadTunnelPromptText = ""
        view = .overview
    }
}

@main
enum TunnelGuardWatchdogTests {
    @MainActor
    static func main() {
        print("=== TunnelGuardWatchdog Tests ===")

        testInterfaceDetection()
        testDnsHangTimeoutProtection()
        testVpnDropBehaviorAndEdgeTriggering()
        testLogDirectoryAndFormat()
        testLogRotation()
        testTargetProcessList()

        print("TunnelGuardWatchdog: all cases passed")
    }

    // MARK: - 1. Interface Detection (utun vs non-utun)

    static func testInterfaceDetection() {
        // 1.1 parseInterface from route output
        let utunOutput = """
           route to: 1.1.1.1
        destination: 1.1.1.1
            gateway: 10.33.0.2
          interface: utun22
              flags: <UP,GATEWAY,HOST,DONE,STATIC>
        """
        precondition(TunnelGuardWatchdog.parseInterface(fromRouteOutput: utunOutput) == "utun22",
                     "Failed to parse utun22 interface")

        let en0Output = """
           route to: default
        destination: default
            gateway: 192.168.1.1
          interface: en0
              flags: <UP,GATEWAY,DONE,STATIC,PRCLONING>
        """
        precondition(TunnelGuardWatchdog.parseInterface(fromRouteOutput: en0Output) == "en0",
                     "Failed to parse en0 interface")

        let paddedOutput = "  interface:   utun0   \nflags: UP\n"
        precondition(TunnelGuardWatchdog.parseInterface(fromRouteOutput: paddedOutput) == "utun0",
                     "Failed to trim whitespace around interface")

        let emptyOutput = ""
        precondition(TunnelGuardWatchdog.parseInterface(fromRouteOutput: emptyOutput) == "",
                     "Empty output must return empty string")

        let noInterfaceOutput = "destination: 1.1.1.1\ngateway: 10.0.0.1\n"
        precondition(TunnelGuardWatchdog.parseInterface(fromRouteOutput: noInterfaceOutput) == "",
                     "Output without interface keyword must return empty string")

        // 1.2 isVpnInterface checks
        precondition(TunnelGuardWatchdog.isVpnInterface("utun0"), "utun0 must be recognized as VPN")
        precondition(TunnelGuardWatchdog.isVpnInterface("utun22"), "utun22 must be recognized as VPN")
        precondition(TunnelGuardWatchdog.isVpnInterface("utun99"), "utun99 must be recognized as VPN")
        precondition(!TunnelGuardWatchdog.isVpnInterface("en0"), "en0 must NOT be recognized as VPN")
        precondition(!TunnelGuardWatchdog.isVpnInterface("en1"), "en1 must NOT be recognized as VPN")
        precondition(!TunnelGuardWatchdog.isVpnInterface("bridge0"), "bridge0 must NOT be recognized as VPN")
        precondition(TunnelGuardWatchdog.isVpnInterface("tun0"), "tun0 must be recognized as VPN")
        precondition(TunnelGuardWatchdog.isVpnInterface("tap0"), "tap0 must be recognized as VPN")
        precondition(TunnelGuardWatchdog.isVpnInterface("ppp0"), "ppp0 must be recognized as VPN")
        precondition(TunnelGuardWatchdog.isVpnInterface("cscotun0"), "cscotun0 must be recognized as VPN")
        precondition(TunnelGuardWatchdog.isVpnInterface("fctun0"), "fctun0 must be recognized as VPN")
        precondition(TunnelGuardWatchdog.isVpnInterface("ipsec0"), "ipsec0 must be recognized as VPN")
        precondition(!TunnelGuardWatchdog.isVpnInterface(""), "empty interface must NOT be recognized as VPN")

        // 1.3 checkVpnTunnel with mock route binaries
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Case A: Mock route returning utun12 for 1.1.1.1
        let mockScriptUtun = tempDir.appendingPathComponent("mock_route_utun.sh")
        let scriptA = """
        #!/bin/sh
        echo "   route to: $3"
        echo "  interface: utun12"
        """
        try! scriptA.write(to: mockScriptUtun, atomically: true, encoding: .utf8)
        try! FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: mockScriptUtun.path)

        let resA = TunnelGuardWatchdog.checkVpnTunnel(routeExecutableURL: mockScriptUtun)
        precondition(resA.isVpn == true, "checkVpnTunnel must return isVpn=true for utun12")
        precondition(resA.iface == "utun12", "checkVpnTunnel must return iface=utun12")

        // Case B: Mock route returning en0 for 1.1.1.1, but utun4 for default (fallback)
        let mockScriptFallback = tempDir.appendingPathComponent("mock_route_fallback.sh")
        let scriptB = """
        #!/bin/sh
        if [ "$3" = "1.1.1.1" ]; then
            echo "  interface: en0"
        else
            echo "  interface: utun4"
        fi
        """
        try! scriptB.write(to: mockScriptFallback, atomically: true, encoding: .utf8)
        try! FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: mockScriptFallback.path)

        let resB = TunnelGuardWatchdog.checkVpnTunnel(routeExecutableURL: mockScriptFallback)
        precondition(resB.isVpn == true, "checkVpnTunnel must fallback to default route when 1.1.1.1 is non-utun")
        precondition(resB.iface == "utun4", "checkVpnTunnel fallback must return utun4")

        // Case C: Mock route returning en0 for both 1.1.1.1 and default
        let mockScriptNonVpn = tempDir.appendingPathComponent("mock_route_nonvpn.sh")
        let scriptC = """
        #!/bin/sh
        echo "  interface: en0"
        """
        try! scriptC.write(to: mockScriptNonVpn, atomically: true, encoding: .utf8)
        try! FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: mockScriptNonVpn.path)

        let resC = TunnelGuardWatchdog.checkVpnTunnel(routeExecutableURL: mockScriptNonVpn)
        precondition(resC.isVpn == false, "checkVpnTunnel must return isVpn=false when route is en0")
        precondition(resC.iface == "en0", "checkVpnTunnel must return iface=en0")

        print("  ✓ Interface detection (utun vs non-utun and fallback): passed")
    }

    // MARK: - 2. DNS Hang & Timeout Protection

    static func testDnsHangTimeoutProtection() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Hanging mock script that simulates DNS freeze by sleeping for 5 seconds
        let hangingScript = tempDir.appendingPathComponent("hanging_route.sh")
        let hangingContent = """
        #!/bin/sh
        sleep 5
        echo "  interface: utun99"
        """
        try! hangingContent.write(to: hangingScript, atomically: true, encoding: .utf8)
        try! FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hangingScript.path)

        let start = Date()
        let iface = TunnelGuardWatchdog.getRouteInterface(
            dest: "1.1.1.1",
            routeExecutableURL: hangingScript,
            timeoutSeconds: 0.25
        )
        let elapsed = Date().timeIntervalSince(start)

        precondition(elapsed < 1.0, "getRouteInterface must timeout and terminate within ~0.25-0.8s, took \(elapsed)s")
        precondition(iface == "", "getRouteInterface on hanging process must return empty string, got '\(iface)'")

        print("  ✓ DNS hang timeout protection (terminated in \(String(format: "%.3f", elapsed))s): passed")
    }

    // MARK: - 3. VPN Drop Behavior & Edge Triggering

    @MainActor
    static func testVpnDropBehaviorAndEdgeTriggering() {
        AppState.shared.resetTestCounters()
        let watchdog = TunnelGuardWatchdog()
        // Unit test safety: prevent firing live pkill against host development environment
        watchdog.targets = []
        watchdog.alarmSoundEnabled = false
        watchdog.macNotificationsEnabled = false

        precondition(watchdog.isVpnActive == true, "Initial watchdog status must be active")
        precondition(AppState.shared.view == .overview, "Initial AppState view must be .overview")
        precondition(AppState.shared.triggerCount == 0, "Initial panic trigger count must be 0")

        // 3.1 Steady active state
        watchdog.handleNetworkTransition(isVpn: true, iface: "utun22")
        precondition(watchdog.isVpnActive == true)
        precondition(watchdog.lastVpnIface == "utun22")
        precondition(AppState.shared.triggerCount == 0, "Steady state must not trigger panic")
        precondition(AppState.shared.view == .overview)

        // 3.2 VPN Drop transition (true -> false): Edge Triggered!
        watchdog.handleNetworkTransition(isVpn: false, iface: "en0")
        precondition(watchdog.isVpnActive == false, "Watchdog must record isVpnActive=false")
        precondition(watchdog.lastVpnIface == "en0", "Watchdog must record lastVpnIface=en0")
        precondition(AppState.shared.view == .securityPanic, "AppState view must switch to .securityPanic")
        precondition(AppState.shared.triggerCount == 1, "Panic must be triggered on VPN drop")
        precondition(AppState.shared.securityAlarmText.contains("VPN отключен!"),
                     "Alarm text must explain VPN disconnection")

        // 3.3 VPN stays down (false -> false): Edge Trigger must NOT re-trigger!
        watchdog.handleNetworkTransition(isVpn: false, iface: "en0")
        precondition(watchdog.isVpnActive == false)
        precondition(AppState.shared.triggerCount == 1,
                     "Edge-triggering must prevent duplicate panic triggers while VPN remains down")

        // 3.4 VPN Restored (false -> true)
        watchdog.handleNetworkTransition(isVpn: true, iface: "utun22")
        precondition(watchdog.isVpnActive == true, "Watchdog must record isVpnActive=true")
        precondition(watchdog.lastVpnIface == "utun22")
        precondition(AppState.shared.view == .overview, "AppState view must reset to .overview upon VPN restoration")
        precondition(AppState.shared.resetCount == 1, "resetSecurityAlert must be called upon restoration")
        precondition(AppState.shared.securityAlarmText == "", "Alarm text must be cleared")

        // 3.5 Steady state with restored VPN (true -> true)
        watchdog.handleNetworkTransition(isVpn: true, iface: "utun22")
        precondition(AppState.shared.resetCount == 1, "No extra reset call when already in steady active state")
        precondition(AppState.shared.triggerCount == 1, "No panic triggers in steady active state")

        AppState.shared.resetTestCounters()
        print("  ✓ VPN drop behavior & edge triggering: passed")
    }

    // MARK: - 4. Log Directory Creation & Entry Format

    static func testLogDirectoryAndFormat() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tunnelguard_log_test_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        precondition(!FileManager.default.fileExists(atPath: tempDir.path), "Test dir should not exist yet")

        // Write first event
        TunnelGuardWatchdog.logSecurityEvent("Unit test security event alpha", logDirURL: tempDir)

        let logFile = tempDir.appendingPathComponent("watchdog.log")
        precondition(FileManager.default.fileExists(atPath: logFile.path), "watchdog.log must be created")

        guard let content = try? String(contentsOf: logFile, encoding: .utf8) else {
            fatalError("Failed to read created watchdog.log")
        }

        // Verify log format: "yyyy-MM-dd HH:mm:ss [TUNNELGUARD_WATCHDOG] <message>\n"
        let pattern = #"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} \[TUNNELGUARD_WATCHDOG\] Unit test security event alpha\n$"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let matches = regex.matches(in: content, range: NSRange(location: 0, length: content.utf16.count))
        precondition(!matches.isEmpty, "Log content '\(content)' did not match expected format pattern")

        // Append second event
        TunnelGuardWatchdog.logSecurityEvent("Unit test security event beta", logDirURL: tempDir)
        let updatedContent = try! String(contentsOf: logFile, encoding: .utf8)
        precondition(updatedContent.contains("Unit test security event alpha"))
        precondition(updatedContent.contains("Unit test security event beta"))

        print("  ✓ Log directory creation & timestamp format: passed")
    }

    // MARK: - 5. Log Rotation (> 5MB)

    static func testLogRotation() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tunnelguard_rotate_test_\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let logFile = tempDir.appendingPathComponent("watchdog.log")
        let oldLogFile = tempDir.appendingPathComponent("watchdog.log.old")

        // Create a 5.2 MB file (exceeds 5 * 1024 * 1024 threshold)
        let dummyBlock = Data(repeating: 0x41, count: 1024 * 1024) // 1MB
        try! dummyBlock.write(to: logFile)
        let handle = try! FileHandle(forWritingTo: logFile)
        handle.seekToEndOfFile()
        for _ in 0..<4 {
            handle.write(dummyBlock)
        }
        let extra = Data(repeating: 0x42, count: 300 * 1024) // 300KB
        handle.write(extra)
        handle.closeFile()

        let sizeBefore = (try! FileManager.default.attributesOfItem(atPath: logFile.path))[.size] as! UInt64
        precondition(sizeBefore > 5 * 1024 * 1024, "File must exceed 5MB prior to rotation test")

        // Calling logSecurityEvent must trigger rotation
        TunnelGuardWatchdog.logSecurityEvent("Rotated fresh message", logDirURL: tempDir)

        precondition(FileManager.default.fileExists(atPath: oldLogFile.path),
                     "watchdog.log.old must exist after rotation")
        let oldSize = (try! FileManager.default.attributesOfItem(atPath: oldLogFile.path))[.size] as! UInt64
        precondition(oldSize == sizeBefore, "watchdog.log.old must contain previous log content")

        let newContent = try! String(contentsOf: logFile, encoding: .utf8)
        precondition(newContent.contains("Rotated fresh message"), "watchdog.log must contain newly logged message")
        precondition(newContent.count < 1000, "New watchdog.log must only contain fresh log entry, not old 5MB data")

        print("  ✓ Log rotation (5MB threshold to watchdog.log.old): passed")
    }

    // MARK: - 6. Target Process List & pkill Command

    static func testTargetProcessList() {
        let targets = TunnelGuardWatchdog.targetProcessExactNames
        let expected = ["claude", "agy", "codex", "gemini", "cursor-agent"]

        precondition(targets == expected, "Target process list must match expected agent names: \(expected)")

        // Safe execution of pkill for non-matching test target
        TunnelGuardWatchdog.killTargetProcesses(targets: ["dummy_nonexistent_process_xyz_99"])

        print("  ✓ Target process list exact names & pkill: passed")
    }
}
