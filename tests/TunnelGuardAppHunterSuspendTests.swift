import Foundation

@main
enum TunnelGuardAppHunterSuspendTests {
    static func main() throws {
        testSafeExecutableNameFiltering()
        try testSuspendAllActiveTargetsInvokesPkillWithStop()
        try testResumeAllActiveTargetsInvokesPkillWithCont()
        try testNonZeroExitCodeNotReportedAsAffected()
        print("✅ testAppHunterSuspendResume passed")
        print("TunnelGuard AppHunter Suspend/Resume tests: all passed")
    }

    static func testSafeExecutableNameFiltering() {
        let dummyTarget = TunnelGuardTargetApp(id: "dummy", name: "Dummy", type: .cli, binaryOrBundleId: "dummy-agent", domain: "")
        assert(TunnelGuardAppHunter.isSafeExecutableName(dummyTarget.binaryOrBundleId))
        assert(TunnelGuardAppHunter.isSafeExecutableName("claude"))
        assert(TunnelGuardAppHunter.isSafeExecutableName("agy"))
        assert(!TunnelGuardAppHunter.isSafeExecutableName("/bin/sh"))
        assert(!TunnelGuardAppHunter.isSafeExecutableName("-flag"))
        assert(!TunnelGuardAppHunter.isSafeExecutableName("hello world"))
        assert(TunnelGuardAppHunter.isProtectedProcess("zsh"))
        assert(TunnelGuardAppHunter.isProtectedProcess("coucou"))
        assert(!TunnelGuardAppHunter.isProtectedProcess("dummy-agent"))
        print("  ✓ safe executable and protected process checks")
    }

    static func testSuspendAllActiveTargetsInvokesPkillWithStop() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tunnelguard-suspend-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let capture = directory.appendingPathComponent("pkill-args.txt")
        let script = directory.appendingPathComponent("mock-pkill.sh")
        let capturePath = capture.path.replacingOccurrences(of: "'", with: "'\\''")
        try "#!/bin/sh\nprintf '%s|%s|%s\\n' \"$1\" \"$2\" \"$3\" >> '\(capturePath)'\nexit 0\n"
            .write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        let targets = [
            TunnelGuardTargetApp(id: "claude-cli", name: "Claude CLI", type: .cli, binaryOrBundleId: "claude", domain: "claude.ai"),
            TunnelGuardTargetApp(id: "agy-cli", name: "Antigravity CLI", type: .cli, binaryOrBundleId: "agy", domain: "generativelanguage.googleapis.com"),
            TunnelGuardTargetApp(id: "gui-app", name: "Claude Desktop", type: .gui, binaryOrBundleId: "com.anthropic.claudefordesktop", domain: "claude.ai"),
            TunnelGuardTargetApp(id: "unsafe", name: "Unsafe CLI", type: .cli, binaryOrBundleId: "/usr/local/bin/agent", domain: "example.com"),
            TunnelGuardTargetApp(id: "protected", name: "Zsh CLI", type: .cli, binaryOrBundleId: "zsh", domain: "example.com")
        ]

        let affected = TunnelGuardAppHunter.suspendAllActiveTargets(
            targets: targets,
            pkillExecutableURL: script
        )

        let captured = try String(contentsOf: capture, encoding: .utf8)
        precondition(affected == ["Claude CLI", "Antigravity CLI"], "Only valid non-whitelisted CLI targets should be affected")
        precondition(captured == "-STOP|-x|claude\n-STOP|-x|agy\n",
                     "pkill must receive exact -STOP -x <binary> arguments; got \(captured.debugDescription)")
        print("  ✓ suspendAllActiveTargets invokes pkill -STOP -x on CLI targets only")
    }

    static func testResumeAllActiveTargetsInvokesPkillWithCont() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tunnelguard-resume-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let capture = directory.appendingPathComponent("pkill-args.txt")
        let script = directory.appendingPathComponent("mock-pkill.sh")
        let capturePath = capture.path.replacingOccurrences(of: "'", with: "'\\''")
        try "#!/bin/sh\nprintf '%s|%s|%s\\n' \"$1\" \"$2\" \"$3\" >> '\(capturePath)'\nexit 0\n"
            .write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        let targets = [
            TunnelGuardTargetApp(id: "codex-cli", name: "Codex CLI", type: .cli, binaryOrBundleId: "codex", domain: "chatgpt.com"),
            TunnelGuardTargetApp(id: "gui-app", name: "ChatGPT Desktop", type: .gui, binaryOrBundleId: "com.openai.chat", domain: "chatgpt.com"),
            TunnelGuardTargetApp(id: "protected", name: "Terminal", type: .cli, binaryOrBundleId: "terminal", domain: "example.com")
        ]

        let affected = TunnelGuardAppHunter.resumeAllActiveTargets(
            targets: targets,
            pkillExecutableURL: script
        )

        let captured = try String(contentsOf: capture, encoding: .utf8)
        precondition(affected == ["Codex CLI"], "Only valid non-whitelisted CLI targets should be affected")
        precondition(captured == "-CONT|-x|codex\n",
                     "pkill must receive exact -CONT -x <binary> arguments; got \(captured.debugDescription)")
        print("  ✓ resumeAllActiveTargets invokes pkill -CONT -x on CLI targets only")
    }

    static func testNonZeroExitCodeNotReportedAsAffected() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tunnelguard-nonzero-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let script = directory.appendingPathComponent("mock-pkill-fail.sh")
        try "#!/bin/sh\nexit 1\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        let targets = [
            TunnelGuardTargetApp(id: "claude-cli", name: "Claude CLI", type: .cli, binaryOrBundleId: "claude", domain: "claude.ai")
        ]

        let suspended = TunnelGuardAppHunter.suspendAllActiveTargets(targets: targets, pkillExecutableURL: script)
        precondition(suspended.isEmpty, "Failed pkill should not report targets as affected")

        let resumed = TunnelGuardAppHunter.resumeAllActiveTargets(targets: targets, pkillExecutableURL: script)
        precondition(resumed.isEmpty, "Failed pkill should not report targets as affected")
        print("  ✓ non-zero pkill exit code does not report targets as affected")
    }
}
