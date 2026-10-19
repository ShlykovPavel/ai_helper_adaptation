import Foundation

@main
@MainActor
enum CodexIntegrationTests {
    static var failures = 0
    static func check(_ label: String, _ condition: Bool) {
        print("  \(condition ? "✓" : "✗") \(label)")
        if !condition { failures += 1 }
    }

    static func main() async {
        let future = Date().addingTimeInterval(3600).timeIntervalSince1970
        let window: [String: Any] = ["usedPercent": 43, "windowDurationMins": 300, "resetsAt": future]
        let weekly: [String: Any] = ["usedPercent": 7, "windowDurationMins": 10080, "resetsAt": future]
        let result: [String: Any] = [
            "rateLimits": ["primary": ["usedPercent": 99, "windowDurationMins": 300, "resetsAt": future]],
            "rateLimitsByLimitId": ["codex": ["primary": window, "secondary": weekly, "planType": "team"]]
        ]
        let usage = CodexPlanGauge.parse(result: result)
        check("prefer Codex bucket over legacy snapshot", usage?.fiveHour?.usedPct == 43)
        check("weekly usage and plan come from same bucket", usage?.sevenDay?.usedPct == 7 && usage?.planType == "team")
        check("map-only rate limits load", CodexPlanGauge.parse(result: ["rateLimitsByLimitId": ["codex": ["primary": window]]]) != nil)
        check("missing duration is not invented as a week", CodexPlanGauge.parse(result: ["rateLimits": ["primary": ["usedPercent": 1, "resetsAt": future]]]) == nil)

        let sync: [String: Any] = ["questions": [["id": "database", "header": "Storage", "question": "Which database?", "options": [
            ["label": "SQLite", "description": "Local"], ["label": "Postgres", "description": "Server"]
        ]]]]
        let parsed = AskQuestion.parse(toolInput: sync)
        check("native Codex question parses", parsed?.questions.first?.options.count == 2)
        let answers = AskQuestion.buildAnswers(questions: parsed?.questions ?? [], selections: [["SQLite"]])
        check("answer uses Codex question id", answers["database"] as? String == "SQLite")
        let free = AskQuestion.parse(toolInput: ["questions": [["title": "What happened?"]]])
        check("async free-text question parses without fabricated choices", free?.questions.first?.question == "What happened?" && free?.questions.first?.options.isEmpty == true)
        let choices = AskQuestion.parse(toolInput: ["questions": [["title": "Choose", "options": ["One", "Two", "Three", "Four", "Five"]]]])
        check("async string options are preserved", choices?.questions.first?.options.count == 5)
        check("malformed options fall back to Codex", AskQuestion.parse(toolInput: ["questions": [["title": "Choose", "options": [42]]]]) == nil)
        check("empty questions fall back to Codex", AskQuestion.parse(toolInput: ["questions": []]) == nil)
        if ProcessInfo.processInfo.environment["COUCOU_LIVE_CODEX_TEST"] == "1" {
            check("installed desktop Codex is discoverable", CodexPlanGauge.codexExecutable() != nil)
            let live = await CodexPlanGauge.fetch()
            check("real desktop app-server returns both quota windows", live?.fiveHour != nil && live?.sevenDay != nil)
            if let live {
                print("Live Codex: 5h \(live.fiveHour?.usedPct ?? -1)%, week \(live.sevenDay?.usedPct ?? -1)%")
            }
        }
        if failures > 0 { exit(1) }
    }
}
