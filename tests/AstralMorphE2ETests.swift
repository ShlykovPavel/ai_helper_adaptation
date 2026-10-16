import Foundation
import CoreGraphics

@main
enum AstralMorphE2ETests {
    static var failures = 0
    static func check(_ label: String, _ got: Bool) {
        if got { print("  ✓ \(label)") }
        else   { print("  ✗ \(label)"); failures += 1 }
    }

    static func main() {
        print("=== Astral Morph Mascot End-to-End Verification ===")

        print("1. Geometry & Overhang Compensation")
        check("Overhang 40 offset is 20", ShapeshifterGeometry.verticalOffset(particleOverhang: 40) == 20)
        check("Collapsed notch mode is compact", ShapeshifterGeometry.isCompactMode(mode: .hidden, isMini: false))

        print("2. 24 FPS Sprite Animation Pipeline & Fallback")
        let anim = SpriteSheetAnimator(config: .default(for: .writing))
        check("Writing cycle has 24 frames", anim.config.frameCount == 24)
        _ = anim.update(dt: 0.5)
        check("Midway frame index is 12", anim.currentFrameIndex == 12)
        check("Missing asset flags vector fallback", SpriteSheetLoader.shouldUseVectorFallback(action: .writing))

        print("3. Compact LOD (20-32px)")
        let compactRect = ShapeshifterCompactRenderer.clampedDrawRect(in: CGSize(width: 32, height: 32))
        check("Compact rect is 32x32", compactRect.width == 32 && compactRect.height == 32)
        let claudeBadge = ShapeshifterCompactRenderer.badgeColor(for: .claude)
        check("Claude badge terracotta hex", claudeBadge.hex == "#D97757")

        print("4. Expanded LOD (64-120px)")
        let expandedRect = ShapeshifterExpandedRenderer.clampedDrawRect(in: CGSize(width: 80, height: 80))
        check("Expanded rect is 80x80", expandedRect.width == 80 && expandedRect.height == 80)
        let coreY = ShapeshifterExpandedRenderer.harmonicCoreYOffset(phase: 0.25)
        check("Core oscillation peak at phase 0.25", abs(coreY - 2.5) < 0.001)

        print("5. Facade & Secondary Surfaces")
        check("working -> writing", ShapeshifterStateMapper.mapAction(state: "working") == .writing)
        check("searching -> reading", ShapeshifterStateMapper.mapAction(state: "searching") == .reading)
        check("Hub live mascot resolves shapeshifter when active", HubMascotResolver.isShapeshifterActive)

        print("=== E2E Test Result: \(failures) failures ===")
        if failures > 0 { exit(1) }
    }
}
