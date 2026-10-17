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

        // Multiple PID parsing
        let samplePs = """
          101 /Applications/Safari.app/Contents/MacOS/Safari
          1234 /Users/test/.antigravity/bin/language_server --csrf_token secret123 --port 5001
          5678 /Users/test/.antigravity/bin/language_server --other_flag --csrf_token=secret456
          9999 /usr/bin/python3 other_script.py
        """
        let candidates = AntigravityPlanGauge.parseProcesses(samplePs)
        check("found 2 language_server candidates", candidates.count == 2)
        check("candidate 1 pid is 1234", candidates.first?.pid == 1234)
        check("candidate 1 token is secret123", candidates.first?.token == "secret123")
        check("candidate 2 pid is 5678", candidates.last?.pid == 5678)
        check("candidate 2 token is secret456", candidates.last?.token == "secret456")

        // Port parsing
        let sampleLsof = """
        COMMAND     PID USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
        language_ 1234 test    7u  IPv4 0x1234567890abcdef      0t0  TCP 127.0.0.1:49200 (LISTEN)
        language_ 1234 test    8u  IPv4 0x1234567890abcdef      0t0  TCP *:49201 (LISTEN)
        """
        let ports = AntigravityPlanGauge.parseListeningPorts(sampleLsof)
        check("found listening ports", ports.contains(49200) && ports.contains(49201))

        // InsecureLocalhostDelegate security check
        final class DummySender: NSObject, URLAuthenticationChallengeSender {
            func cancel(_ challenge: URLAuthenticationChallenge) {}
            func continueWithoutCredential(for challenge: URLAuthenticationChallenge) {}
            func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) {}
            func performDefaultHandling(for challenge: URLAuthenticationChallenge) {}
            func rejectProtectionSpaceAndContinue(with challenge: URLAuthenticationChallenge) {}
        }
        let delegate = InsecureLocalhostDelegate()
        let evilSpace = URLProtectionSpace(host: "evil.com", port: 443, protocol: "https", realm: nil, authenticationMethod: NSURLAuthenticationMethodServerTrust)
        let evilChallenge = URLAuthenticationChallenge(protectionSpace: evilSpace, proposedCredential: nil, previousFailureCount: 0, failureResponse: nil, error: nil, sender: DummySender())
        var evilDisp: URLSession.AuthChallengeDisposition?
        delegate.urlSession(URLSession.shared, didReceive: evilChallenge) { disp, _ in evilDisp = disp }
        check("InsecureLocalhostDelegate rejects evil.com", evilDisp == .performDefaultHandling)

        let localSpace = URLProtectionSpace(host: "127.0.0.1", port: 443, protocol: "https", realm: nil, authenticationMethod: "customAuth")
        let localChallenge = URLAuthenticationChallenge(protectionSpace: localSpace, proposedCredential: nil, previousFailureCount: 0, failureResponse: nil, error: nil, sender: DummySender())
        var localDisp: URLSession.AuthChallengeDisposition?
        delegate.urlSession(URLSession.shared, didReceive: localChallenge) { disp, _ in localDisp = disp }
        check("InsecureLocalhostDelegate handles 127.0.0.1 safely", localDisp == .performDefaultHandling)

        if failures > 0 { exit(1) }
    }
}
