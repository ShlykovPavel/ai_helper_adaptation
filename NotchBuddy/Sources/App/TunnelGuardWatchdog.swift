import Foundation
import AppKit
import Darwin

enum TunnelGuardProtectionStatus: Equatable, Sendable {
    case disabled
    case grace
    case protected
    case vpnInactive
    case deadTunnel
    case splitTunnelLeak
}

/// Главный координатор системы безопасности TunnelGuard.
/// Объединяет TunnelGuardPowerGuard, TunnelGuardNetworkWorker и TunnelGuardAppHunter
/// и предоставляет реактивный интерфейс для SwiftUI и Dynamic Island (чёлки).
@MainActor
final class TunnelGuardWatchdog: ObservableObject {
    static let shared = TunnelGuardWatchdog()

    // MARK: - Подсистемы
    let powerGuard: TunnelGuardPowerGuard
    let networkWorker: TunnelGuardNetworkWorker

    // MARK: - Реактивные свойства состояния
    @Published private(set) var isVpnActive: Bool = true
    @Published private(set) var lastVpnIface: String = ""
    @Published private(set) var lastGateway: String = ""
    @Published private(set) var pingLatencyMs: Double = 0.0
    @Published private(set) var isDeadTunnel: Bool = false
    @Published private(set) var externalIp: String = ""
    @Published private(set) var ipProbeResult: ExternalIpProbeResult?
    @Published private(set) var isCheckingIp: Bool = false
    @Published private(set) var isGracePeriodActive: Bool = false
    /// Единый статус, которым пользуются watchdog и UI. Он учитывает не только
    /// наличие utun, но и dead-tunnel/split-tunnel аварии.
    @Published private(set) var protectionStatus: TunnelGuardProtectionStatus = .protected

    var canResetSecurityAlert: Bool { protectionStatus == .protected }

    // MARK: - Настройки и политики
    @Published var isEnabled: Bool = true {
        didSet {
            if !isEnabled {
                protectionStatus = .disabled
                isGracePeriodActive = false
                powerGuard.updateSleepAssertion(shouldHold: false)
            }
            syncRuntimeStateFile()
        }
    }
    @Published var continuousKill: Bool = true
    @Published var pingCheckEnabled: Bool = true
    @Published var splitTunnelCheck: Bool = false
    @Published var preventSleep: Bool = true {
        didSet {
            powerGuard.updateSleepAssertion(
                shouldHold: preventSleep && isEnabled,
                reason: "TunnelGuard VPN Protection Active"
            )
        }
    }
    @Published var sleepWakeGuardEnabled: Bool = true
    @Published var alarmSoundEnabled: Bool = true
    @Published var macNotificationsEnabled: Bool = true
    @Published var targets: [TunnelGuardTargetApp] = TunnelGuardAppHunter.defaultTargets {
        didSet {
            syncRuntimeStateFile()
        }
    }

    /// Директория для записи runtime state файла (по умолчанию nil -> defaultStateDirectoryURL).
    var stateDirectoryURL: URL? = nil

    /// Домены, по которым пользователь может вручную проверить маршрут и внешний IP.
    var ipProbeDomains: [String] {
        var domains = ["claude.ai"]
        for domain in targets.map(\.domain) where !domain.isEmpty && !domains.contains(domain) {
            domains.append(domain)
        }
        return domains
    }

    // MARK: - Внутреннее состояние
    private var previousHealthy: Bool = true
    private var monitorTimer: Timer?
    private let queue = DispatchQueue(label: "com.tunnelguard.coucou.watchdog", qos: .userInitiated)
    private var isChecking: Bool = false
    private let settingsDefaults: UserDefaults

    /// Точные имена исполняемых файлов (флаг -x исключает ложные срабатывания)
    nonisolated static let targetProcessExactNames = [
        "claude",
        "agy",
        "codex",
        "gemini",
        "cursor-agent"
    ]

    init(
        powerGuard: TunnelGuardPowerGuard = TunnelGuardPowerGuard(),
        networkWorker: TunnelGuardNetworkWorker = TunnelGuardNetworkWorker(),
        settingsDefaults: UserDefaults = .standard,
        stateDirectoryURL: URL? = nil
    ) {
        self.powerGuard = powerGuard
        self.networkWorker = networkWorker
        self.settingsDefaults = settingsDefaults
        self.stateDirectoryURL = stateDirectoryURL
        loadPersistedSettings()
    }

