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
        let toast = AgentToast(pillId: "agent_antigravity", message: "Antigravity: Done", colorHex: "#E879F9")
        check("toast pillId", toast.pillId == "agent_antigravity")
        check("toast message", toast.message == "Antigravity: Done")
        check("toast color", toast.colorHex == "#E879F9")

        if failures > 0 { exit(1) }
    }
}
