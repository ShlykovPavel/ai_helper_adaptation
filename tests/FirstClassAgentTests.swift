import Foundation
import CoreGraphics

// Minimal stubs for standalone IslandTypes compilation
enum EyeShape: String { case pill }
struct IslandScreenGeometry { static let fallbackNotchWidth: CGFloat = 160 }

@main
enum FirstClassAgentTests {
    static var failures = 0
    static func check(_ label: String, _ condition: Bool) {
        if condition { print("  ✓ \(label)") }
        else { print("  ✗ \(label)"); failures += 1 }
    }

    static func main() {
        print("FirstClassAgentTests")

        // 1. Antigravity session subtitle
        let agyDef = PillCatalog.definition(for: "agent_antigravity")
        check("agent_antigravity definition exists", agyDef != nil)
        check("agent_antigravity sessionSubtitle is Antigravity", agyDef?.sessionSubtitle == "Antigravity")

        // 2. First-class agent identification
        let firstClassPills = ["integration_claude", "agent_codex", "agent_cursor", "agent_antigravity"]
        for pill in firstClassPills {
            check("\(pill) is recognized as first-class", PillCatalog.definition(for: pill) != nil)
        }

        if failures > 0 { exit(1) }
    }
}
