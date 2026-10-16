import Foundation
import CoreGraphics

@main
enum ShapeshifterExpandedLODTests {
    static var failures = 0
    static func check(_ label: String, _ got: Bool) {
        if got { print("  ✓ \(label)") }
        else   { print("  ✗ \(label)"); failures += 1 }
    }

    static func main() {
        print("ShapeshifterExpandedRenderer — harmonic core float calculation")
        let y0 = ShapeshifterExpandedRenderer.harmonicCoreYOffset(phase: 0.0, amplitude: 2.5)
        check("Offset at phase 0 is 0.0", abs(y0) < 0.001)

        let yQuarter = ShapeshifterExpandedRenderer.harmonicCoreYOffset(phase: 0.25, amplitude: 2.5)
        check("Offset at phase 0.25 is peak 2.5", abs(yQuarter - 2.5) < 0.001)

        let yThreeQuarter = ShapeshifterExpandedRenderer.harmonicCoreYOffset(phase: 0.75, amplitude: 2.5)
        check("Offset at phase 0.75 is trough -2.5", abs(yThreeQuarter - (-2.5)) < 0.001)

        print("ShapeshifterExpandedRenderer — Review Focus 4: Non-square bounding box centering")
        let clampedRect = ShapeshifterExpandedRenderer.clampedDrawRect(in: CGSize(width: 120, height: 60))
        check("Clamped side is 60", clampedRect.width == 60 && clampedRect.height == 60)
        check("Clamped rect is centered horizontally (x == 30)", clampedRect.origin.x == 30)

        let clampedTall = ShapeshifterExpandedRenderer.clampedDrawRect(in: CGSize(width: 60, height: 120))
        check("Clamped tall side is 60", clampedTall.width == 60 && clampedTall.height == 60)
        check("Clamped tall rect is centered vertically (y == 30)", clampedTall.origin.y == 30)

        print("ShapeshifterExpandedRenderer — Review Focus 3: Fallback core for unknown provider")
        let coreColor = ShapeshifterExpandedRenderer.coreColor(for: .custom("generic_agent"))
        check("Custom provider core color is astral cyan #64D2FF", coreColor.hex == "#64D2FF")

        let claudeColor = ShapeshifterExpandedRenderer.coreColor(for: .claude)
        check("Claude provider core color is terracotta #D97757", claudeColor.hex == "#D97757")

        let geminiColor = ShapeshifterExpandedRenderer.coreColor(for: .gemini)
        check("Gemini provider core color is #4E80EE", geminiColor.hex == "#4E80EE")

        let openaiColor = ShapeshifterExpandedRenderer.coreColor(for: .openai)
        check("OpenAI provider core color is #10A37F", openaiColor.hex == "#10A37F")

        let antigravityColor = ShapeshifterExpandedRenderer.coreColor(for: .antigravity)
        check("Antigravity provider core color is #8B5CF6", antigravityColor.hex == "#8B5CF6")

        print("ShapeshifterExpandedLODTests finished with \(failures) failures.")
        if failures > 0 { exit(1) }
    }
}
