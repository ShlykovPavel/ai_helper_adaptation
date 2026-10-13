import Foundation
import AppKit
import Darwin

enum GestapoProtectionStatus: Equatable, Sendable {
    case disabled
    case grace
    case protected
    case vpnInactive
    case deadTunnel
    case splitTunnelLeak
}

/// Главный координатор системы безопасности Gestapo.
/// Объединяет GestapoPowerGuard, GestapoNetworkWorker и GestapoAppHunter
/// и предоставляет реактивный интерфейс для SwiftUI и Dynamic Island (чёлки).
@MainActor
final class GestapoWatchdog: ObservableObject {
    static let shared = GestapoWatchdog()

    // MARK: - Подсистемы
    let powerGuard: GestapoPowerGuard
    let networkWorker: GestapoNetworkWorker

    // MARK: - Реактивные свойства состояния
    @Published private(set) var isVpnActive: Bool = true
    @Published private(set) var lastVpnIface: String = ""
    @Published private(set) var lastGateway: String = ""
    @Published private(set) var pingLatencyMs: Double = 0.0
    @Published private(set) var isDeadTunnel: Bool = false
    @Published private(set) var externalIp: String = ""
    @Published private(set) var isCheckingIp: Bool = false
    @Published private(set) var isGracePeriodActive: Bool = false
    /// Единый статус, которым пользуются watchdog и UI. Он учитывает не только
    /// наличие utun, но и dead-tunnel/split-tunnel аварии.
    @Published private(set) var protectionStatus: GestapoProtectionStatus = .protected

    var canResetSecurityAlert: Bool { protectionStatus == .protected }

    // MARK: - Настройки и политики
    @Published var isEnabled: Bool = true
    @Published var continuousKill: Bool = true
    @Published var pingCheckEnabled: Bool = true
    @Published var splitTunnelCheck: Bool = false
    @Published var preventSleep: Bool = true
    @Published var sleepWakeGuardEnabled: Bool = true
    @Published var alarmSoundEnabled: Bool = true
    @Published var macNotificationsEnabled: Bool = true
    @Published var targets: [GestapoTargetApp] = GestapoAppHunter.defaultTargets

    // MARK: - Внутреннее состояние
    private var previousHealthy: Bool = true
    private var monitorTimer: Timer?
    private let queue = DispatchQueue(label: "com.gestapo.coucou.watchdog", qos: .userInitiated)
    private var isChecking: Bool = false

    /// Точные имена исполняемых файлов (флаг -x исключает ложные срабатывания)
    nonisolated static let targetProcessExactNames = [
        "claude",
        "agy",
        "codex",
        "gemini",
        "cursor-agent"
    ]

