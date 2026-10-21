import Foundation
import AppKit

/// Минимальный снимок запущенного GUI-приложения.
///
/// `NSRunningApplication` нельзя создать в изолированных тестах. Этот seam
/// оставляет в production только тонкий адаптер AppKit, а тесты могут
/// подставить безопасный mock, не запуская и не завершая реальные процессы.
struct TunnelGuardRunningApplication {
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

/// Описание целевого приложения или CLI-агента под защитой TunnelGuard
struct TunnelGuardTargetApp: Sendable, Identifiable, Equatable {
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

/// TunnelGuardAppHunter отвечает за обнаружение и гарантированную ликвидацию
/// защищаемых процессов (как консольных агентов, так и оконных приложений macOS).
final class TunnelGuardAppHunter: Sendable {

    /// Предустановленный список целей TunnelGuard
    nonisolated static let defaultTargets: [TunnelGuardTargetApp] = [
        // CLI-агенты
        TunnelGuardTargetApp(id: "claude-cli", name: "Claude CLI", type: .cli, binaryOrBundleId: "claude", domain: "claude.ai"),
        TunnelGuardTargetApp(id: "agy-cli", name: "Antigravity CLI", type: .cli, binaryOrBundleId: "agy", domain: "generativelanguage.googleapis.com"),
        TunnelGuardTargetApp(id: "codex-cli", name: "Codex CLI", type: .cli, binaryOrBundleId: "codex", domain: "chatgpt.com"),
        TunnelGuardTargetApp(id: "gemini-cli", name: "Gemini CLI", type: .cli, binaryOrBundleId: "gemini", domain: "generativelanguage.googleapis.com"),
        TunnelGuardTargetApp(id: "cursor-agent-cli", name: "Cursor Agent", type: .cli, binaryOrBundleId: "cursor-agent", domain: "cursor.sh"),

        // Оконные GUI-приложения
        TunnelGuardTargetApp(id: "claude-desktop", name: "Claude Desktop", type: .gui, binaryOrBundleId: "com.anthropic.claudefordesktop", domain: "claude.ai"),
        TunnelGuardTargetApp(id: "chatgpt-desktop", name: "ChatGPT Desktop", type: .gui, binaryOrBundleId: "com.openai.chat", domain: "chatgpt.com"),
        TunnelGuardTargetApp(id: "antigravity-desktop", name: "Antigravity Desktop", type: .gui, binaryOrBundleId: "com.google.antigravity", domain: "generativelanguage.googleapis.com"),
        TunnelGuardTargetApp(id: "antigravity-ide", name: "Antigravity IDE", type: .gui, binaryOrBundleId: "com.google.antigravity.ide", domain: "generativelanguage.googleapis.com")
    ]

    /// Имена бинарников CLI по умолчанию
    nonisolated static var defaultCliBinaryNames: [String] {
        defaultTargets.filter { $0.type == .cli }.map { $0.binaryOrBundleId }
    }

    /// Белый список от самоубийства и повреждения системных процессов macOS
    nonisolated static let suicideWhitelist: Set<String> = [
        "coucou",
        "notchbuddy",
        "tunnelguard",
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
    nonisolated static func liveRunningApplications() -> [TunnelGuardRunningApplication] {
        NSWorkspace.shared.runningApplications.map { app in
            TunnelGuardRunningApplication(
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
        targets: [TunnelGuardTargetApp],
        pkillExecutableURL: URL = URL(fileURLWithPath: "/usr/bin/pkill"),
        runningApplications: [TunnelGuardRunningApplication]? = nil
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

    /// Приостановка всех активных CLI-целей из списка targets (SIGSTOP)
    /// Возвращает список имён приостановленных целей
    @discardableResult
    nonisolated static func suspendAllActiveTargets(
        targets: [TunnelGuardTargetApp],
        pkillExecutableURL: URL = URL(fileURLWithPath: "/usr/bin/pkill")
    ) -> [String] {
        sendCliSignal(signal: "-STOP", targets: targets, pkillExecutableURL: pkillExecutableURL)
    }

    /// Возобновление всех активных CLI-целей из списка targets (SIGCONT)
    /// Возвращает список имён возобновлённых целей
    @discardableResult
    nonisolated static func resumeAllActiveTargets(
        targets: [TunnelGuardTargetApp],
        pkillExecutableURL: URL = URL(fileURLWithPath: "/usr/bin/pkill")
    ) -> [String] {
        sendCliSignal(signal: "-CONT", targets: targets, pkillExecutableURL: pkillExecutableURL)
    }

    /// Поиск PID процессов для указанных CLI-целей через pgrep
    nonisolated static func findTargetPIDs(
        targets: [TunnelGuardTargetApp],
        pgrepExecutableURL: URL = URL(fileURLWithPath: "/usr/bin/pgrep")
    ) -> Set<pid_t> {
        var pids = Set<pid_t>()
        let currentPid = ProcessInfo.processInfo.processIdentifier
        let cliTargets = targets.filter { $0.type == .cli }
        for target in cliTargets {
            let binName = target.binaryOrBundleId
            guard isSafeExecutableName(binName), !isProtectedProcess(binName) else { continue }
            let task = Process()
            task.executableURL = pgrepExecutableURL
            task.arguments = ["-x", binName]
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = FileHandle.nullDevice
            do {
                try task.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                task.waitUntilExit()
                if task.terminationStatus == 0, let str = String(data: data, encoding: .utf8) {
                    for line in str.split(whereSeparator: \.isNewline) {
                        let trimmed = line.trimmingCharacters(in: .whitespaces)
                        if let pid = pid_t(trimmed), pid != currentPid && pid > 1 {
                            pids.insert(pid)
                        }
                    }
                }
            } catch {}
        }
        return pids
    }

    /// Возобновление процессов по списку PID (SIGCONT)
    @discardableResult
    nonisolated static func resumeProcesses(
        pids: Set<pid_t>,
        signalSender: (pid_t, Int32) -> Int32 = { kill($0, $1) }
    ) -> Set<pid_t> {
        var resumed = Set<pid_t>()
        for pid in pids {
            #if canImport(Darwin)
            if signalSender(pid, SIGCONT) == 0 {
                resumed.insert(pid)
            }
            #endif
        }
        return resumed
    }

    private nonisolated static func sendCliSignal(
        signal: String,
        targets: [TunnelGuardTargetApp],
        pkillExecutableURL: URL
    ) -> [String] {
        var affected: [String] = []
        let cliTargets = targets.filter { $0.type == .cli }
        for target in cliTargets {
            let binName = target.binaryOrBundleId
            guard isSafeExecutableName(binName), !isProtectedProcess(binName) else { continue }
            let task = Process()
            task.executableURL = pkillExecutableURL
            task.arguments = [signal, "-x", binName]
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            do {
                try task.run()
                task.waitUntilExit()
                if task.terminationStatus == 0 { affected.append(target.name) }
            } catch {}
        }
        return affected
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