    func start() {
        // AppDelegate starts the singleton before SettingsView is created. Load
        // AppStorage-backed preferences here so the first network check uses
        // the user's persisted policy and target selection.
        loadPersistedSettings()
        syncRuntimeStateFile()
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

    private func loadPersistedSettings() {
        let defaults = settingsDefaults
        func bool(forKey key: String, default defaultValue: Bool) -> Bool {
            guard defaults.object(forKey: key) != nil else { return defaultValue }
            return defaults.bool(forKey: key)
        }

        isEnabled = bool(forKey: "tunnelGuard.enabled", default: true)
        continuousKill = bool(forKey: "tunnelGuard.continuousKill", default: true)
        pingCheckEnabled = bool(forKey: "tunnelGuard.pingCheckEnabled", default: true)
        splitTunnelCheck = bool(forKey: "tunnelGuard.splitTunnelCheck", default: false)
        preventSleep = bool(forKey: "tunnelGuard.preventSleep", default: true)
        sleepWakeGuardEnabled = bool(forKey: "tunnelGuard.sleepWakeGuardEnabled", default: true)
        alarmSoundEnabled = bool(forKey: "tunnelGuard.alarmSoundEnabled", default: true)
        macNotificationsEnabled = bool(forKey: "tunnelGuard.macNotificationsEnabled", default: true)

        targets = TunnelGuardAppHunter.defaultTargets.filter { target in
            bool(forKey: "tunnelGuard.target.\(target.id)", default: true)
        }

        if !isEnabled {
            protectionStatus = .disabled
            isGracePeriodActive = false
            powerGuard.updateSleepAssertion(shouldHold: false)
        } else {
            powerGuard.updateSleepAssertion(
                shouldHold: preventSleep,
                reason: "TunnelGuard VPN Protection Active"
            )
        }

        syncRuntimeStateFile()
    }

    func stop() {
        monitorTimer?.invalidate()
        monitorTimer = nil
        powerGuard.releaseOnTerminate()
        cleanupRuntimeStateFile()
    }

    func applicationWillTerminate() {
        cleanupRuntimeStateFile()
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
            reason: "TunnelGuard VPN Protection Active"
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
            executeTunnelGuardHardKill(reason: failureReason, detectedIface: snapshot.iface)
        } else if !wasHealthy && !currentlyHealthy {
            // Level Trigger: Повторные тики пока сеть не восстановлена (Continuous Kill)
            if continuousKill {
                let activeTargets = targets
                queue.async {
                    let killed = TunnelGuardAppHunter.killAllActiveTargets(targets: activeTargets)
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

    func executeTunnelGuardHardKill(reason: String, detectedIface: String = "") {
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
            TunnelGuardAppHunter.sendMacNotification(
                title: "🚨 TUNNELGUARD: ТРЕВОГА!",
                message: reason
            )
        }

        // Вынос логирования и ликвидации на фоновую очередь
        let activeTargets = targets
        queue.async {
            Self.logSecurityEvent("🚨 [KILL-SWITCH] \(reason). Немедленная ликвидация агентов.")
            let killed = TunnelGuardAppHunter.killAllActiveTargets(targets: activeTargets)
            if !killed.isEmpty {
                Self.logSecurityEvent("💀 [KILL-SWITCH] Ликвидированы: \(killed.joined(separator: ", "))")
            }
        }
    }

    func executeTunnelGuardHardKill(detectedIface: String) {
        executeTunnelGuardHardKill(
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
            self.ipProbeResult = result
            self.externalIp = result.ip
            self.isCheckingIp = false
            Self.logSecurityEvent("🛰 [IP_PROBE] Внешний IP: \(result.ip.isEmpty ? "не определен" : result.ip) (интерфейс: \(result.iface), vpn: \(result.isVpn))")
        }
    }

    /// Сбрасывает устаревший результат IP-проверки при смене целевого домена.
    func clearIpProbeResult() {
        ipProbeResult = nil
        externalIp = ""
    }

    // MARK: - Статические утилиты (Nonisolated для Swift 6 и обратной совместимости)

    nonisolated static func isVpnInterface(_ iface: String) -> Bool {
        let prefixes = ["utun", "tun", "tap", "ppp", "cscotun", "fctun", "ipsec"]
        return prefixes.contains { iface.hasPrefix($0) }
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
        let logDir = logDirURL ?? URL(fileURLWithPath: (NSHomeDirectory() as NSString).appendingPathComponent("Library/Logs/TunnelGuard"))
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
        let line = "\(timestamp) [TUNNELGUARD_WATCHDOG] \(message)\n"

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

    // MARK: - Runtime State Synchronization

    nonisolated static var defaultStateDirectoryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotchBuddy", isDirectory: true)
    }

    nonisolated static var defaultStateFileURL: URL {
        defaultStateDirectoryURL.appendingPathComponent("tunnelguard-state.json")
    }

    nonisolated static func stateFileURL(for directoryURL: URL?) -> URL {
        let dir = directoryURL ?? defaultStateDirectoryURL
        if dir.pathExtension == "json" {
            return dir
        }
        return dir.appendingPathComponent("tunnelguard-state.json")
    }

    func syncRuntimeStateFile(stateDirURL: URL? = nil) {
        let targetDir = stateDirURL ?? stateDirectoryURL
        let payload = buildRuntimeStatePayload(running: true)
        writeRuntimeStatePayload(payload, stateDirURL: targetDir)
    }

    func cleanupRuntimeStateFile(stateDirURL: URL? = nil) {
        let targetDir = stateDirURL ?? stateDirectoryURL
        let payload = buildRuntimeStatePayload(running: false)
        writeRuntimeStatePayload(payload, stateDirURL: targetDir)
    }

    private func buildRuntimeStatePayload(running: Bool) -> [String: Any] {
        let activeCliTargets = targets.filter { $0.type == .cli }.map(\.binaryOrBundleId)
        var domains: [String: String] = [:]
        for target in targets where target.type == .cli && !target.domain.isEmpty {
            domains[target.binaryOrBundleId] = target.domain
        }
        if let agyDomain = domains["agy"] {
            domains["antigravity"] = agyDomain
        }
        if let cursorDomain = domains["cursor-agent"] {
            domains["cursor"] = cursorDomain
        }

        return [
            "running": running,
            "enabled": running ? isEnabled : false,
            "pid": Int(ProcessInfo.processInfo.processIdentifier),
            "protected_targets": activeCliTargets,
            "target_domains": domains,
            "updated_at": Date().timeIntervalSince1970
        ]
    }

    private func writeRuntimeStatePayload(_ payload: [String: Any], stateDirURL: URL?) {
        let fileURL = Self.stateFileURL(for: stateDirURL)
        let targetDir = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: fileURL, options: .atomic)
        } catch {
            Self.logSecurityEvent("⚠️ Не удалось записать tunnelguard-state.json: \(error.localizedDescription)")
        }
    }
}
