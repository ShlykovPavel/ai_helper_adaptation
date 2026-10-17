import Foundation

// MARK: - Antigravity plan usage

struct AntigravityPlanUsage: Codable, Sendable {
    var geminiFiveHour: PlanWindow?
    var geminiWeekly: PlanWindow?
    var thirdPartyFiveHour: PlanWindow?
    var thirdPartyWeekly: PlanWindow?
    var updatedAt: Date

    /// Highest effective percentage of geminiFiveHour and geminiWeekly.
    var dominantGeminiPct: Double? {
        let p1 = geminiFiveHour.map { ClaudePlanGauge.effectivePct($0) }
        let p2 = geminiWeekly.map { ClaudePlanGauge.effectivePct($0) }
        switch (p1, p2) {
        case (.none, .none): return nil
        case (let x?, .none): return x
        case (.none, let y?): return y
        case (let x?, let y?): return max(x, y)
        }
    }
}

// MARK: - Antigravity Plan Gauge

enum AntigravityPlanGauge {
    nonisolated(unsafe) static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        return f
    }()

    nonisolated(unsafe) private static let isoFormatterFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func parseDate(_ str: String) -> Date? {
        isoFormatter.date(from: str) ?? isoFormatterFractional.date(from: str)
    }

    /// Parses LanguageServerService RetrieveUserQuotaSummary JSON response data.
    static func parse(data: Data) -> AntigravityPlanUsage? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let resp = (obj["response"] as? [String: Any]) ?? (obj["userQuotaSummary"] as? [String: Any]) ?? (obj["groups"] != nil ? obj : nil),
              let groups = resp["groups"] as? [[String: Any]] else { return nil }

        var g5h: PlanWindow? = nil
        var gWeek: PlanWindow? = nil
        var tp5h: PlanWindow? = nil
        var tpWeek: PlanWindow? = nil

        for group in groups {
            guard let buckets = group["buckets"] as? [[String: Any]] else { continue }
            for b in buckets {
                let id = b["bucketId"] as? String ?? ""
                let rem: Double
                if let v = b["remainingFraction"] as? Double { rem = v }
                else if let v = b["remainingFraction"] as? Int { rem = Double(v) }
                else { continue }

                guard let resetStr = b["resetTime"] as? String,
                      let resetDate = parseDate(resetStr) else { continue }

                let usedPct = min(100.0, max(0.0, (1.0 - rem) * 100.0))
                let window = PlanWindow(usedPct: usedPct, resetsAt: resetDate)
                switch id {
                case "gemini-5h": g5h = window
                case "gemini-weekly": gWeek = window
                case "3p-5h": tp5h = window
                case "3p-weekly": tpWeek = window
                default: break
                }
            }
        }

        guard g5h != nil || gWeek != nil || tp5h != nil || tpWeek != nil else { return nil }

        return AntigravityPlanUsage(
            geminiFiveHour: g5h,
            geminiWeekly: gWeek,
            thirdPartyFiveHour: tp5h,
            thirdPartyWeekly: tpWeek,
            updatedAt: Date()
        )
    }

    static func pillLabel(_ usage: AntigravityPlanUsage?) -> String {
        guard let usage, let pct = usage.dominantGeminiPct else { return "Gemini —" }
        return "Gemini \(Int(pct.rounded()))%"
    }

    static func color(_ usage: AntigravityPlanUsage?) -> String {
        ClaudePlanGauge.color(for: usage?.dominantGeminiPct)
    }

    /// Discovers language_server process and queries RetrieveUserQuotaSummary.
    static func fetch() async -> AntigravityPlanUsage? {
        await Task.detached { queryLocalServer() }.value
    }

    private static func queryLocalServer() -> AntigravityPlanUsage? {
        let (pid, token) = findLanguageServerProcess()
        guard let pid, let token else { return nil }
        let ports = findListeningPorts(pid: pid)
        guard !ports.isEmpty else { return nil }

        for port in ports {
            if let usage = queryPort(scheme: "https", port: port, token: token) {
                return usage
            }
            if let usage = queryPort(scheme: "http", port: port, token: token) {
                return usage
            }
        }
        return nil
    }

    private static func queryPort(scheme: String, port: Int, token: String) -> AntigravityPlanUsage? {
        guard let url = URL(string: "\(scheme)://127.0.0.1:\(port)/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 3.0)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: "x-codeium-csrf-token")
        request.httpBody = Data("{}".utf8)

        let session = URLSession(configuration: .ephemeral, delegate: InsecureLocalhostDelegate(), delegateQueue: nil)
        var resultData: Data? = nil
        let sema = DispatchSemaphore(value: 0)
        let task = session.dataTask(with: request) { data, response, error in
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                resultData = data
            } else if error == nil, let d = data, !d.isEmpty {
                resultData = d
            }
            sema.signal()
        }
        task.resume()
        _ = sema.wait(timeout: .now() + 3.5)
        session.invalidateAndCancel()
        guard let data = resultData else { return nil }
        return parse(data: data)
    }

    private static func findLanguageServerProcess() -> (Int?, String?) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-ax", "-o", "pid,command"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do { try task.run(); task.waitUntilExit() } catch { return (nil, nil) }
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        for line in output.components(separatedBy: "\n") {
            if line.contains("language_server") && line.contains("--csrf_token") {
                let parts = line.trimmingCharacters(in: .whitespaces).components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                guard let pid = Int(parts[0]) else { continue }
                if let tokenIdx = parts.firstIndex(of: "--csrf_token"), tokenIdx + 1 < parts.count {
                    return (pid, parts[tokenIdx + 1])
                }
                for part in parts {
                    if part.starts(with: "--csrf_token=") {
                        let token = String(part.dropFirst("--csrf_token=".count))
                        return (pid, token)
                    }
                }
            }
        }
        return (nil, nil)
    }

    private static func findListeningPorts(pid: Int) -> [Int] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        task.arguments = ["-a", "-iTCP", "-sTCP:LISTEN", "-n", "-P", "-p", "\(pid)"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do { try task.run(); task.waitUntilExit() } catch { return [] }
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        var ports: [Int] = []
        for line in output.components(separatedBy: "\n") {
            guard line.contains("LISTEN") else { continue }
            let components = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            for comp in components {
                if let colonIdx = comp.lastIndex(of: ":") {
                    let portStr = comp[comp.index(after: colonIdx)...]
                    if let port = Int(portStr), !ports.contains(port) {
                        ports.append(port)
                    }
                }
            }
        }
        return ports
    }
}

private final class InsecureLocalhostDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
