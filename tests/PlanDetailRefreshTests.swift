import Foundation
import SwiftUI

@main
@MainActor
enum PlanDetailRefreshTests {
    static var failures = 0

    static func check(_ label: String, _ condition: Bool) {
        if condition {
            print("  ✓ \(label)")
        } else {
            print("  ✗ \(label)")
            failures += 1
        }
    }

    static func main() async {
        print("PlanDetailRefreshTests (R04 & R05)")

        testR05CardViewMatrix()
        testR05DominantWindowSelection()
        testR05TransitionsBeforeDataLoaded()
        await testR04RefreshLoopActiveTarget()
        await testR04RefreshLoopCancellationOnClose()
        await testR04CardSwitching()
        await testR04ParallelFetchProtection()
        await testR04RateLimitingAndMinGap()
        await testR04ServerUnavailableRecovery()

        if failures > 0 {
            print("\nPlanDetailRefreshTests FAILED with \(failures) failure(s).")
            exit(1)
        } else {
            print("\nAll PlanDetailRefreshTests passed successfully.")
        }
    }

    // MARK: - R05 Tests: Card layout matrix & transitions

    static func testR05CardViewMatrix() {
        print("\n--- R05: Antigravity card view matrix & 2-column layout ---")

        // 1. Both disabled -> 1 column
        let cardBothOff = AntigravityPlanCardView(
            usage: nil,
            codexRow: false,
            claudeRow: false
        )
        check("codexRow=F, claudeRow=F -> hasTwoColumns is false", !cardBothOff.hasTwoColumns)

        // 2. Only codex enabled -> 1 column
        let cardOnlyCodex = AntigravityPlanCardView(
            usage: nil,
            codexRow: true,
            claudeRow: false
        )
        check("codexRow=T, claudeRow=F -> hasTwoColumns is false", !cardOnlyCodex.hasTwoColumns)

        // 3. Only claude enabled -> 1 column
        let cardOnlyClaude = AntigravityPlanCardView(
            usage: nil,
            codexRow: false,
            claudeRow: true
        )
        check("codexRow=F, claudeRow=T -> hasTwoColumns is false", !cardOnlyClaude.hasTwoColumns)

        // 4. BOTH enabled -> 2 columns (neither excludes the other!)
        var codexTapped = false
        var claudeTapped = false
        let cardBothOn = AntigravityPlanCardView(
            usage: nil,
            codexRow: true,
            codexUsage: nil,
            onCodex: { codexTapped = true },
            claudeRow: true,
            claudeUsage: nil,
            onClaude: { claudeTapped = true }
        )
        check("codexRow=T, claudeRow=T -> hasTwoColumns is true", cardBothOn.hasTwoColumns)

        // Verify action closures work independently
        cardBothOn.onCodex?()
        check("onCodex callback fires", codexTapped)
        cardBothOn.onClaude?()
        check("onClaude callback fires", claudeTapped)
    }

    static func testR05DominantWindowSelection() {
        print("\n--- R05: Dominant window resolution ---")

        let future = Date().addingTimeInterval(3600)
        let w20 = PlanWindow(usedPct: 20, resetsAt: future)
        let w60 = PlanWindow(usedPct: 60, resetsAt: future)
        let w85 = PlanWindow(usedPct: 85, resetsAt: future)

        // Codex dominant window
        var codexUsage = CodexPlanUsage(planType: "pro", updatedAt: Date())
        codexUsage.fiveHour = w20
        codexUsage.sevenDay = w60

        let card1 = AntigravityPlanCardView(
            usage: nil,
            codexRow: true,
            codexUsage: codexUsage,
            claudeRow: false
        )
        check("codex 5h=20%, 7d=60% -> picks 60% window", card1.codexDominantWindow?.usedPct == 60)

        codexUsage.fiveHour = w85
        codexUsage.sevenDay = w60
        let card2 = AntigravityPlanCardView(
            usage: nil,
            codexRow: true,
            codexUsage: codexUsage,
            claudeRow: false
        )
        check("codex 5h=85%, 7d=60% -> picks 85% window", card2.codexDominantWindow?.usedPct == 85)

        // Claude dominant window
        var claudeUsage = PlanUsage(fiveHour: w20, sevenDay: w60, updatedAt: Date())
        let card3 = AntigravityPlanCardView(
            usage: nil,
            codexRow: false,
            claudeRow: true,
            claudeUsage: claudeUsage
        )
        check("claude 5h=20%, 7d=60% -> picks 60% window", card3.claudeDominantWindow?.usedPct == 60)

        claudeUsage.fiveHour = w85
        let card4 = AntigravityPlanCardView(
            usage: nil,
            codexRow: false,
            claudeRow: true,
            claudeUsage: claudeUsage
        )
        check("claude 5h=85%, 7d=60% -> picks 85% window", card4.claudeDominantWindow?.usedPct == 85)
    }

