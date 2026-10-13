import Foundation
import AppKit
import Darwin

@MainActor
final class GestapoWatchdog: ObservableObject {
    static let shared = GestapoWatchdog()

    @Published private(set) var isVpnActive: Bool = true
    @Published private(set) var lastVpnIface: String = ""

    private var previousVpnActive: Bool = true
    private var monitorTimer: Timer?
    private let queue = DispatchQueue(label: "com.gestapo.coucou.watchdog", qos: .userInitiated)
    private var isChecking: Bool = false

    /// Точные имена исполняемых файлов (флаг -x исключает ложные срабатывания)
    private static let targetProcessExactNames = [
        "claude",
        "agy",
        "codex",
        "gemini",
        "cursor-agent"
    ]

    private init() {}

    func start() {
        checkNetwork()

        // Таймер в режиме .common для работы даже при открытых системных меню
        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.checkNetwork()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.monitorTimer = timer
    }

    func stop() {
        monitorTimer?.invalidate()
        monitorTimer = nil
    }

    /// Проверка маршрута через /sbin/route (nonisolated для Swift 6 Strict Concurrency)
    nonisolated static func getRouteInterface(dest: String = "1.1.1.1") -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/sbin/route")
        task.arguments = ["-n", "get", dest]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        let timeoutItem = DispatchWorkItem { [weak task] in
            if let task, task.isRunning {
                task.terminate()
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.8, execute: timeoutItem)
        defer { timeoutItem.cancel() }

        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            if let output = String(data: data, encoding: .utf8) {
                for line in output.components(separatedBy: .newlines) {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix("interface:") {
                        return trimmed.replacingOccurrences(of: "interface:", with: "").trimmingCharacters(in: .whitespaces)
                    }
                }
            }
        } catch {}
        return ""
    }

    nonisolated static func checkVpnTunnel() -> (isVpn: Bool, iface: String) {
        var iface = getRouteInterface(dest: "1.1.1.1")
        if !iface.hasPrefix("utun") {
            let defIface = getRouteInterface(dest: "default")
            if defIface.hasPrefix("utun") {
                iface = defIface
            }
        }
        return (iface.hasPrefix("utun"), iface)
    }

    private func checkNetwork() {
        guard !isChecking else { return }
        isChecking = true

        queue.async {
            let (isVpn, iface) = Self.checkVpnTunnel()

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isChecking = false
                self.lastVpnIface = iface
                let prevActive = self.previousVpnActive
                self.isVpnActive = isVpn
                self.previousVpnActive = isVpn

                if prevActive && !isVpn {
                    // Edge-Triggered: тревога и ликвидация только в момент падения VPN (переход true -> false)
                    self.executeGestapoHardKill(detectedIface: iface)
                } else if isVpn && AppState.shared.view == .securityPanic {
                    // Восстановление
                    AppState.shared.resetSecurityAlert()
                    self.queue.async {
                        Self.logSecurityEvent("🟢 [WATCHDOG] VPN туннель восстановлен: \(iface)")
                    }
                }
            }
        }
    }

    /// Точечная ликвидация процессов агентов (флаг -x)
    private func executeGestapoHardKill(detectedIface: String) {
        // Активация режима тревоги в чёлке
        AppState.shared.triggerSecurityPanic(
            message: "VPN отключен! AI-агенты принудительно ликвидированы."
        )

        // Звуковое оповещение только на edge-переходе
        NSSound.beep()

        // Вынос логирования и pkill на фоновую очередь
        let targets = Self.targetProcessExactNames
        queue.async {
            Self.logSecurityEvent("🚨 [KILL-SWITCH] VPN упал! Обнаружен интерфейс: \(detectedIface). Немедленная ликвидация агентов.")
            Self.killTargetProcesses(targets: targets)
        }
    }

    nonisolated private static func killTargetProcesses(targets: [String]) {
        for binName in targets {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
            task.arguments = ["-9", "-x", binName]
            do {
                try task.run()
                task.waitUntilExit()
            } catch {}
        }
    }

    nonisolated private static func logSecurityEvent(_ message: String) {
        let logDir = URL(fileURLWithPath: (NSHomeDirectory() as NSString).appendingPathComponent("Library/Logs/Gestapo"))
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        let logFile = logDir.appendingPathComponent("watchdog.log")

        // Ротация логов при превышении 5 МБ
        if let attrs = try? FileManager.default.attributesOfItem(atPath: logFile.path),
           let size = attrs[.size] as? UInt64, size > 5 * 1024 * 1024 {
            let oldLog = logDir.appendingPathComponent("watchdog.log.old")
            try? FileManager.default.removeItem(at: oldLog)
            try? FileManager.default.moveItem(at: logFile, to: oldLog)
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let timestamp = formatter.string(from: Date())
        let line = "\(timestamp) [GESTAPO_WATCHDOG] \(message)\n"

        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFile.path),
               let handle = try? FileHandle(forWritingTo: logFile) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            } else {
                try? data.write(to: logFile)
            }
        }
    }
}
