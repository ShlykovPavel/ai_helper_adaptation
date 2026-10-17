import Foundation

@main
enum AgentToastTests {
    static var failures = 0
    static func check(_ label: String, _ condition: Bool) {
        if condition { print("  ✓ \(label)") }
        else { print("  ✗ \(label)"); failures += 1 }
    }

    static func main() {
        print("AgentToastTests")
        let now = Date()
        let toast = AgentToast(pillId: "agent_antigravity", message: "Antigravity: Done", colorHex: "#E879F9", timestamp: now)
        check("toast pillId", toast.pillId == "agent_antigravity")
        check("toast message", toast.message == "Antigravity: Done")
        check("toast color", toast.colorHex == "#E879F9")
        check("toast timestamp", toast.timestamp == now)

        let toastSame = AgentToast(pillId: "agent_antigravity", message: "Antigravity: Done", colorHex: "#E879F9", timestamp: now)
        let toastDifferentPill = AgentToast(pillId: "agent_codex", message: "Antigravity: Done", colorHex: "#E879F9", timestamp: now)
        let toastDifferentMsg = AgentToast(pillId: "agent_antigravity", message: "Different", colorHex: "#E879F9", timestamp: now)
        let toastDifferentColor = AgentToast(pillId: "agent_antigravity", message: "Antigravity: Done", colorHex: "#000000", timestamp: now)
        let toastDifferentTime = AgentToast(pillId: "agent_antigravity", message: "Antigravity: Done", colorHex: "#E879F9", timestamp: now.addingTimeInterval(10))
        let toastDefault = AgentToast(pillId: "agent_antigravity", message: "Antigravity: Done", colorHex: "#E879F9")

        check("toast equality (same properties)", toast == toastSame)
        check("toast inequality (different pillId)", toast != toastDifferentPill)
        check("toast inequality (different message)", toast != toastDifferentMsg)
        check("toast inequality (different colorHex)", toast != toastDifferentColor)
        check("toast inequality (different timestamp)", toast != toastDifferentTime)
        check("toast default timestamp initializes to now", abs(toastDefault.timestamp.timeIntervalSinceNow) < 5.0)

        if failures > 0 { exit(1) }
    }
}