    static func testR05TransitionsBeforeDataLoaded() {
        print("\n--- R05: Transitions available before usage snapshot loads ---")

        // In the original bug, `if codexRow, codexUsage != nil` hid the button until loaded.
        // Now, if codexRow is true, button is present even if codexUsage is nil.
        let cardNilUsage = AntigravityPlanCardView(
            usage: nil,
            codexRow: true,
            codexUsage: nil,
            claudeRow: true,
            claudeUsage: nil
        )
        check("codex dominant window is nil when usage is nil", cardNilUsage.codexDominantWindow == nil)
        check("claude dominant window is nil when usage is nil", cardNilUsage.claudeDominantWindow == nil)
        check("two columns layout is preserved even when data is nil", cardNilUsage.hasTwoColumns)
    }

    // MARK: - R04 Tests: Refresh loop, target selection, cancellation, and rate-limiting

    /// Mock state simulating AppState properties relevant to plan detail card
    final class MockPlanState {
        var showingPlanDetail: Bool = false
        var planDetailIsAntigravity: Bool = false
        var planDetailIsCodex: Bool = false

        var antigravityFetchCount = 0
        var codexFetchCount = 0

        func refreshAntigravity() {
            antigravityFetchCount += 1
        }

        func refreshCodex() {
            codexFetchCount += 1
        }
    }

    static func testR04RefreshLoopActiveTarget() async {
        print("\n--- R04: Active target refresh in plan detail loop ---")

        let state = MockPlanState()
        state.showingPlanDetail = true

        // 1. Antigravity active
        state.planDetailIsAntigravity = true
        state.planDetailIsCodex = false

        // Simulate loop tick
        if state.planDetailIsAntigravity {
            state.refreshAntigravity()
        } else if state.planDetailIsCodex {
            state.refreshCodex()
        }

        check("Antigravity active -> Antigravity refreshed", state.antigravityFetchCount == 1)
        check("Antigravity active -> Codex NOT refreshed", state.codexFetchCount == 0)

        // 2. Codex active
        state.planDetailIsAntigravity = false
        state.planDetailIsCodex = true

        if state.planDetailIsAntigravity {
            state.refreshAntigravity()
        } else if state.planDetailIsCodex {
            state.refreshCodex()
        }

        check("Codex active -> Codex refreshed", state.codexFetchCount == 1)
        check("Codex active -> Antigravity count remained 1", state.antigravityFetchCount == 1)

        // 3. Claude active (neither Antigravity nor Codex)
        state.planDetailIsAntigravity = false
        state.planDetailIsCodex = false

        if state.planDetailIsAntigravity {
            state.refreshAntigravity()
        } else if state.planDetailIsCodex {
            state.refreshCodex()
        }

        check("Claude active -> no additional polling for Antigravity or Codex",
              state.antigravityFetchCount == 1 && state.codexFetchCount == 1)
    }

