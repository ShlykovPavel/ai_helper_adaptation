import Foundation

@main
enum AntigravityPlanGaugeTests {
    static var failures = 0
    static func check(_ label: String, _ condition: Bool) {
        if condition { print("  ✓ \(label)") }
        else { print("  ✗ \(label)"); failures += 1 }
    }

    static func main() {
        print("AntigravityPlanGaugeTests")

        let rawJSON = """
        {
          "response": {
            "groups": [
              {
                "displayName": "Gemini Models",
                "buckets": [
                  {
                    "bucketId": "gemini-weekly",
                    "window": "weekly",
                    "remainingFraction": 0.94,
                    "resetTime": "2026-10-24T05:59:38Z"
                  },
                  {
                    "bucketId": "gemini-5h",
                    "window": "5h",
                    "remainingFraction": 0.82,
                    "resetTime": "2026-10-17T10:59:38Z"
                  }
                ]
              },
              {
                "displayName": "Claude and GPT models",
                "buckets": [
                  {
                    "bucketId": "3p-weekly",
                    "window": "weekly",
                    "remainingFraction": 0.0,
                    "resetTime": "2026-10-20T06:38:25Z"
                  },
                  {
                    "bucketId": "3p-5h",
                    "window": "5h",
                    "remainingFraction": 1.0,
                    "resetTime": "2026-10-17T11:24:12Z"
                  }
                ]
              }
            ]
          }
        }
        """

        let data = Data(rawJSON.utf8)
        let usage = AntigravityPlanGauge.parse(data: data)
        check("parse non-nil", usage != nil)
        // usedPct = (1.0 - remainingFraction) * 100
        check("gemini 5h usedPct is 18%", abs((usage?.geminiFiveHour?.usedPct ?? 0) - 18.0) < 0.1)
        check("gemini weekly usedPct is 6%", abs((usage?.geminiWeekly?.usedPct ?? 0) - 6.0) < 0.1)
        check("3p weekly usedPct is 100%", abs((usage?.thirdPartyWeekly?.usedPct ?? 0) - 100.0) < 0.1)

        // Pill label
        let label = AntigravityPlanGauge.pillLabel(usage)
        check("pillLabel starts with Gemini", label.starts(with: "Gemini"))

        if failures > 0 { exit(1) }
    }
}
