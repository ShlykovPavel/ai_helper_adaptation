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

        print("ShapeshifterExpandedRenderer — Expressive Character Face Geometry")
        let face = ShapeshifterExpandedRenderer.faceGeometry(rect: CGRect(x: 0, y: 0, width: 80, height: 80), lookX: 0.5, lookY: -0.5)
        check("Left and right eye distinct horizontal positions", face.leftEyeCenter.x < face.rightEyeCenter.x)
        check("Pupil specular highlight offset inside eye bounds", face.leftSpecularPrimary.x < face.leftEyeCenter.x)
        check("Cheeks positioned symmetrically below eyes", face.leftCheekCenter.y > face.leftEyeCenter.y && face.rightCheekCenter.y > face.rightEyeCenter.y)
        check("Mouth positioned between cheeks", face.mouthCenter.y >= face.leftCheekCenter.y - 2)

        print("ShapeshifterExpandedRenderer — Action Props Geometry")
        let writingProp = ShapeshifterExpandedRenderer.actionPropsGeometry(rect: CGRect(x: 0, y: 0, width: 80, height: 80), action: .writing)
        check("Writing prop has tablet bounds", writingProp.propBounds.width > 0)
        check("Writing prop stroke color is cyan #64D2FF", writingProp.strokeColorHex == "#64D2FF")

        let readingProp = ShapeshifterExpandedRenderer.actionPropsGeometry(rect: CGRect(x: 0, y: 0, width: 80, height: 80), action: .reading)
        check("Reading prop stroke color is yellow #FDE047", readingProp.strokeColorHex == "#FDE047")

        let approvalProp = ShapeshifterExpandedRenderer.actionPropsGeometry(rect: CGRect(x: 0, y: 0, width: 80, height: 80), action: .approval)
        check("Approval prop stroke color is green #30D158", approvalProp.strokeColorHex == "#30D158")

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