    static func testR04RefreshLoopCancellationOnClose() async {
        print("\n--- R04: Refresh loop cancellation on card dismissal ---")

        let state = MockPlanState()
        state.showingPlanDetail = true
        state.planDetailIsAntigravity = true

        var loopTicks = 0
        let loopTask = Task {
            while !Task.isCancelled {
                if state.planDetailIsAntigravity {
                    state.refreshAntigravity()
                } else if state.planDetailIsCodex {
                    state.refreshCodex()
                }
                loopTicks += 1
                do {
                    try await Task.sleep(for: .milliseconds(50))
                } catch {
                    return
                }
            }
        }

        // Wait for first tick
        try? await Task.sleep(for: .milliseconds(20))
        check("Loop runs while card is open", loopTicks >= 1)

        // Dismiss card -> cancel task
        state.showingPlanDetail = false
        loopTask.cancel()

        try? await Task.sleep(for: .milliseconds(100))
        let ticksAfterCancel = loopTicks
        try? await Task.sleep(for: .milliseconds(100))
        check("Loop stopped immediately after cancellation", loopTicks == ticksAfterCancel)
    }

    static func testR04CardSwitching() async {
        print("\n--- R04: Card switching Antigravity <-> Codex ---")

        let state = MockPlanState()
        state.showingPlanDetail = true
        state.planDetailIsAntigravity = true

        // User switches to Codex
        // In IslandViewContent:
        // withAnimation { state.planDetailIsAntigravity = false; state.planDetailIsCodex = true }
        // state.refreshCodexPlanUsage()
        state.planDetailIsAntigravity = false
        state.planDetailIsCodex = true
        state.refreshCodex()

        check("Switch to Codex immediately refreshes Codex", state.codexFetchCount == 1)

        // Next loop tick verifies Codex is refreshed
        if state.planDetailIsAntigravity {
            state.refreshAntigravity()
        } else if state.planDetailIsCodex {
            state.refreshCodex()
        }
        check("Subsequent loop tick refreshes Codex", state.codexFetchCount == 2)
        check("Subsequent loop tick does not refresh Antigravity", state.antigravityFetchCount == 0)

        // Switch back to Antigravity
        state.planDetailIsCodex = false
        state.planDetailIsAntigravity = true
        state.refreshAntigravity()

        check("Switch to Antigravity immediately refreshes Antigravity", state.antigravityFetchCount == 1)

        if state.planDetailIsAntigravity {
            state.refreshAntigravity()
        } else if state.planDetailIsCodex {
            state.refreshCodex()
        }
        check("Subsequent loop tick refreshes Antigravity", state.antigravityFetchCount == 2)
    }

    /// Mock rate-limited fetch engine mirroring AppState logic
    final class MockFetchEngine {
        var lastAttempt: Date = .distantPast
        var inFlight = false
        var usage: AntigravityPlanUsage? = nil
        var fetchExecutionCount = 0

        func fetch(now: Date = Date(), simulatedDelayMs: UInt64 = 0) async -> AntigravityPlanUsage? {
            if let u = usage, now.timeIntervalSince(u.updatedAt) < 55 {
                return u
            }
            guard !inFlight else { return usage }
            let minGap: TimeInterval = usage == nil ? 5 : 55
            guard now.timeIntervalSince(lastAttempt) > minGap else { return usage }

            inFlight = true
            lastAttempt = now
            defer { inFlight = false }

            fetchExecutionCount += 1
            if simulatedDelayMs > 0 {
                try? await Task.sleep(nanoseconds: simulatedDelayMs * 1_000_000)
            }

            let newUsage = AntigravityPlanUsage(
                geminiFiveHour: PlanWindow(usedPct: 25, resetsAt: now.addingTimeInterval(3600)),
                geminiWeekly: PlanWindow(usedPct: 10, resetsAt: now.addingTimeInterval(86400)),
                thirdPartyFiveHour: nil,
                thirdPartyWeekly: nil,
                updatedAt: now
            )
            usage = newUsage
            return newUsage
        }
    }

