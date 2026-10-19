import Foundation
import CoreGraphics

@main
enum AstralHybridIdleTests {
    static var failures = 0
    static func check(_ label: String, _ got: Bool) {
        if got { print("  ✓ \(label)") }
        else   { print("  ✗ \(label)"); failures += 1 }
    }

    static func main() {
        print("AstralHybridIdle — Motion Physics Math")

        // 1. Float Y math
        let float0 = AstralHybridMotion.floatY(at: 0, amp: 4.0)
        check("Float at 0 is 0.0", abs(float0) < 0.001)

        let floatPeak = AstralHybridMotion.floatY(at: .pi / 4.0, amp: 4.0) // 2.0 * (.pi / 4) = .pi / 2 -> sin = 1
        check("Float at quarter-period reaches peak amp (4.0)", abs(floatPeak - 4.0) < 0.001)

        let floatSleepPeak = AstralHybridMotion.floatY(at: .pi / 2.4, amp: 4.0, isSleeping: true) // 1.2 * (.pi / 2.4) = .pi / 2 -> sin = 1
        check("Float when sleeping is reduced to 3.0", abs(floatSleepPeak - 3.0) < 0.001)

        // 2. Breath Squash & Stretch
        let (scaleX0, scaleY0) = AstralHybridMotion.breathScale(at: 0)
        check("ScaleX at 0 is 1.015", abs(scaleX0 - 1.015) < 0.001)
        check("ScaleY at 0 is 0.985", abs(scaleY0 - 0.985) < 0.001)
        check("Volume preservation product ~ 1.0", abs((scaleX0 * scaleY0) - 1.0) < 0.001)

        let (scaleXSleep, _) = AstralHybridMotion.breathScale(at: 0, isSleeping: true)
        check("Sleeping breath has deeper delta (1.022)", abs(scaleXSleep - 1.022) < 0.001)

        // 3. Blink State Machine
        let blink0 = AstralHybridMotion.blinkProgress(at: 0)
        check("Blink at 0 is open (0.0)", blink0 == 0.0)

        let blinkMid = AstralHybridMotion.blinkProgress(at: 0.09) // 0.18 / 2
        check("Blink at midpoint is fully closed (1.0)", abs(blinkMid - 1.0) < 0.01)

        let blinkEnd = AstralHybridMotion.blinkProgress(at: 0.20)
        check("Blink after 200ms is fully open again (0.0)", blinkEnd == 0.0)

        let blinkRest = AstralHybridMotion.blinkProgress(at: 2.0)
        check("Blink during resting interval is 0.0", blinkRest == 0.0)

        // 4. Rendering in Context
        print("AstralHybridIdle — Rendering Verification")
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: 128,
            height: 128,
            bitsPerComponent: 8,
            bytesPerRow: 128 * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            print("  ✗ Failed to create test CGContext")
            exit(1)
        }

        // Create dummy synthetic 3D base image for headless test
        guard let dummyCtx = CGContext(
            data: nil,
            width: 64,
            height: 64,
            bitsPerComponent: 8,
            bytesPerRow: 64 * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let dummyImg = dummyCtx.makeImage() else {
            print("  ✗ Failed to create dummy test image")
            exit(1)
        }

        // Draw awake state
        AstralHybridRenderer.draw(
            in: ctx,
            size: CGSize(width: 128, height: 128),
            elapsed: 1.5,
            lookX: 0.5,
            lookY: -0.3,
            isSleeping: false,
            imageOverride: dummyImg
        )
        check("Renderer draws awake frame without crashing", true)

        // Draw sleeping state
        AstralHybridRenderer.draw(
            in: ctx,
            size: CGSize(width: 128, height: 128),
            elapsed: 3.0,
            lookX: 0,
            lookY: 0,
            isSleeping: true,
            imageOverride: dummyImg
        )
        check("Renderer draws sleeping frame with sleep arcs without crashing", true)

        print("AstralHybridIdleTests finished with \(failures) failures.")
        if failures > 0 { exit(1) }
    }
}
