#if !APPSTORE
import SwiftUI

// MARK: - Antigravity Model Tab

enum AntigravityModelTab: String, CaseIterable, Sendable {
    case gemini
    case thirdParty
}

// MARK: - Antigravity Plan Card View

struct AntigravityPlanCardView: View {
    let usage: AntigravityPlanUsage?   // nil = loading or unavailable
    var codexRow: Bool = false
    var codexUsage: CodexPlanUsage? = nil
    var onCodex: (() -> Void)? = nil
    var claudeRow: Bool = false
    var claudeUsage: PlanUsage? = nil
    var onClaude: (() -> Void)? = nil

    @State private var selectedTab: AntigravityModelTab = .gemini
    @State private var now = Date()

    private var hasThirdParty: Bool {
        usage?.thirdPartyWeekly != nil || usage?.thirdPartyFiveHour != nil
    }

    private var thirdPartyWarning: Bool {
        guard let usage else { return false }
        let wPct = usage.thirdPartyWeekly.map { ClaudePlanGauge.effectivePct($0) } ?? 0
        let fPct = usage.thirdPartyFiveHour.map { ClaudePlanGauge.effectivePct($0) } ?? 0
        return wPct >= 80 || fPct >= 80
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(hex: AntigravityPlanGauge.color(usage)))
                        .frame(width: 7, height: 7)
                    Text("Antigravity plan")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(hex: "#F5F6F8"))
                    Text(subtitleText)
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#8E939C"))
                        .lineLimit(1)
                        .fixedSize()
                }

                Spacer(minLength: 8)

                // Segmented model switcher: [ Gemini ] [ Claude & GPT • ]
                if hasThirdParty {
                    HStack(spacing: 2) {
                        Button(action: {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                selectedTab = .gemini
                            }
                        }) {
                            Text("Gemini")
                                .font(.system(size: 10, weight: selectedTab == .gemini ? .semibold : .medium))
                                .foregroundColor(selectedTab == .gemini ? Color(hex: "#F5F6F8") : Color(hex: "#8E939C"))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2.5)
                                .background(selectedTab == .gemini ? Color.white.opacity(0.12) : Color.clear)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)

                        Button(action: {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                selectedTab = .thirdParty
                            }
                        }) {
                            HStack(spacing: 3) {
                                Text("Claude & GPT")
                                if thirdPartyWarning {
                                    Circle()
                                        .fill(Color(hex: "#FF5252"))
                                        .frame(width: 4, height: 4)
                                }
                            }
                            .font(.system(size: 10, weight: selectedTab == .thirdParty ? .semibold : .medium))
                            .foregroundColor(selectedTab == .thirdParty ? Color(hex: "#F5F6F8") : Color(hex: "#8E939C"))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(selectedTab == .thirdParty ? Color.white.opacity(0.12) : Color.clear)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(2)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Capsule())
                }
            }
            .padding(.top, 6)
            .padding(.leading, 134)
            .padding(.trailing, 44)

            // Gauge rows (clean single column with 2 rows)
            VStack(alignment: .leading, spacing: 5) {
                if selectedTab == .gemini {
                    GaugeRowView(label: "5 hours", window: usage?.geminiFiveHour, now: now, labelWidth: 54)
                    GaugeRowView(label: "Week", window: usage?.geminiWeekly, now: now, weekly: true, labelWidth: 54)
                } else {
                    GaugeRowView(label: "5 hours", window: usage?.thirdPartyFiveHour, now: now, labelWidth: 54)
                    GaugeRowView(label: "Week", window: usage?.thirdPartyWeekly, now: now, weekly: true, labelWidth: 54)
                }

                #if !APPSTORE
                if codexRow, codexUsage != nil {
                    Button(action: { onCodex?() }) {
                        let window = codexDominantWindow
                        GaugeRowView(label: "Codex", window: window, now: now,
                                     weekly: window != nil && window == codexUsage?.sevenDay, labelWidth: 54)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else if claudeRow, claudeUsage != nil {
                    Button(action: { onClaude?() }) {
                        let window = claudeDominantWindow
                        GaugeRowView(label: "Claude", window: window, now: now,
                                     weekly: window != nil && window == claudeUsage?.sevenDay, labelWidth: 54)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                #endif
            }
            .padding(.top, 8)
            .padding(.leading, 134)
            .padding(.trailing, 16)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.top, 4)
        // Update countdown every 30s, only while visible
        .background(
            TimelineView(.periodic(from: .now, by: 30)) { ctx in
                Color.clear.onChange(of: ctx.date) { _, d in now = d }
            }
        )
    }

    private var subtitleText: String {
        guard let usage else { return "Asking Antigravity…" }
        let diff = now.timeIntervalSince(usage.updatedAt)
        if diff < 60 { return "just now" }
        let mins = Int(diff / 60)
        if mins < 60 { return "\(mins) min ago" }
        return "\(mins / 60) h ago"
    }

    #if !APPSTORE
    private var codexDominantWindow: PlanWindow? {
        guard let u = codexUsage else { return nil }
        switch (u.fiveHour, u.sevenDay) {
        case (nil, nil): return nil
        case (let f?, nil): return f
        case (nil, let w?): return w
        case (let f?, let w?):
            return ClaudePlanGauge.effectivePct(f) >= ClaudePlanGauge.effectivePct(w) ? f : w
        }
    }

    private var claudeDominantWindow: PlanWindow? {
        guard let u = claudeUsage else { return nil }
        switch (u.fiveHour, u.sevenDay) {
        case (nil, nil): return nil
        case (let f?, nil): return f
        case (nil, let w?): return w
        case (let f?, let w?):
            return ClaudePlanGauge.effectivePct(f) >= ClaudePlanGauge.effectivePct(w) ? f : w
        }
    }
    #endif
}
#endif
