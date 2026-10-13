import Foundation
import Darwin

/// Снимок состояния сети, формируемый GestapoNetworkWorker
struct NetworkSnapshot: Sendable, Equatable {
    let isVpn: Bool
    let iface: String
    let pingOk: Bool
    let pingLatencyMs: Double
    let deadTunnelDetected: Bool
    let targetDomainsOk: Bool
}

/// GestapoNetworkWorker изолирует сетевые проверки, ICMP-пинг и DNS-резолвинг
/// в Swift Actor для обеспечения потокобезопасности без блокировки UI.
actor GestapoNetworkWorker {
    private var dnsCache: [String: (ip: String, timestamp: TimeInterval)] = [:]
    private var consecutivePingFails: Int = 0
    private var lastPingOk: Bool = true
    private var lastPingLatencyMs: Double = 0.0
    private var lastPingTimestamp: TimeInterval = 0.0

    private let dnsCacheTTL: TimeInterval = 300.0
    private let pingInterval: TimeInterval
    private let routeTimeout: TimeInterval

    var pingExecutableURL: URL = URL(fileURLWithPath: "/sbin/ping")
    var routeExecutableURL: URL = URL(fileURLWithPath: "/sbin/route")
    var curlExecutableURL: URL = URL(fileURLWithPath: "/usr/bin/curl")

    init(
        pingExecutableURL: URL = URL(fileURLWithPath: "/sbin/ping"),
        routeExecutableURL: URL = URL(fileURLWithPath: "/sbin/route"),
        curlExecutableURL: URL = URL(fileURLWithPath: "/usr/bin/curl"),
        pingInterval: TimeInterval = 5.0,
        routeTimeout: TimeInterval = 0.8
    ) {
        self.pingExecutableURL = pingExecutableURL
        self.routeExecutableURL = routeExecutableURL
        self.curlExecutableURL = curlExecutableURL
        self.pingInterval = pingInterval
        self.routeTimeout = routeTimeout
    }

    /// Резолвинг доменного имени в IPv4 с 300-секундным кэшем.
    /// Предотвращает обращение к DNS в /sbin/route, исключая зависания при отвале сети.
    func resolveDomain(_ hostOrIp: String) -> String {
        guard !hostOrIp.isEmpty else { return "" }

        // Если это уже числовой IPv4
        let parts = hostOrIp.split(separator: ".")
        if parts.count == 4 && parts.allSatisfy({ part in
            guard let n = Int(part) else { return false }
            return n >= 0 && n <= 255
        }) {
            return hostOrIp
        }

        let now = Date().timeIntervalSince1970
        if let cached = dnsCache[hostOrIp], (now - cached.timestamp) < dnsCacheTTL, !cached.ip.isEmpty {
            return cached.ip
        }

        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_STREAM

        var res: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(hostOrIp, nil, &hints, &res)
        defer {
            if let res = res {
                freeaddrinfo(res)
            }
        }

        if status == 0, let first = res {
            var ptr: UnsafeMutablePointer<addrinfo>? = first
            while let curr = ptr {
                if curr.pointee.ai_family == AF_INET, let addr = curr.pointee.ai_addr {
                    var ipBuffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                    let sockAddrIn = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
                    var sinAddr = sockAddrIn.sin_addr
                    if inet_ntop(AF_INET, &sinAddr, &ipBuffer, socklen_t(INET_ADDRSTRLEN)) != nil {
                        let ipStr = ipBuffer.withUnsafeBufferPointer { ptr in
                            guard let base = ptr.baseAddress else { return "" }
                            return String(cString: base)
                        }
                        if !ipStr.isEmpty {
                            dnsCache[hostOrIp] = (ipStr, now)
                            return ipStr
                        }
                    }
                }
                ptr = curr.pointee.ai_next
            }
        }

        if let cached = dnsCache[hostOrIp], !cached.ip.isEmpty {
            return cached.ip
        }
        return ""
    }

    /// Проверка маршрута через /sbin/route -n get <dest> с защитой от зависания по таймауту
    func getRouteInterface(dest: String, timeoutSeconds: Double = 0.8) -> String {
        let task = Process()
        task.executableURL = routeExecutableURL
        task.arguments = ["-n", "get", dest]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        let timeoutItem = DispatchWorkItem { [weak task] in
            if let task, task.isRunning {
                task.terminate()
                if task.isRunning {
                    kill(task.processIdentifier, SIGKILL)
                }
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds, execute: timeoutItem)
        defer { timeoutItem.cancel() }

        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            if let output = String(data: data, encoding: .utf8) {
                return GestapoWatchdog.parseInterface(fromRouteOutput: output)
            }
        } catch {}
        return ""
    }

    /// Отправка ICMP пакета с отдельным wall-clock таймаутом.
    private func executePing() -> (ok: Bool, latencyMs: Double) {
        let task = Process()
        task.executableURL = pingExecutableURL
        task.arguments = ["-c", "1", "-W", "1500", "1.1.1.1"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice

        let startTime = Date()
        do {
            try task.run()
            let deadline = Date().addingTimeInterval(2.0)
            while task.isRunning && Date() < deadline {
                usleep(50_000)
            }
            if task.isRunning {
                task.terminate()
                if task.isRunning {
                    kill(task.processIdentifier, SIGKILL)
                }
                task.waitUntilExit()
                return (false, 0.0)
            }
            let elapsed = Date().timeIntervalSince(startTime) * 1000.0
            let ok = (task.terminationStatus == 0)
            return (ok, ok ? elapsed : 0.0)
        } catch {
            return (false, 0.0)
        }
    }

    /// Комплексная проверка состояния сети:
    /// 1. Основной VPN-маршрут (1.1.1.1 / default)
    /// 2. Split Tunneling для целевых AI-доменов
    /// 3. Фоновый пинг (Dead Tunnel Detection) с порогом в 2 сбоя
    func checkStatus(
        targetDomains: [String] = [],
        enablePing: Bool = true,
        isGracePeriod: Bool = false
    ) -> NetworkSnapshot {
        // 1. Определение интерфейса глобального шлюза.
        // Для def1/раздельных конфигураций первый публичный адрес может
        // оказаться вне туннеля, поэтому проверяем ещё 8.8.8.8 и default.
        var iface = getRouteInterface(dest: "1.1.1.1", timeoutSeconds: routeTimeout)
        if !GestapoWatchdog.isVpnInterface(iface) {
            let secondaryIface = getRouteInterface(dest: "8.8.8.8", timeoutSeconds: routeTimeout)
            if GestapoWatchdog.isVpnInterface(secondaryIface) {
                iface = secondaryIface
            } else {
                let defIface = getRouteInterface(dest: "default", timeoutSeconds: routeTimeout)
                if GestapoWatchdog.isVpnInterface(defIface) {
                    iface = defIface
                } else if iface.isEmpty {
                    iface = defIface.isEmpty ? secondaryIface : defIface
                }
            }
        }
        let isVpn = GestapoWatchdog.isVpnInterface(iface)

        // 2. Проверка Split Tunneling доменов (если переданы)
        var targetDomainsOk = true
        if !targetDomains.isEmpty {
            for domain in targetDomains {
                let resolvedIp = resolveDomain(domain)
                guard !resolvedIp.isEmpty else {
                    targetDomainsOk = false
                    break
                }
                let domainIface = getRouteInterface(dest: resolvedIp, timeoutSeconds: routeTimeout)
                if !GestapoWatchdog.isVpnInterface(domainIface) {
                    targetDomainsOk = false
                    break
                }
            }
        }

        // 3. Пинг и детект зависшего туннеля (Dead Tunnel Detection)
        var pingOk = lastPingOk
        var pingLatencyMs = lastPingLatencyMs
        var deadTunnel = false

        if isGracePeriod {
            consecutivePingFails = 0
            pingOk = true
            deadTunnel = false
        } else if enablePing && isVpn {
            let now = Date().timeIntervalSince1970
            // Пинг выполняется не чаще, чем раз в pingInterval (5 секунд)
            if now - lastPingTimestamp >= pingInterval || lastPingTimestamp == 0 {
                let pingResult = executePing()
                lastPingTimestamp = now
                pingOk = pingResult.ok
                pingLatencyMs = pingResult.latencyMs
                lastPingOk = pingOk
                lastPingLatencyMs = pingLatencyMs

                if pingOk {
                    consecutivePingFails = 0
                } else {
                    consecutivePingFails += 1
                    if consecutivePingFails >= 2 {
                        deadTunnel = true
                    }
                }
            } else {
                if consecutivePingFails >= 2 {
                    deadTunnel = true
                }
            }
        } else {
            if !enablePing {
                consecutivePingFails = 0
                pingOk = true
                pingLatencyMs = 0.0
            }
        }

        return NetworkSnapshot(
            isVpn: isVpn,
            iface: iface,
            pingOk: pingOk,
            pingLatencyMs: pingLatencyMs,
            deadTunnelDetected: deadTunnel,
            targetDomainsOk: targetDomainsOk
        )
    }

    /// Принудительный сброс счетчика ошибок пинга
    func resetPingFails() {
        consecutivePingFails = 0
        lastPingOk = true
    }

    /// On-demand опрос внешнего IP через curl, привязанный к указанному интерфейсу
    func probeExternalIp(targetDomain: String = "claude.ai") async -> (ip: String, iface: String, isVpn: Bool) {
        // Шаг 1: определение маршрута для целевого домена
        let targetIp = resolveDomain(targetDomain)
        var iface = ""
        if !targetIp.isEmpty {
            iface = getRouteInterface(dest: targetIp, timeoutSeconds: routeTimeout)
        }
        if iface.isEmpty {
            iface = getRouteInterface(dest: "1.1.1.1", timeoutSeconds: routeTimeout)
        }
        if iface.isEmpty {
            iface = getRouteInterface(dest: "default", timeoutSeconds: routeTimeout)
        }

        // Шаг 2: запрос к api.ipify.org
        let task = Process()
        task.executableURL = curlExecutableURL
        var args = ["-s", "--max-time", "4"]
        if !iface.isEmpty {
            args.append(contentsOf: ["--interface", iface])
        }
        args.append("https://api.ipify.org")
        task.arguments = args

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !output.isEmpty {
                let isVpn = GestapoWatchdog.isVpnInterface(iface)
                return (ip: output, iface: iface, isVpn: isVpn)
            }
        } catch {}

        return (ip: "", iface: iface, isVpn: GestapoWatchdog.isVpnInterface(iface))
    }
}
