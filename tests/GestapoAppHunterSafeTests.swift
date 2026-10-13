import Foundation
import AppKit

private final class MockRunningApplication {
    let processIdentifier: Int32
    let bundleIdentifier: String?
    private(set) var forceTerminateCalls = 0

    init(processIdentifier: Int32, bundleIdentifier: String?) {
        self.processIdentifier = processIdentifier
        self.bundleIdentifier = bundleIdentifier
    }

    lazy var snapshot: GestapoRunningApplication = GestapoRunningApplication(
        processIdentifier: processIdentifier,
        bundleIdentifier: bundleIdentifier,
        forceTerminate: { [weak self] in
            guard let self else { return false }
            forceTerminateCalls += 1
            return true
        }
    )
}

@main
enum GestapoAppHunterSafeTests {
    static func main() throws {
        testWhitelistIsExact()
        try testGuiTerminationUsesForceTerminateAndExactBundleID()
        try testCliTerminationUsesExactPkillArguments()
        testNotificationScriptEscaping()
        print("Gestapo AppHunter Phase 2 safe tests: all passed")
    }

    static func testWhitelistIsExact() {
        precondition(GestapoAppHunter.isProtectedProcess("coucou"))
        precondition(GestapoAppHunter.isProtectedProcess("/usr/bin/zsh"))
        precondition(GestapoAppHunter.isProtectedProcess(" TERMINAL\n"))
        precondition(!GestapoAppHunter.isProtectedProcess("coucou-helper"),
                     "Whitelist must not match a process by substring")
        precondition(!GestapoAppHunter.isProtectedProcess("bash-malware"),
                     "Whitelist must not match a process by substring")
        precondition(!GestapoAppHunter.isProtectedProcess("/tmp/coucou-helper"))
        precondition(!GestapoAppHunter.isSafeExecutableName("/tmp/claude"))
        precondition(!GestapoAppHunter.isSafeExecutableName("-x"))
        precondition(!GestapoAppHunter.isSafeExecutableName("claude agent"))
        precondition(GestapoAppHunter.isSafeExecutableName("cursor-agent"))
        print("  ✓ exact process whitelist and pkill name validation")
    }

    static func testGuiTerminationUsesForceTerminateAndExactBundleID() throws {
        let exact = MockRunningApplication(
            processIdentifier: ProcessInfo.processInfo.processIdentifier + 10,
            bundleIdentifier: "com.example.target"
        )
        let prefixOnly = MockRunningApplication(
            processIdentifier: ProcessInfo.processInfo.processIdentifier + 11,
            bundleIdentifier: "com.example.target.helper"
        )
        let selfProcess = MockRunningApplication(
            processIdentifier: ProcessInfo.processInfo.processIdentifier,
            bundleIdentifier: "com.example.target"
        )
        let target = GestapoTargetApp(
            id: "gui-test",
            name: "GUI test",
            type: .gui,
            binaryOrBundleId: "com.example.target",
            domain: "example.com"
        )

        let killed = GestapoAppHunter.killAllActiveTargets(
            targets: [target],
            pkillExecutableURL: URL(fileURLWithPath: "/usr/bin/false"),
            runningApplications: [exact.snapshot, prefixOnly.snapshot, selfProcess.snapshot]
        )

        precondition(killed == ["GUI test"], "Only the exact GUI bundle should be reported as killed")
        precondition(exact.forceTerminateCalls == 1, "GUI target must use forceTerminate exactly once")
        precondition(prefixOnly.forceTerminateCalls == 0, "Bundle ID prefix must not be terminated")
        precondition(selfProcess.forceTerminateCalls == 0, "Gestapo must never terminate its own PID")
        print("  ✓ GUI forceTerminate seam and exact bundle matching")
    }

    static func testCliTerminationUsesExactPkillArguments() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gestapo-app-hunter-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let capture = directory.appendingPathComponent("pkill-args.txt")
        let script = directory.appendingPathComponent("mock-pkill.sh")
        let capturePath = capture.path.replacingOccurrences(of: "'", with: "'\\''")
        try "#!/bin/sh\nprintf '%s|%s|%s\\n' \"$1\" \"$2\" \"$3\" >> '\(capturePath)'\nexit 0\n"
            .write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        let targets = [
            GestapoTargetApp(id: "one", name: "Claude", type: .cli, binaryOrBundleId: "claude", domain: "claude.ai"),
            GestapoTargetApp(id: "two", name: "Cursor", type: .cli, binaryOrBundleId: "cursor-agent", domain: "cursor.sh"),
            GestapoTargetApp(id: "unsafe-path", name: "Unsafe", type: .cli, binaryOrBundleId: "/tmp/agent", domain: "example.com"),
            GestapoTargetApp(id: "protected", name: "Shell", type: .cli, binaryOrBundleId: "zsh", domain: "example.com")
        ]

        let killed = GestapoAppHunter.killAllActiveTargets(
            targets: targets,
            pkillExecutableURL: script,
            runningApplications: []
        )
        let captured = try String(contentsOf: capture, encoding: .utf8)
        precondition(killed == ["Claude", "Cursor"], "Only valid non-whitelisted CLI targets should be reported")
        precondition(captured == "-9|-x|claude\n-9|-x|cursor-agent\n",
                     "pkill must receive exact -9 -x <binary> arguments; got \(captured.debugDescription)")
        print("  ✓ CLI exact pkill invocation through safe mock executable")
    }

    static func testNotificationScriptEscaping() {
        let script = GestapoAppHunter.notificationScript(
            title: "title\\\"",
            message: "line1\nline2\t\\\"\u{0001}"
        )
        precondition(script == "display notification \"line1\\nline2\\t\\\\\\\" \" with title \"title\\\\\\\"\" sound name \"Basso\"",
                     "Notification text must escape AppleScript delimiters and controls: \(script.debugDescription)")
        print("  ✓ macOS notification AppleScript escaping")
    }
}
