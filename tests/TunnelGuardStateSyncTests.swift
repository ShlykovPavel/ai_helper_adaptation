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

    func triggerSecurityPanic(message: String) {
        securityAlarmText = message
        view = .securityPanic
    }

    func resetSecurityAlert() {
        securityAlarmText = ""
        view = .overview
    }

    func triggerDeadTunnelPrompt(message: String = "") {
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
enum TunnelGuardStateSyncTests {
    @MainActor
    static func main() throws {
        print("=== TunnelGuard State Sync Tests ===")

        testDefaultStateFileURL()
        testSyncRuntimeStateFile()
        testEnabledChangeSync()
        testTargetChangeSync()
        testCleanupRuntimeStateFile()
        testStopAndApplicationWillTerminate()
        testDefaultStateFileUntouchedByWatchdog()
        try testExternalControlFileRemainsUntouched()
        testTestModeSafetyFallbackPreventsDefaultFileWrite()

        print("TunnelGuard State Sync: all cases passed")
    }

    static func testDefaultStateFileURL() {
        let url = TunnelGuardWatchdog.defaultStateFileURL
        precondition(url.lastPathComponent == "tunnelguard-state.json",
                     "Default state file name must be tunnelguard-state.json")
        precondition(url.path.contains("Library/Application Support/NotchBuddy"),
                     "Default state file must reside in ~/Library/Application Support/NotchBuddy")
        print("  ✓ defaultStateFileURL path: passed")
    }

    @MainActor
    static func testSyncRuntimeStateFile() {
        let context = TunnelGuardTestContext(prefix: "tg-sync-test")
        defer { context.tearDown() }

        let watchdog = context.makeWatchdog()
        watchdog.syncRuntimeStateFile(stateDirURL: context.tempDirectoryURL)

        let stateFile = context.stateFileURL
        precondition(FileManager.default.fileExists(atPath: stateFile.path),
                     "tunnelguard-state.json must be created in tempDir")

        guard let data = try? Data(contentsOf: stateFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            fatalError("Failed to parse tunnelguard-state.json as JSON dictionary")
        }

        precondition(json["running"] as? Bool == true, "running must be true")
        precondition(json["enabled"] as? Bool == true, "enabled must reflect isEnabled (true)")
        precondition(json["pid"] as? Int == Int(ProcessInfo.processInfo.processIdentifier),
                     "pid must match current process PID")

        let targets = json["protected_targets"] as? [String]
        let expectedTargets = ["claude", "agy", "codex", "gemini", "cursor-agent"]
        precondition(targets == expectedTargets,
                     "protected_targets must contain active CLI targets: \(String(describing: targets))")

        guard let domains = json["target_domains"] as? [String: String] else {
            fatalError("target_domains missing or not [String: String]")
        }
        precondition(domains["antigravity"] == "generativelanguage.googleapis.com", "antigravity domain mismatch")
        precondition(domains["agy"] == "generativelanguage.googleapis.com", "agy domain mismatch")
        precondition(domains["gemini"] == "generativelanguage.googleapis.com", "gemini domain mismatch")
        precondition(domains["claude"] == "claude.ai", "claude domain mismatch")
        precondition(domains["codex"] == "chatgpt.com", "codex domain mismatch")
        precondition(domains["cursor"] == "cursor.sh", "cursor domain mismatch")
        precondition(domains["cursor-agent"] == "cursor.sh", "cursor-agent domain mismatch")

        guard let updatedAt = json["updated_at"] as? Double else {
            fatalError("updated_at missing or not Double")
        }
        let now = Date().timeIntervalSince1970
        precondition(abs(updatedAt - now) < 5.0, "updated_at must be close to current time")

        print("  ✓ syncRuntimeStateFile writes valid JSON with running=true, pid, enabled, targets: passed")
    }

    @MainActor
    static func testEnabledChangeSync() {
        let context = TunnelGuardTestContext(prefix: "tg-enabled-test")
        defer { context.tearDown() }

        let watchdog = context.makeWatchdog()
        watchdog.syncRuntimeStateFile(stateDirURL: context.tempDirectoryURL)

        // Disable TunnelGuard
        watchdog.isEnabled = false
        watchdog.syncRuntimeStateFile(stateDirURL: context.tempDirectoryURL)

        let stateFile = context.stateFileURL
        guard let data = try? Data(contentsOf: stateFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            fatalError("Failed to parse state file after disabling")
        }

        precondition(json["running"] as? Bool == true, "running must remain true while app is active")
        precondition(json["enabled"] as? Bool == false, "enabled must be false when isEnabled=false")

        print("  ✓ changing isEnabled=false writes enabled=false: passed")
    }

    @MainActor
    static func testTargetChangeSync() {
        let context = TunnelGuardTestContext(prefix: "tg-targets-test")
        defer { context.tearDown() }

        let watchdog = context.makeWatchdog()

        // Custom target list: only claude
        watchdog.targets = [
            TunnelGuardTargetApp(id: "claude-cli", name: "Claude CLI", type: .cli, binaryOrBundleId: "claude", domain: "claude.ai")
        ]
        watchdog.syncRuntimeStateFile(stateDirURL: context.tempDirectoryURL)

        let stateFile = context.stateFileURL
        guard let data = try? Data(contentsOf: stateFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            fatalError("Failed to parse state file after target change")
        }

        precondition(json["protected_targets"] as? [String] == ["claude"],
                     "protected_targets must only contain claude")
        let domains = json["target_domains"] as? [String: String]
        precondition(domains?["claude"] == "claude.ai", "claude domain must be present")
        precondition(domains?["agy"] == nil, "agy should not be in target_domains when not in targets")

        print("  ✓ updating targets syncs protected_targets and target_domains: passed")
    }

    @MainActor
    static func testCleanupRuntimeStateFile() {
        let context = TunnelGuardTestContext(prefix: "tg-cleanup-test")
        defer { context.tearDown() }

        let watchdog = context.makeWatchdog()

        // First sync running=true
        watchdog.syncRuntimeStateFile(stateDirURL: context.tempDirectoryURL)

        // Cleanup
        watchdog.cleanupRuntimeStateFile(stateDirURL: context.tempDirectoryURL)

        let stateFile = context.stateFileURL
        guard let data = try? Data(contentsOf: stateFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            fatalError("Failed to parse state file after cleanup")
        }

        precondition(json["running"] as? Bool == false, "running must be false on cleanup")
        precondition(json["enabled"] as? Bool == false, "enabled must be false on cleanup")
        precondition(json["pid"] as? Int == Int(ProcessInfo.processInfo.processIdentifier),
                     "pid must be present on cleanup")

        print("  ✓ cleanupRuntimeStateFile writes running=false and enabled=false: passed")
    }

    @MainActor
    static func testStopAndApplicationWillTerminate() {
        let context = TunnelGuardTestContext(prefix: "tg-stop-test")
        defer { context.tearDown() }

        let watchdog = context.makeWatchdog()

        let stateFile = context.stateFileURL
        precondition(FileManager.default.fileExists(atPath: stateFile.path),
                     "State file should exist after initialization")

        // Call stop() -> triggers cleanupRuntimeStateFile
        watchdog.stop()

        guard let data = try? Data(contentsOf: stateFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            fatalError("Failed to parse state file after stop")
        }

        precondition(json["running"] as? Bool == false, "stop() must write running=false")
        precondition(json["enabled"] as? Bool == false, "stop() must write enabled=false")

        print("  ✓ stop() triggers cleanupRuntimeStateFile with running=false: passed")
    }

    @MainActor
    static func testDefaultStateFileUntouchedByWatchdog() {
        let defaultURL = TunnelGuardWatchdog.defaultStateFileURL
        let existsBefore = FileManager.default.fileExists(atPath: defaultURL.path)
        let dataBefore = try? Data(contentsOf: defaultURL)

        let context = TunnelGuardTestContext(prefix: "tg-untouched-test")
        let watchdog = context.makeWatchdog()
        watchdog.isEnabled = true
        watchdog.syncRuntimeStateFile()
        watchdog.targets = []
        watchdog.isEnabled = false
        watchdog.stop()
        context.tearDown()

        let existsAfter = FileManager.default.fileExists(atPath: defaultURL.path)
        precondition(existsBefore == existsAfter,
                     "Default state file existence changed! Before: \(existsBefore), after: \(existsAfter)")

        if existsBefore {
            let dataAfter = try? Data(contentsOf: defaultURL)
            precondition(dataBefore == dataAfter,
                         "Default state file was modified! Real user state must never be touched by tests.")
        }
        print("  ✓ default state file remains completely untouched by watchdog operations: passed")
    }

    @MainActor
    static func testExternalControlFileRemainsUntouched() throws {
        let controlDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tg-control-dir-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: controlDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: controlDir) }

        let controlFile = controlDir.appendingPathComponent("tunnelguard-state.json")
        let sentinelData = "{\"sentinel\": \"canary-guard-12345\"}".data(using: .utf8)!
        try sentinelData.write(to: controlFile)

        let context = TunnelGuardTestContext(prefix: "tg-canary-test")
        let watchdog = context.makeWatchdog()
        watchdog.isEnabled = true
        watchdog.syncRuntimeStateFile()
        watchdog.targets = []
        watchdog.stop()
        context.tearDown()

        let readControl = try Data(contentsOf: controlFile)
        precondition(readControl == sentinelData,
                     "Control file in external directory was modified by watchdog!")
        print("  ✓ control file outside test directory remains completely untouched: passed")
    }

    @MainActor
    static func testTestModeSafetyFallbackPreventsDefaultFileWrite() {
        let defaultURL = TunnelGuardWatchdog.defaultStateFileURL
        let dataBefore = try? Data(contentsOf: defaultURL)
        let existsBefore = FileManager.default.fileExists(atPath: defaultURL.path)

        // Bare TunnelGuardWatchdog() under TUNNELGUARD_TEST_MODE=1
        let bareWatchdog = TunnelGuardWatchdog()
        bareWatchdog.isEnabled = true
        bareWatchdog.syncRuntimeStateFile()
        bareWatchdog.isEnabled = false
        bareWatchdog.stop()

        let existsAfter = FileManager.default.fileExists(atPath: defaultURL.path)
        precondition(existsBefore == existsAfter, "Bare watchdog modified default state file existence!")
        if existsBefore {
            let dataAfter = try? Data(contentsOf: defaultURL)
            precondition(dataBefore == dataAfter, "Bare watchdog modified default state file content!")
        }
        print("  ✓ TUNNELGUARD_TEST_MODE fallback prevents bare watchdog from touching default file: passed")
    }
}
