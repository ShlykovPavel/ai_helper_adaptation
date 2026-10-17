#if !APPSTORE
import SwiftUI

// MARK: - Antigravity Plan Card View

struct AntigravityPlanCardView: View {
    let usage: AntigravityPlanUsage?   // nil = loading or unavailable

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
}
#endif
