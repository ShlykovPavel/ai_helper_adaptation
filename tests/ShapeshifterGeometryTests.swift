import Foundation
import CoreGraphics

#if STANDALONE_CLI
public enum IslandMode: Sendable {
    case hidden
    case compact
    case expanded
}
#endif

@main
enum ShapeshifterGeometryTests {
    static var failures = 0
    static func check(_ label: String, _ got: Bool) {
        if got { print("  ✓ \(label)") }
        else   { print("  ✗ \(label)"); failures += 1 }
    }

    static func main() {
        print("ShapeshifterGeometry — Review Focus 1: Vertical Offset & Notch Overhang Compensation")
        let overhang40 = ShapeshifterGeometry.verticalOffset(particleOverhang: 40)
        check("Overhang 40 yields downward offset +20", overhang40 == 20)

        let overhangZero = ShapeshifterGeometry.verticalOffset(particleOverhang: 0)
        check("Overhang 0 yields downward offset 0", overhangZero == 0)

        print("ShapeshifterGeometry — Mode Detection (Collapsed notch must be compact)")
        check("Hidden mode is compact", ShapeshifterGeometry.isCompactMode(mode: .hidden, isMini: false))
        check("Compact mode is compact", ShapeshifterGeometry.isCompactMode(mode: .compact, isMini: false))
        check("Mini pill is compact", ShapeshifterGeometry.isCompactMode(mode: .expanded, isMini: true))
        check("Expanded mode is NOT compact", !ShapeshifterGeometry.isCompactMode(mode: .expanded, isMini: false))

        print("ShapeshifterGeometry — Review Focus 4: Target Sizing in Notch and Cards")
        let miniSize = ShapeshifterGeometry.targetMascotSize(isCompact: true, isMini: true, canvasSize: CGSize(width: 18, height: 18), overhang: 0)
        check("Mini size is exactly 18x18", miniSize.width == 18 && miniSize.height == 18)

        let restingSize = ShapeshifterGeometry.targetMascotSize(isCompact: true, isMini: false, canvasSize: CGSize(width: 40, height: 72), overhang: 40)
        check("Resting notch size is clamped <= 26pt", restingSize.width <= 26 && restingSize.width >= 20)

        let expandedSize = ShapeshifterGeometry.targetMascotSize(isCompact: false, isMini: false, canvasSize: CGSize(width: 120, height: 120), overhang: 0)
        check("Expanded size fills card frame (120x120)", expandedSize.width == 120 && expandedSize.height == 120)

        print("ShapeshifterGeometryTests finished with \(failures) failures.")
        if failures > 0 { exit(1) }
    }
}
