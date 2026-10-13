import Foundation
import AppKit

/// Описание целевого приложения или CLI-агента под защитой Gestapo
struct GestapoTargetApp: Sendable, Identifiable, Equatable {
    enum TargetType: String, Sendable, Equatable {
        case cli
        case gui
    }

    let id: String
    let name: String
    let type: TargetType
    let binaryOrBundleId: String
    let domain: String
}

/// GestapoAppHunter отвечает за обнаружение и гарантированную ликвидацию
/// защищаемых процессов (как консольных агентов, так и оконных приложений macOS).
final class GestapoAppHunter: Sendable {

    /// Предустановленный список целей Gestapo
    nonisolated static let defaultTargets: [GestapoTargetApp] = [
        // CLI-агенты
        GestapoTargetApp(id: "claude-cli", name: "Claude CLI", type: .cli, binaryOrBundleId: "claude", domain: "claude.ai"),
        GestapoTargetApp(id: "agy-cli", name: "Antigravity CLI", type: .cli, binaryOrBundleId: "agy", domain: "generativelanguage.googleapis.com"),
        GestapoTargetApp(id: "codex-cli", name: "Codex CLI", type: .cli, binaryOrBundleId: "codex", domain: "chatgpt.com"),
        GestapoTargetApp(id: "gemini-cli", name: "Gemini CLI", type: .cli, binaryOrBundleId: "gemini", domain: "generativelanguage.googleapis.com"),
        GestapoTargetApp(id: "cursor-agent-cli", name: "Cursor Agent", type: .cli, binaryOrBundleId: "cursor-agent", domain: "cursor.sh"),

        // Оконные GUI-приложения
        GestapoTargetApp(id: "claude-desktop", name: "Claude Desktop", type: .gui, binaryOrBundleId: "com.anthropic.claudefordesktop", domain: "claude.ai"),
        GestapoTargetApp(id: "chatgpt-desktop", name: "ChatGPT Desktop", type: .gui, binaryOrBundleId: "com.openai.chat", domain: "chatgpt.com"),
        GestapoTargetApp(id: "antigravity-desktop", name: "Antigravity Desktop", type: .gui, binaryOrBundleId: "com.google.antigravity", domain: "generativelanguage.googleapis.com"),
        GestapoTargetApp(id: "antigravity-ide", name: "Antigravity IDE", type: .gui, binaryOrBundleId: "com.google.antigravity.ide", domain: "generativelanguage.googleapis.com")
    ]

    /// Имена бинарников CLI по умолчанию
    nonisolated static var defaultCliBinaryNames: [String] {
        defaultTargets.filter { $0.type == .cli }.map { $0.binaryOrBundleId }
    }

    /// Белый список от самоубийства и повреждения системных процессов macOS
    nonisolated static let suicideWhitelist: Set<String> = [
        "coucou",
        "notchbuddy",
        "gestapo",
        "terminal",
        "zsh",
        "bash",
        "login",
        "launchd",
        "sshd"
    ]

    nonisolated static func isProtectedProcess(_ identifier: String) -> Bool {
        let lower = identifier.lowercased()
        return suicideWhitelist.contains { lower.contains($0) }
    }

    /// Принудительная ликвидация всех активных целей из списка targets
    /// Возвращает список имён ликвидированных целей
    @discardableResult
    nonisolated static func killAllActiveTargets(
        targets: [GestapoTargetApp],
        pkillExecutableURL: URL = URL(fileURLWithPath: "/usr/bin/pkill")
    ) -> [String] {
        var killedNames: [String] = []
        let currentPid = ProcessInfo.processInfo.processIdentifier

        // 1. Ликвидация оконных GUI-приложений через NSWorkspace / NSRunningApplication
        let guiTargets = targets.filter { $0.type == .gui }
        if !guiTargets.isEmpty {
            let runningApps = NSWorkspace.shared.runningApplications
            for target in guiTargets {
                let targetIdLower = target.binaryOrBundleId.lowercased()
                if isProtectedProcess(targetIdLower) { continue }

                for app in runningApps {
                    guard app.processIdentifier != currentPid else { continue }
                    if let bundleId = app.bundleIdentifier?.lowercased(),
                       bundleId == targetIdLower || bundleId.hasPrefix(targetIdLower) {
                        app.forceTerminate()
                        killedNames.append(target.name)
                    }
                }
            }
        }

        // 2. Ликвидация консольных процессов через /usr/bin/pkill -9 -x
        let cliTargets = targets.filter { $0.type == .cli }
        for target in cliTargets {
            let binName = target.binaryOrBundleId
            if isProtectedProcess(binName) { continue }

            let task = Process()
            task.executableURL = pkillExecutableURL
            task.arguments = ["-9", "-x", binName]
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            do {
                try task.run()
                task.waitUntilExit()
                if task.terminationStatus == 0 {
                    killedNames.append(target.name)
                }
            } catch {}
        }

        return killedNames
    }

    /// Отправка нативного системного баннера macOS через osascript
    nonisolated static func sendMacNotification(title: String, message: String) {
        let escapedTitle = title
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let escapedMessage = message
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let script = "display notification \"\(escapedMessage)\" with title \"\(escapedTitle)\" sound name \"Basso\""
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
    }
}
