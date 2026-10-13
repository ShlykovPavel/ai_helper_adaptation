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
    /// Next-hop gateway for the selected route, when the system reports one.
    var gateway: String = ""
}

/// Подробный результат ручной проверки внешнего IP.
/// Храним маршрут до целевого AI-сервиса и маршрут до IP-сервиса отдельно,
/// чтобы UI мог объяснить, что именно было проверено.
struct ExternalIpProbeResult: Sendable, Equatable {
    let targetHost: String
    let targetIp: String
    let targetInterface: String
    let targetGateway: String
    let ipService: String
    let ipServiceIp: String
    let ipServiceInterface: String
    let ipServiceGateway: String
    let ip: String
    let errorMessage: String

    var isVpn: Bool { GestapoWatchdog.isVpnInterface(targetInterface) }
    var isSuccessful: Bool { !ip.isEmpty && errorMessage.isEmpty }

    // Compatibility with the Phase 1 tuple-shaped result.
    var iface: String { targetInterface }
}

/// GestapoNetworkWorker изолирует сетевые проверки, ICMP-пинг и DNS-резолвинг
/// в Swift Actor для обеспечения потокобезопасности без блокировки UI.
actor GestapoNetworkWorker {
    private struct RouteInfo: Sendable {
        let iface: String
        let gateway: String
    }
    private var dnsCache: [String: (ip: String, timestamp: TimeInterval)] = [:]
    private var consecutivePingFails: Int = 0
    private var lastPingOk: Bool = true
    private var lastPingLatencyMs: Double = 0.0
    private var lastPingTimestamp: TimeInterval = 0.0

    private let dnsCacheTTL: TimeInterval = 300.0
    private let pingInterval: TimeInterval
    private let routeTimeout: TimeInterval
    private let ipProbeServices: [String]

    var pingExecutableURL: URL = URL(fileURLWithPath: "/sbin/ping")
    var routeExecutableURL: URL = URL(fileURLWithPath: "/sbin/route")
    var curlExecutableURL: URL = URL(fileURLWithPath: "/usr/bin/curl")

    init(
        pingExecutableURL: URL = URL(fileURLWithPath: "/sbin/ping"),
        routeExecutableURL: URL = URL(fileURLWithPath: "/sbin/route"),
        curlExecutableURL: URL = URL(fileURLWithPath: "/usr/bin/curl"),
        pingInterval: TimeInterval = 5.0,
        routeTimeout: TimeInterval = 0.8,
        ipProbeServices: [String] = [
            "ifconfig.me",
            "icanhazip.com",
            "api.ipify.org",
            "checkip.amazonaws.com"
        ]
    ) {
        self.pingExecutableURL = pingExecutableURL
        self.routeExecutableURL = routeExecutableURL
        self.curlExecutableURL = curlExecutableURL
        self.pingInterval = pingInterval
        self.routeTimeout = routeTimeout
        self.ipProbeServices = ipProbeServices
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
    private func getRouteInfo(dest: String, timeoutSeconds: Double = 0.8) -> RouteInfo {
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
                let parsed = GestapoWatchdog.parseRouteInfo(fromRouteOutput: output)
                return RouteInfo(iface: parsed.iface, gateway: parsed.gateway)
            }
        } catch {}
        return RouteInfo(iface: "", gateway: "")
    }

    func getRouteInterface(dest: String, timeoutSeconds: Double = 0.8) -> String {
        getRouteInfo(dest: dest, timeoutSeconds: timeoutSeconds).iface
    }

    func getRouteGateway(dest: String, timeoutSeconds: Double = 0.8) -> String {
        getRouteInfo(dest: dest, timeoutSeconds: timeoutSeconds).gateway
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

    private func isValidIPv4(_ value: String) -> Bool {
        var address = in_addr()
        return value.withCString { inet_pton(AF_INET, $0, &address) == 1 }
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
        var selectedRoute = getRouteInfo(dest: "1.1.1.1", timeoutSeconds: routeTimeout)
        if !GestapoWatchdog.isVpnInterface(selectedRoute.iface) {
            let secondaryRoute = getRouteInfo(dest: "8.8.8.8", timeoutSeconds: routeTimeout)
            if GestapoWatchdog.isVpnInterface(secondaryRoute.iface) {
                selectedRoute = secondaryRoute
            } else {
                let defaultRoute = getRouteInfo(dest: "default", timeoutSeconds: routeTimeout)
                if GestapoWatchdog.isVpnInterface(defaultRoute.iface) {
                    selectedRoute = defaultRoute
                } else if selectedRoute.iface.isEmpty {
                    selectedRoute = defaultRoute.iface.isEmpty ? secondaryRoute : defaultRoute
                }
            }
        }
        let iface = selectedRoute.iface
        let isVpn = GestapoWatchdog.isVpnInterface(iface)
        let gateway = selectedRoute.gateway

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
            targetDomainsOk: targetDomainsOk,
            gateway: gateway
        )
    }

    /// Принудительный сброс счетчика ошибок пинга
    func resetPingFails() {
        consecutivePingFails = 0
        lastPingOk = true
    }

    /// On-demand опрос внешнего IP через сервис, чей маршрут совпадает
    /// с маршрутом до целевого AI-сервиса.
    func probeExternalIp(targetDomain: String = "claude.ai") async -> ExternalIpProbeResult {
        let targetIp = resolveDomain(targetDomain)
        guard !targetIp.isEmpty else {
            return ExternalIpProbeResult(
                targetHost: targetDomain, targetIp: "", targetInterface: "", targetGateway: "",
                ipService: "", ipServiceIp: "", ipServiceInterface: "", ipServiceGateway: "",
                ip: "", errorMessage: "Не удалось определить IP адреса \(targetDomain)"
            )
        }

        let targetRoute = getRouteInfo(dest: targetIp, timeoutSeconds: routeTimeout)
        guard !targetRoute.iface.isEmpty else {
            return ExternalIpProbeResult(
                targetHost: targetDomain, targetIp: targetIp, targetInterface: "", targetGateway: "",
                ipService: "", ipServiceIp: "", ipServiceInterface: "", ipServiceGateway: "",
                ip: "", errorMessage: "Не удалось определить маршрут до \(targetDomain)"
            )
        }

        var selectedService: (host: String, ip: String, route: RouteInfo)?
        for service in ipProbeServices {
            let serviceIp = resolveDomain(service)
            guard !serviceIp.isEmpty else { continue }
            let serviceRoute = getRouteInfo(dest: serviceIp, timeoutSeconds: routeTimeout)
            if serviceRoute.iface == targetRoute.iface {
                selectedService = (service, serviceIp, serviceRoute)
                break
            }
        }

        guard let service = selectedService else {
            return ExternalIpProbeResult(
                targetHost: targetDomain, targetIp: targetIp,
                targetInterface: targetRoute.iface, targetGateway: targetRoute.gateway,
                ipService: "", ipServiceIp: "", ipServiceInterface: "", ipServiceGateway: "",
                ip: "", errorMessage: "Не найден сервис проверки IP через \(targetRoute.iface)"
            )
        }

        // Запрос привязан к тому же интерфейсу, что и маршрут до AI-сервиса.
        let task = Process()
        task.executableURL = curlExecutableURL
        var args = ["-4", "-sS", "--fail", "--max-time", "4"]
        args.append(contentsOf: ["--resolve", "\(service.host):443:\(service.ip)"])
        args.append(contentsOf: ["--interface", targetRoute.iface])
        args.append("https://\(service.host)")
        task.arguments = args

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               isValidIPv4(output),
               task.terminationStatus == 0 {
                return ExternalIpProbeResult(
                    targetHost: targetDomain, targetIp: targetIp,
                    targetInterface: targetRoute.iface, targetGateway: targetRoute.gateway,
                    ipService: service.host, ipServiceIp: service.ip,
                    ipServiceInterface: service.route.iface, ipServiceGateway: service.route.gateway,
                    ip: output, errorMessage: ""
                )
            }
        } catch {}

        return ExternalIpProbeResult(
            targetHost: targetDomain, targetIp: targetIp,
            targetInterface: targetRoute.iface, targetGateway: targetRoute.gateway,
            ipService: service.host, ipServiceIp: service.ip,
            ipServiceInterface: service.route.iface, ipServiceGateway: service.route.gateway,
            ip: "", errorMessage: "Сервис \(service.host) не ответил через \(targetRoute.iface)"
        )
    }
}
