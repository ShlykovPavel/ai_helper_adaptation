import Foundation
import CoreGraphics

@main
enum ShapeshifterCompactLODTests {
    static var failures = 0
    static func check(_ label: String, _ got: Bool) {
        if got { print("  ✓ \(label)") }
        else   { print("  ✗ \(label)"); failures += 1 }
    }

    static func main() {
        print("ShapeshifterCompactRenderer — Review Focus 3: Provider badge colors & nil fallback")
        let claude = ShapeshifterCompactRenderer.badgeColor(for: .claude)
        check("Claude badge color is terracotta #D97757", claude.hex == "#D97757")

        let gemini = ShapeshifterCompactRenderer.badgeColor(for: .gemini)
        check("Gemini badge color is #4E80EE", gemini.hex == "#4E80EE")

        let openai = ShapeshifterCompactRenderer.badgeColor(for: .openai)
        check("OpenAI badge color is #10A37F", openai.hex == "#10A37F")

        let antigravity = ShapeshifterCompactRenderer.badgeColor(for: .antigravity)
        check("Antigravity badge color is #8B5CF6", antigravity.hex == "#8B5CF6")

        let customFallback = ShapeshifterCompactRenderer.badgeColor(for: .custom("unknown"))
        check("Unknown provider falls back to astral cyan #64D2FF", customFallback.hex == "#64D2FF")

        print("ShapeshifterCompactRenderer — Review Focus 4: Clamping non-square bounding rects")
        let clampedSquare = ShapeshifterCompactRenderer.clampedDrawRect(in: CGSize(width: 40, height: 20))
        check("Clamped width matches height (20)", clampedSquare.width == 20 && clampedSquare.height == 20)
        check("Clamped rect is centered horizontally (x == 10)", clampedSquare.origin.x == 10)

        print("ShapeshifterCompactRenderer — Expressive Character Features (Eyes & Specular Highlights)")
        let eyes = ShapeshifterCompactRenderer.eyeOffsets(lookX: 1.0, lookY: -1.0, diameter: 24)
        check("Left eye within safe horizontal boundary", abs(eyes.left.x) <= 6.0)
        check("Right eye within safe horizontal boundary", abs(eyes.right.x) <= 6.0)

        let highlights = ShapeshifterCompactRenderer.specularHighlightOffsets(lookX: 0.0, lookY: 0.0, diameter: 24)
        check("Left eye primary specular dot is in top-left quadrant", highlights.leftPrimary.x < eyes.left.x && highlights.leftPrimary.y < eyes.left.y)

        print("ShapeshifterCompactRenderer — Rosy Cheek Blush Geometry")
        let cheeks = ShapeshifterCompactRenderer.cheekBlushOffsets(diameter: 24)
        check("Cheeks are positioned below eye level", cheeks.left.y > 0 && cheeks.right.y > 0)
        check("Cheek radius is proportional (approx 1.5 - 2.5pt)", cheeks.radius >= 1.2 && cheeks.radius <= 3.0)

        print("ShapeshifterCompactLODTests finished with \(failures) failures.")
        if failures > 0 { exit(1) }
    }
}
