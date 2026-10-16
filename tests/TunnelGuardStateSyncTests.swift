import Foundation
import AppKit

enum IslandView: String, CaseIterable {
    case overview, securityPanic
}

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()
    var view: IslandView = .overview
    var securityAlarmText: String = ""

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
enum TunnelGuardStateSyncTests {
    @MainActor
    static func main() {
        print("=== TunnelGuard State Sync Tests ===")

        testDefaultStateFileURL()
        testSyncRuntimeStateFile()
        testEnabledChangeSync()
        testTargetChangeSync()
        testCleanupRuntimeStateFile()
        testStopAndApplicationWillTerminate()

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
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tg-sync-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let watchdog = TunnelGuardWatchdog(settingsDefaults: defaults, stateDirectoryURL: tempDir)

        watchdog.syncRuntimeStateFile(stateDirURL: tempDir)

        let stateFile = tempDir.appendingPathComponent("tunnelguard-state.json")
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
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tg-enabled-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let watchdog = TunnelGuardWatchdog(settingsDefaults: defaults, stateDirectoryURL: tempDir)

        watchdog.syncRuntimeStateFile(stateDirURL: tempDir)

        // Disable TunnelGuard
        watchdog.isEnabled = false
        watchdog.syncRuntimeStateFile(stateDirURL: tempDir)

        let stateFile = tempDir.appendingPathComponent("tunnelguard-state.json")
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
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tg-targets-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let watchdog = TunnelGuardWatchdog(settingsDefaults: defaults, stateDirectoryURL: tempDir)

        // Custom target list: only claude
        watchdog.targets = [
            TunnelGuardTargetApp(id: "claude-cli", name: "Claude CLI", type: .cli, binaryOrBundleId: "claude", domain: "claude.ai")
        ]
        watchdog.syncRuntimeStateFile(stateDirURL: tempDir)

        let stateFile = tempDir.appendingPathComponent("tunnelguard-state.json")
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
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tg-cleanup-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let watchdog = TunnelGuardWatchdog(settingsDefaults: defaults, stateDirectoryURL: tempDir)

        // First sync running=true
        watchdog.syncRuntimeStateFile(stateDirURL: tempDir)

        // Cleanup
        watchdog.cleanupRuntimeStateFile(stateDirURL: tempDir)

        let stateFile = tempDir.appendingPathComponent("tunnelguard-state.json")
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
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tg-stop-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let watchdog = TunnelGuardWatchdog(settingsDefaults: defaults, stateDirectoryURL: tempDir)

        let stateFile = tempDir.appendingPathComponent("tunnelguard-state.json")
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
}
