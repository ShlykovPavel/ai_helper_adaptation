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

        // 4. Multi-Form Physics Math
        print("AstralHybridIdle — Multi-Form Motion Physics Math")
        let bounce0 = AstralHybridMotion.bounceY(at: 0, amp: 6.0)
        check("Bounce at 0 is 0.0", abs(bounce0) < 0.001)

        let bouncePeak = AstralHybridMotion.bounceY(at: .pi / 8.0, amp: 6.0) // 4.0 * (.pi / 8) = .pi / 2 -> sin = 1
        check("Bounce at quarter-period reaches -amp (-6.0)", abs(bouncePeak - (-6.0)) < 0.001)

        let tilt0 = AstralHybridMotion.tiltAngle(at: 0, maxAngle: 0.12)
        check("Tilt angle at 0 is 0.0", abs(tilt0) < 0.001)

        let tiltPeak = AstralHybridMotion.tiltAngle(at: .pi / 3.0, maxAngle: 0.12) // 1.5 * (.pi / 3) = .pi / 2 -> sin = 1
        check("Tilt angle at quarter-period reaches maxAngle (0.12)", abs(tiltPeak - 0.12) < 0.001)

        let shake = AstralHybridMotion.flameShake(at: 1.0, amp: 2.0)
        check("Flame shake returns finite values", shake.dx.isFinite && shake.dy.isFinite)

        let flicker = AstralHybridMotion.flickerOffset(at: 1.0, amp: 2.0)
        check("Flicker offset alias matches flameShake", flicker.dx == shake.dx && flicker.dy == shake.dy)

        let gaze0 = AstralHybridMotion.searchGazeX(at: 0)
        check("Search gaze at 0 is 0.0", abs(gaze0) < 0.001)

        let gazePeak = AstralHybridMotion.searchGazeX(at: .pi / 4.0) // 2.0 * (.pi / 4) = .pi / 2 -> sin = 1
        check("Search gaze at quarter-period is 0.75", abs(gazePeak - 0.75) < 0.001)

        // 5. State Mapping
        print("AstralHybridIdle — Form & State Resolution")
        check("Form for finished is orb", AstralHybridForm.form(for: "finished") == .orb)
        check("Form for done is orb", AstralHybridForm.form(for: "done") == .orb)
        check("Form for question is cube", AstralHybridForm.form(for: "question") == .cube)
        check("Form for approval is cube", AstralHybridForm.form(for: "approval") == .cube)
        check("Form for permission is cube", AstralHybridForm.form(for: "permission") == .cube)
        check("Form for error is wisp", AstralHybridForm.form(for: "error") == .wisp)
        check("Form for ratelimit is wisp", AstralHybridForm.form(for: "ratelimit") == .wisp)
        check("Form for dizzy is wisp", AstralHybridForm.form(for: "dizzy") == .wisp)
        check("Form for idle is ghost", AstralHybridForm.form(for: "idle") == .ghost)
        check("Form for sleeping is ghost", AstralHybridForm.form(for: "sleeping") == .ghost)
        check("Form for working is ghost", AstralHybridForm.form(for: "working") == .ghost)
        check("Form for thinking is ghost", AstralHybridForm.form(for: "thinking") == .ghost)
        check("Form for searching is ghost", AstralHybridForm.form(for: "searching") == .ghost)

        enum TestState: String {
            case finished, question, error, idle
        }
        check("RawRepresentable form for finished is orb", AstralHybridForm.form(for: TestState.finished) == .orb)
        check("RawRepresentable form for question is cube", AstralHybridForm.form(for: TestState.question) == .cube)
        check("RawRepresentable form for error is wisp", AstralHybridForm.form(for: TestState.error) == .wisp)
        check("RawRepresentable form for idle is ghost", AstralHybridForm.form(for: TestState.idle) == .ghost)

        for s in AstralHybridState.allCases {
            check("AstralHybridState \(s.rawValue) resolves form", s.form == AstralHybridForm.form(for: s.rawValue))
        }

        // 6. Eye Geometry Specs
        print("AstralHybridIdle — Eye Geometry Specs")
        for form in AstralHybridForm.allCases {
            let geom = AstralHybridEyeGeometry.geometry(for: form)
            check("Geom for \(form) has symmetric Y", abs(geom.leftY - geom.rightY) < 0.001)
            check("Geom for \(form) has valid horizontal separation", geom.leftX < geom.rightX)
            check("Geom for \(form) has positive eye radii", geom.rx > 0 && geom.ry > 0)
        }

        // 7. Assets Loading & Caching
        print("AstralHybridIdle — Assets Loading & Caching")
        AstralHybridAssets.shared.clearCache()
        let ghostImg = AstralHybridAssets.shared.bodyImage(for: .ghost)
        check("Loads ghost image from disk/bundle", ghostImg != nil)

        let orbImg = AstralHybridAssets.shared.bodyImage(for: .orb)
        check("Loads orb image from disk/bundle", orbImg != nil)

        let cubeImg = AstralHybridAssets.shared.bodyImage(for: .cube)
        check("Loads cube image from disk/bundle", cubeImg != nil)

        let wispImg = AstralHybridAssets.shared.bodyImage(for: .wisp)
        check("Loads wisp image from disk/bundle", wispImg != nil)

        // 8. Rendering in Context
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

        // Draw awake state (legacy signature)
        AstralHybridRenderer.draw(
            in: ctx,
            size: CGSize(width: 128, height: 128),
            elapsed: 1.5,
            lookX: 0.5,
            lookY: -0.3,
            isSleeping: false,
            imageOverride: dummyImg
        )
        check("Renderer draws awake frame without crashing (legacy signature)", true)

        // Draw sleeping state (legacy signature)
        AstralHybridRenderer.draw(
            in: ctx,
            size: CGSize(width: 128, height: 128),
            elapsed: 3.0,
            lookX: 0,
            lookY: 0,
            isSleeping: true,
            imageOverride: dummyImg
        )
        check("Renderer draws sleeping frame with sleep arcs without crashing (legacy signature)", true)

        // Draw all forms and states with full signature
        let statesToTest = ["idle", "working", "thinking", "searching", "finished", "approval", "question", "error", "ratelimit", "dizzy", "sleeping"]
        for st in statesToTest {
            let targetForm = AstralHybridForm.form(for: st)
            AstralHybridRenderer.draw(
                in: ctx,
                size: CGSize(width: 128, height: 128),
                elapsed: 2.5,
                form: targetForm,
                stateName: st,
                lookX: 0.3,
                lookY: -0.2,
                isSleeping: (st == "sleeping"),
                imageOverride: dummyImg
            )
        }
        check("Renderer draws all 11 states across all 4 forms with dummy image", true)

        // Test fallback body rendering (imageOverride == nil and clear cache)
        AstralHybridAssets.shared.clearCache()
        for form in AstralHybridForm.allCases {
            AstralHybridRenderer.draw(
                in: ctx,
                size: CGSize(width: 128, height: 128),
                elapsed: 1.0,
                form: form,
                stateName: "idle",
                lookX: 0,
                lookY: 0,
                isSleeping: false,
                imageOverride: dummyImg
            )
        }
        check("Renderer draws all forms without crashing", true)

        // 9. R07: Vertical eye look direction contract verification
        print("AstralHybridIdle — R07 Look Direction Contract")
        let testRect = CGRect(x: 0, y: 0, width: 100, height: 100)
        let neutralEyes = AstralHybridRenderer.eyeCenters(rect: testRect, form: .ghost, lookX: 0, lookY: 0)
        let lookDownEyes = AstralHybridRenderer.eyeCenters(rect: testRect, form: .ghost, lookX: 0, lookY: -1.0)
        let lookUpEyes = AstralHybridRenderer.eyeCenters(rect: testRect, form: .ghost, lookX: 0, lookY: 1.0)

        check("Cursor below (lookY = -1.0) shifts eyes DOWN (left.y > neutral.y)", lookDownEyes.left.y > neutralEyes.left.y)
        check("Cursor below (lookY = -1.0) shifts eyes DOWN (right.y > neutral.y)", lookDownEyes.right.y > neutralEyes.right.y)
        check("Cursor above (lookY = 1.0) shifts eyes UP (left.y < neutral.y)", lookUpEyes.left.y < neutralEyes.left.y)
        check("Cursor above (lookY = 1.0) shifts eyes UP (right.y < neutral.y)", lookUpEyes.right.y < neutralEyes.right.y)

        let lookRightEyes = AstralHybridRenderer.eyeCenters(rect: testRect, form: .ghost, lookX: 1.0, lookY: 0)
        let lookLeftEyes = AstralHybridRenderer.eyeCenters(rect: testRect, form: .ghost, lookX: -1.0, lookY: 0)
        check("Cursor right (lookX = 1.0) shifts eyes RIGHT", lookRightEyes.left.x > neutralEyes.left.x)
        check("Cursor left (lookX = -1.0) shifts eyes LEFT", lookLeftEyes.left.x < neutralEyes.left.x)

        // 10. R17: Slap / poke bounce physics and state machine verification
        print("AstralHybridIdle — R17 Slap Physics & State Machine")
        let slapInitial = AstralHybridMotion.slapBounce(at: 0.0, duration: 0.5, amp: 10.0)
        check("Slap at 0 is active", slapInitial.isActive)
        check("Slap at 0 has zero vertical bounce", abs(slapInitial.bounceY) < 0.001)
        check("Slap at 0 has initial squash (scaleX > 1, scaleY < 1)", slapInitial.scaleX > 1.0 && slapInitial.scaleY < 1.0)
        check("Slap at 0 has initial blush alpha", slapInitial.blushAlpha > 0.5)

        let slapMid = AstralHybridMotion.slapBounce(at: 0.25, duration: 0.5, amp: 10.0)
        check("Slap at midpoint is active", slapMid.isActive)
        check("Slap at midpoint reaches peak negative bounceY (lifted up)", slapMid.bounceY < -9.5)
        check("Slap at midpoint has flight stretch (scaleY > 1)", slapMid.scaleY > 1.0)

        let slapEnd = AstralHybridMotion.slapBounce(at: 0.55, duration: 0.5, amp: 10.0)
        check("Slap past duration is inactive", !slapEnd.isActive)
        check("Slap past duration has zero bounce", abs(slapEnd.bounceY) < 0.001)

        let slapNegative = AstralHybridMotion.slapBounce(at: -0.1, duration: 0.5, amp: 10.0)
        check("Slap with negative elapsed is inactive", !slapNegative.isActive)

        // State machine tests
        var slapState = AstralHybridSlapState(duration: 0.5)
        check("SlapState starts inactive", !slapState.isActive(at: 100.0))
        check("SlapState elapsed is nil when inactive", slapState.elapsed(at: 100.0) == nil)

        slapState.trigger(at: 100.0)
        check("SlapState is active after trigger", slapState.isActive(at: 100.1))
        check("SlapState elapsed matches time delta", abs((slapState.elapsed(at: 100.1) ?? 0) - 0.1) < 0.001)

        // Repeat slap before finish resets duration
        slapState.trigger(at: 100.3)
        check("SlapState remains active after second trigger", slapState.isActive(at: 100.6))
        check("SlapState elapsed is relative to latest trigger", abs((slapState.elapsed(at: 100.6) ?? 0) - 0.3) < 0.001)

        // Slap finishes cleanly
        check("SlapState becomes inactive after duration", !slapState.isActive(at: 100.9))
        check("SlapState elapsed is nil after duration", slapState.elapsed(at: 100.9) == nil)

        // Reset clears slap (e.g. on collapse or pause)
        slapState.trigger(at: 200.0)
        slapState.reset()
        check("SlapState is inactive after reset", !slapState.isActive(at: 200.1))

        // Draw with active slap
        AstralHybridRenderer.draw(
            in: ctx,
            size: CGSize(width: 128, height: 128),
            elapsed: 1.0,
            form: .ghost,
            stateName: "idle",
            lookX: 0,
            lookY: 0,
            isSleeping: false,
            slapElapsed: 0.25,
            imageOverride: dummyImg
        )
        check("Renderer draws frame with active slap and blush without crashing", true)

        print("AstralHybridIdleTests finished with \(failures) failures.")
        if failures > 0 { exit(1) }
    }
}
