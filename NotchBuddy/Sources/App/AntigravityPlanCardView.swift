#if !APPSTORE
import SwiftUI

// MARK: - Antigravity Plan Card View

struct AntigravityPlanCardView: View {
    let usage: AntigravityPlanUsage?   // nil = loading or unavailable
    var codexRow: Bool = false
    var codexUsage: CodexPlanUsage? = nil
    var onCodex: (() -> Void)? = nil
    var claudeRow: Bool = false
    var claudeUsage: PlanUsage? = nil
    var onClaude: (() -> Void)? = nil

    @State private var now = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
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
            .padding(.top, 6)
            .padding(.leading, 108)
            .padding(.trailing, 36)

            // Gauge rows
            VStack(alignment: .leading, spacing: 5) {
                GaugeRowView(label: "Gemini 5h", window: usage?.geminiFiveHour, now: now, labelWidth: 64)
                GaugeRowView(label: "Gemini Wk", window: usage?.geminiWeekly, now: now, weekly: true, labelWidth: 64)
                if usage?.thirdPartyWeekly != nil {
                    GaugeRowView(label: "3P Wk", window: usage?.thirdPartyWeekly, now: now, weekly: true, labelWidth: 64)
                }
                if usage?.thirdPartyFiveHour != nil {
                    GaugeRowView(label: "3P 5h", window: usage?.thirdPartyFiveHour, now: now, labelWidth: 64)
                }
                #if !APPSTORE
                if codexRow {
                    Button(action: { onCodex?() }) {
                        let window = codexDominantWindow
                        GaugeRowView(label: "Codex", window: window, now: now,
                                     weekly: window != nil && window == codexUsage?.sevenDay, labelWidth: 64)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if claudeRow {
                    Button(action: { onClaude?() }) {
                        let window = claudeDominantWindow
                        GaugeRowView(label: "Claude", window: window, now: now,
                                     weekly: window != nil && window == claudeUsage?.sevenDay, labelWidth: 64)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                #endif
            }
            .padding(.top, 8)
            .padding(.leading, 108)
            .padding(.trailing, 12)
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