    init(
        powerGuard: GestapoPowerGuard = GestapoPowerGuard(),
        networkWorker: GestapoNetworkWorker = GestapoNetworkWorker()
    ) {
        self.powerGuard = powerGuard
        self.networkWorker = networkWorker
    }

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
        powerGuard.releaseOnTerminate()
    }

    func applicationWillTerminate() {
        stop()
    }

    // MARK: - Обработка сетевых переходов и Continuous Level-Triggered Kill

    func handleNetworkSnapshot(_ snapshot: NetworkSnapshot, isGrace: Bool) {
        let effectiveGrace = isGrace || powerGuard.isSleeping ||
            (sleepWakeGuardEnabled && powerGuard.isGracePeriodActive)
        self.lastVpnIface = snapshot.iface
        self.lastGateway = snapshot.gateway
        self.isVpnActive = snapshot.isVpn
        self.pingLatencyMs = snapshot.pingLatencyMs
        self.isDeadTunnel = snapshot.deadTunnelDetected
        self.isGracePeriodActive = effectiveGrace

        // Keep the power assertion aligned with the user setting even while
        // the network is in grace or the protection is disabled.
        powerGuard.updateSleepAssertion(
            shouldHold: preventSleep && isEnabled,
            reason: "Gestapo VPN Protection Active"
        )

        guard isEnabled else {
            protectionStatus = .disabled
            previousHealthy = true
            return
        }

        if effectiveGrace {
            protectionStatus = .grace
            return
        }

        // Во время Grace Period сетевые сбои игнорируются для исключения ложных тревог
        if effectiveGrace {
            return
        }

        // Определение актуального статуса защищённости
        let currentlyHealthy: Bool
        let failureReason: String

        if snapshot.deadTunnelDetected {
            currentlyHealthy = false
            failureReason = "Завис VPN туннель (нет ответа на пинг)"
        } else if splitTunnelCheck && !snapshot.targetDomainsOk {
            currentlyHealthy = false
            failureReason = "Утечка трафика целевых AI-доменов в незащищенный интерфейс"
        } else if !splitTunnelCheck && !snapshot.isVpn {
            currentlyHealthy = false
            failureReason = "VPN отключен! Обнаружен интерфейс: \(snapshot.iface.isEmpty ? "нет" : snapshot.iface)"
        } else {
            currentlyHealthy = true
            failureReason = ""
        }

        if currentlyHealthy {
            protectionStatus = .protected
        } else if snapshot.deadTunnelDetected {
            protectionStatus = .deadTunnel
        } else if splitTunnelCheck && !snapshot.targetDomainsOk {
            protectionStatus = .splitTunnelLeak
        } else {
            protectionStatus = .vpnInactive
        }

        let wasHealthy = previousHealthy

        if wasHealthy && !currentlyHealthy {
            // Edge Trigger: Первое падение — полномасштабная авария
            previousHealthy = false
            executeGestapoHardKill(reason: failureReason, detectedIface: snapshot.iface)
        } else if !wasHealthy && !currentlyHealthy {
            // Level Trigger: Повторные тики пока сеть не восстановлена (Continuous Kill)
            if continuousKill {
                let activeTargets = targets
                queue.async {
                    let killed = GestapoAppHunter.killAllActiveTargets(targets: activeTargets)
                    if !killed.isEmpty {
                        Self.logSecurityEvent("⚡ [CONTINUOUS_KILL] Подавлены повторно запущенные процессы: \(killed.joined(separator: ", "))")
                    }
                }
            }
        } else if !wasHealthy && currentlyHealthy {
            // Восстановление сети
            previousHealthy = true
            if AppState.shared.view == .securityPanic {
                AppState.shared.resetSecurityAlert()
                let recoveredIface = snapshot.iface
                queue.async {
                    Self.logSecurityEvent("🟢 [WATCHDOG] VPN туннель восстановлен: \(recoveredIface)")
                }
            }
        }
    }

    /// Совместимость с модульными тестами и прямыми вызовами проверки VPN
    func handleNetworkTransition(isVpn: Bool, iface: String) {
        let snapshot = NetworkSnapshot(
            isVpn: isVpn,
            iface: iface,
            pingOk: true,
            pingLatencyMs: 0.0,
            deadTunnelDetected: false,
            targetDomainsOk: true
        )
        handleNetworkSnapshot(snapshot, isGrace: false)
    }

    private func checkNetwork() {
        guard !isChecking else { return }
        guard isEnabled else {
            protectionStatus = .disabled
            isGracePeriodActive = false
            powerGuard.updateSleepAssertion(shouldHold: false)
            return
        }
        isChecking = true

        let isGrace = sleepWakeGuardEnabled && powerGuard.isGracePeriodActive
        self.isGracePeriodActive = isGrace

        if powerGuard.isSleeping {
            isChecking = false
            return
        }

        let targetDomains = splitTunnelCheck ? targets.map(\.domain).filter { !$0.isEmpty } : []
        let pingEnabled = pingCheckEnabled

        Task { [weak self] in
            guard let self else { return }
            let snapshot = await self.networkWorker.checkStatus(
                targetDomains: targetDomains,
                enablePing: pingEnabled,
                isGracePeriod: isGrace
            )
            self.isChecking = false
            self.handleNetworkSnapshot(snapshot, isGrace: isGrace)
        }
    }

    // MARK: - Аварийная ликвидация (Hard Kill)

    func executeGestapoHardKill(reason: String, detectedIface: String = "") {
        // Активация режима тревоги в чёлке
        AppState.shared.triggerSecurityPanic(
            message: "VPN отключен! AI-агенты принудительно ликвидированы."
        )

        // Звуковое оповещение только на edge-переходе
        if alarmSoundEnabled {
            NSSound.beep()
        }

        // Системный баннер macOS
        if macNotificationsEnabled {
            GestapoAppHunter.sendMacNotification(
                title: "🚨 ГЕСТАПО: ТРЕВОГА!",
                message: reason
            )
        }

        // Вынос логирования и ликвидации на фоновую очередь
        let activeTargets = targets
        queue.async {
            Self.logSecurityEvent("🚨 [KILL-SWITCH] \(reason). Немедленная ликвидация агентов.")
            let killed = GestapoAppHunter.killAllActiveTargets(targets: activeTargets)
            if !killed.isEmpty {
                Self.logSecurityEvent("💀 [KILL-SWITCH] Ликвидированы: \(killed.joined(separator: ", "))")
            }
        }
    }

    func executeGestapoHardKill(detectedIface: String) {
        executeGestapoHardKill(
            reason: "VPN упал! Обнаружен интерфейс: \(detectedIface)",
            detectedIface: detectedIface
        )
    }

    // MARK: - On-demand проверка внешнего IP

    func probeExternalIpOnDemand(domain: String = "claude.ai") {
        guard !isCheckingIp else { return }
        isCheckingIp = true
        Task { [weak self] in
            guard let self else { return }
            let result = await self.networkWorker.probeExternalIp(targetDomain: domain)
            self.externalIp = result.ip
            self.isCheckingIp = false
            Self.logSecurityEvent("🛰 [IP_PROBE] Внешний IP: \(result.ip.isEmpty ? "не определен" : result.ip) (интерфейс: \(result.iface), vpn: \(result.isVpn))")
        }
    }

    // MARK: - Статические утилиты (Nonisolated для Swift 6 и обратной совместимости)

    nonisolated static func isVpnInterface(_ iface: String) -> Bool {
        iface.hasPrefix("utun")
    }

    nonisolated static func parseInterface(fromRouteOutput output: String) -> String {
        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("interface:") {
                return trimmed.replacingOccurrences(of: "interface:", with: "").trimmingCharacters(in: .whitespaces)
            }
        }
        return ""
    }

    nonisolated static func parseGateway(fromRouteOutput output: String) -> String {
        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("gateway:") else { continue }
            return trimmed.replacingOccurrences(of: "gateway:", with: "")
                .trimmingCharacters(in: .whitespaces)
        }
        return ""
    }

    nonisolated static func parseRouteInfo(fromRouteOutput output: String) -> (iface: String, gateway: String) {
        (parseInterface(fromRouteOutput: output), parseGateway(fromRouteOutput: output))
    }

    nonisolated static func getRouteInterface(
        dest: String = "1.1.1.1",
        routeExecutableURL: URL = URL(fileURLWithPath: "/sbin/route"),
        timeoutSeconds: Double = 0.8
    ) -> String {
        let task = Process()
        task.executableURL = routeExecutableURL
        task.arguments = ["-n", "get", dest]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        let timeoutItem = DispatchWorkItem { [weak task] in
            if let task, task.isRunning {
                task.terminate()
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds, execute: timeoutItem)
        defer { timeoutItem.cancel() }

        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            if let output = String(data: data, encoding: .utf8) {
                return parseInterface(fromRouteOutput: output)
            }
        } catch {}
        return ""
    }

    nonisolated static func checkVpnTunnel(
        routeExecutableURL: URL = URL(fileURLWithPath: "/sbin/route")
    ) -> (isVpn: Bool, iface: String) {
        var iface = getRouteInterface(dest: "1.1.1.1", routeExecutableURL: routeExecutableURL)
        if !isVpnInterface(iface) {
            let defIface = getRouteInterface(dest: "default", routeExecutableURL: routeExecutableURL)
            if isVpnInterface(defIface) {
                iface = defIface
            }
        }
        return (isVpnInterface(iface), iface)
    }

    nonisolated static func killTargetProcesses(targets: [String]) {
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

    nonisolated static func logSecurityEvent(_ message: String, logDirURL: URL? = nil) {
        let logDir = logDirURL ?? URL(fileURLWithPath: (NSHomeDirectory() as NSString).appendingPathComponent("Library/Logs/Gestapo"))
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