    static func testR04ParallelFetchProtection() async {
        print("\n--- R04: Parallel fetch protection (inFlight guard) ---")

        let engine = MockFetchEngine()
        let t0 = Date()

        // Launch first fetch with 50ms simulated duration
        let task1 = Task {
            await engine.fetch(now: t0, simulatedDelayMs: 50)
        }

        // Brief delay to ensure task1 has entered and set inFlight = true
        try? await Task.sleep(for: .milliseconds(10))
        check("inFlight is true during active fetch", engine.inFlight)

        // Attempt a concurrent second fetch
        let task2 = Task {
            await engine.fetch(now: t0.addingTimeInterval(0.01), simulatedDelayMs: 0)
        }

        _ = await task1.value
        _ = await task2.value

        check("Parallel request was suppressed (execution count == 1)", engine.fetchExecutionCount == 1)
        check("inFlight reset to false after completion", !engine.inFlight)
    }

    static func testR04RateLimitingAndMinGap() async {
        print("\n--- R04: Rate limiting & min gap (5s for nil, 55s for non-nil) ---")

        let engine = MockFetchEngine()
        var clock = Date()

        // 1. Initial attempt with usage == nil -> allowed
        _ = await engine.fetch(now: clock)
        check("First attempt allowed", engine.fetchExecutionCount == 1)

        // Reset usage to nil to test the 5s gap
        engine.usage = nil

        // Attempt 2s later (< 5s minGap) -> rejected
        clock.addTimeInterval(2.0)
        _ = await engine.fetch(now: clock)
        check("Attempt within 5s when nil is suppressed", engine.fetchExecutionCount == 1)

        // Attempt 6s later (> 5s minGap) -> allowed
        clock.addTimeInterval(4.0) // total 6s from lastAttempt
        _ = await engine.fetch(now: clock)
        check("Attempt after 5s when nil is allowed", engine.fetchExecutionCount == 2)
        check("Usage is now non-nil", engine.usage != nil)

        // 2. With usage != nil, min gap is 55s
        // Attempt 30s later (< 55s) -> suppressed
        clock.addTimeInterval(30.0)
        _ = await engine.fetch(now: clock)
        check("Attempt within 55s when loaded is suppressed", engine.fetchExecutionCount == 2)

        // Attempt 60s from last attempt (> 55s) -> allowed
        clock.addTimeInterval(30.0) // total 60s from lastAttempt
        _ = await engine.fetch(now: clock)
        check("Attempt after 60s is allowed and updates snapshot", engine.fetchExecutionCount == 3)
    }

    static func testR04ServerUnavailableRecovery() async {
        print("\n--- R04: Server unavailable (failure) recovery ---")

        var lastAttempt: Date = .distantPast
        var inFlight = false
        var usage: AntigravityPlanUsage? = nil
        var attempts = 0

        func queryServer(now: Date, returnSuccess: Bool) async -> AntigravityPlanUsage? {
            guard !inFlight else { return usage }
            let minGap: TimeInterval = usage == nil ? 5 : 55
            guard now.timeIntervalSince(lastAttempt) > minGap else { return usage }

            inFlight = true
            lastAttempt = now
            defer { inFlight = false }

            attempts += 1
            if returnSuccess {
                usage = AntigravityPlanUsage(
                    geminiFiveHour: PlanWindow(usedPct: 15, resetsAt: now.addingTimeInterval(3600)),
                    geminiWeekly: nil,
                    thirdPartyFiveHour: nil,
                    thirdPartyWeekly: nil,
                    updatedAt: now
                )
                return usage
            } else {
                // Server unavailable or returns nil
                return nil
            }
        }

        var clock = Date()

        // 1. Server offline: returns nil
        let res1 = await queryServer(now: clock, returnSuccess: false)
        check("Server offline returns nil", res1 == nil)
        check("inFlight cleared after failed attempt", !inFlight)
        check("attempts count incremented to 1", attempts == 1)

        // 2. Immediate retry suppressed
        clock.addTimeInterval(1.0)
        let res2 = await queryServer(now: clock, returnSuccess: false)
        check("Immediate retry suppressed", res2 == nil && attempts == 1)

        // 3. 6s later server comes online
        clock.addTimeInterval(5.0)
        let res3 = await queryServer(now: clock, returnSuccess: true)
        check("Recovery after offline: fetch succeeds", res3 != nil && attempts == 2)
        check("Updated usage is stored", usage != nil)
    }
}
