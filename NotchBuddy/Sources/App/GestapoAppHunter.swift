import Foundation
import AppKit

/// Минимальный снимок запущенного GUI-приложения.
///
/// `NSRunningApplication` нельзя создать в изолированных тестах. Этот seam
/// оставляет в production только тонкий адаптер AppKit, а тесты могут
/// подставить безопасный mock, не запуская и не завершая реальные процессы.
struct GestapoRunningApplication {
    let processIdentifier: Int32
    let bundleIdentifier: String?
    let forceTerminate: () -> Bool

    init(
        processIdentifier: Int32,
        bundleIdentifier: String?,
        forceTerminate: @escaping () -> Bool
    ) {
        self.processIdentifier = processIdentifier
        self.bundleIdentifier = bundleIdentifier
        self.forceTerminate = forceTerminate
    }
}

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
        // Сравниваем имя процесса целиком. Проверка по подстроке ошибочно
        // пропускала бы произвольные цели вроде "bash-helper" или
        // "notchbuddy-malware".
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let basename = trimmed.split(separator: "/").last.map(String.init) ?? trimmed
        return suicideWhitelist.contains(basename.lowercased())
    }

    /// Снимок AppKit-приложений для production-вызова. В тестах этот список
    /// заменяется параметром `runningApplications`.
    nonisolated static func liveRunningApplications() -> [GestapoRunningApplication] {
        NSWorkspace.shared.runningApplications.map { app in
            GestapoRunningApplication(
                processIdentifier: app.processIdentifier,
                bundleIdentifier: app.bundleIdentifier,
                forceTerminate: { app.forceTerminate() }
            )
        }
    }

    /// Имена, которые можно безопасно передать как один аргумент `pkill -x`.
    /// Это также не позволяет пользовательской настройке превратить команду
    /// в выбор по пути или в опцию `pkill`.
    nonisolated static func isSafeExecutableName(_ identifier: String) -> Bool {
        guard !identifier.isEmpty,
              identifier.first != "-",
              identifier.unicodeScalars.allSatisfy({
                  CharacterSet.alphanumerics.contains($0) || "._-".unicodeScalars.contains($0)
              }) else {
            return false
        }
        return true
    }

    /// Принудительная ликвидация всех активных целей из списка targets
    /// Возвращает список имён ликвидированных целей
    @discardableResult
    nonisolated static func killAllActiveTargets(
        targets: [GestapoTargetApp],
        pkillExecutableURL: URL = URL(fileURLWithPath: "/usr/bin/pkill"),
        runningApplications: [GestapoRunningApplication]? = nil
    ) -> [String] {
        var killedNames: [String] = []
        let currentPid = ProcessInfo.processInfo.processIdentifier

        // 1. Ликвидация оконных GUI-приложений через NSWorkspace / NSRunningApplication
        let guiTargets = targets.filter { $0.type == .gui }
        if !guiTargets.isEmpty {
            let runningApps = runningApplications ?? liveRunningApplications()
            for target in guiTargets {
                let targetIdLower = target.binaryOrBundleId.lowercased()
                if isProtectedProcess(targetIdLower) { continue }

                for app in runningApps {
                    guard app.processIdentifier != currentPid else { continue }
                    if let bundleId = app.bundleIdentifier?.lowercased(),
                       bundleId == targetIdLower,
                       app.forceTerminate() {
                        killedNames.append(target.name)
                    }
                }
            }
        }

        // 2. Ликвидация консольных процессов через /usr/bin/pkill -9 -x
        let cliTargets = targets.filter { $0.type == .cli }
        for target in cliTargets {
            let binName = target.binaryOrBundleId
            guard isSafeExecutableName(binName), !isProtectedProcess(binName) else { continue }

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
    nonisolated static func notificationScript(title: String, message: String) -> String {
        // AppleScript string literals escape backslash and quote. Control
        // characters are normalized so a hostile/newline-containing reason
        // cannot alter the generated script or produce a malformed banner.
        func escape(_ value: String) -> String {
            value.unicodeScalars.reduce(into: "") { result, scalar in
                switch scalar.value {
                case 0x08: result += "\\b"
                case 0x09: result += "\\t"
                case 0x0A: result += "\\n"
                case 0x0C: result += "\\f"
                case 0x0D: result += "\\r"
                case 0x00...0x1F, 0x7F: result += " "
                case 0x5C: result += "\\\\"
                case 0x22: result += "\\\""
                default: result.append(Character(scalar))
                }
            }
        }

        return "display notification \"\(escape(message))\" with title \"\(escape(title))\" sound name \"Basso\""
    }

    /// Отправка баннера macOS fire-and-forget. Запуск `osascript` и ожидание
    /// его завершения вынесены на utility queue, поэтому watchdog не ждёт
    /// Центр уведомлений и не задерживает kill-switch.
    nonisolated static func sendMacNotification(
        title: String,
        message: String,
        osascriptExecutableURL: URL = URL(fileURLWithPath: "/usr/bin/osascript")
    ) {
        let script = notificationScript(title: title, message: message)
        DispatchQueue.global(qos: .utility).async {
            let task = Process()
            task.executableURL = osascriptExecutableURL
            task.arguments = ["-e", script]
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            try? task.run()
        }
    }
}
