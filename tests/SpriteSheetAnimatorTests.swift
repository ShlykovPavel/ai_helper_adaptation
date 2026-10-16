import Foundation
import CoreGraphics

@main
enum SpriteSheetAnimatorTests {
    static var failures = 0
    static func check(_ label: String, _ got: Bool) {
        if got { print("  ✓ \(label)") }
        else   { print("  ✗ \(label)"); failures += 1 }
    }

    static func main() {
        print("SpriteSheetAnimator — frame advancement at 24 FPS")
        let config = SpriteSheetConfig(frameCount: 24, fps: 24.0, columns: 24, rows: 1, frameWidth: 240, frameHeight: 240)
        let animator = SpriteSheetAnimator(config: config)
        check("Initial frame is 0", animator.currentFrameIndex == 0)

        _ = animator.update(dt: 1.0 / 24.0)
        check("Frame advances to 1 after 1/24s", animator.currentFrameIndex == 1)

        print("SpriteSheetAnimator — Review Focus 2: Missing asset graceful fallback")
        let missingAssetImage = SpriteSheetLoader.shared.image(for: .sleeping, bundle: Bundle(for: SpriteSheetAnimator.self))
        check("Non-existent sprite returns nil without crash", missingAssetImage == nil)

        let fallbackDecision = SpriteSheetLoader.shouldUseVectorFallback(action: .sleeping, bundle: Bundle(for: SpriteSheetAnimator.self))
        check("Fallback flag is true when asset is missing", fallbackDecision == true)

        print("SpriteSheetAnimator — Review Focus 2: Paused state 0% work")
        animator.isPaused = true
        _ = animator.update(dt: 10.0)
        check("Frame does not advance while paused", animator.currentFrameIndex == 1)

        print("SpriteSheetAnimator — frameRect math")
        let rect = animator.frameRect(for: 2, imageSize: CGSize(width: 240 * 24, height: 240))
        check("Horizontal strip rect X origin is 480", rect.origin.x == 480)
        check("Rect width is 240", rect.width == 240)

        print("SpriteSheetAnimator — Action state switch resets time")
        animator.setAction(.writing)
        check("Action switch resets to frame 0", animator.currentFrameIndex == 0)

        print("SpriteSheetAnimatorTests finished with \(failures) failures.")
        if failures > 0 { exit(1) }
    }
}
