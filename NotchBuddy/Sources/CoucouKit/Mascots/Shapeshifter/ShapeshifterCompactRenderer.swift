import Foundation
import CoreGraphics

public struct CompactRenderParams: Sendable, Equatable {
    public var size: CGSize
    public var lookX: CGFloat
    public var lookY: CGFloat
    public var shape: MascotShape
    public var provider: ProviderCoreType
    public var isPulsing: Bool

    public init(
        size: CGSize,
        lookX: CGFloat = 0,
        lookY: CGFloat = 0,
        shape: MascotShape = .squircle,
        provider: ProviderCoreType = .antigravity,
        isPulsing: Bool = false
    ) {
        self.size = size
        self.lookX = max(-1.0, min(1.0, lookX))
        self.lookY = max(-1.0, min(1.0, lookY))
        self.shape = shape
        self.provider = provider
        self.isPulsing = isPulsing
    }
}

public final class ShapeshifterCompactRenderer: @unchecked Sendable {
    public static func badgeColor(for provider: ProviderCoreType) -> (r: Double, g: Double, b: Double, hex: String) {
        switch provider {
        case .claude:      return (0.851, 0.467, 0.341, "#D97757") // Terracotta
        case .gemini:      return (0.306, 0.502, 0.933, "#4E80EE") // Blue-purple
        case .openai:      return (0.063, 0.639, 0.498, "#10A37F") // Emerald
        case .antigravity: return (0.545, 0.361, 0.965, "#8B5CF6") // Violet
        case .custom:      return (0.392, 0.824, 1.000, "#64D2FF") // Astral Cyan Fallback
        }
    }

    public static func clampedDrawRect(in bounds: CGSize) -> CGRect {
        let side = min(bounds.width, bounds.height)
        let ox = (bounds.width - side) / 2.0
        let oy = (bounds.height - side) / 2.0
        return CGRect(x: ox, y: oy, width: side, height: side)
    }

    public static func eyeOffsets(lookX: CGFloat, lookY: CGFloat, diameter: CGFloat) -> (left: CGPoint, right: CGPoint) {
        let clampedLookX = max(-1.0, min(1.0, lookX))
        let clampedLookY = max(-1.0, min(1.0, lookY))
        let maxOffset = diameter * 0.055
        let shiftX = clampedLookX * maxOffset
        let shiftY = -clampedLookY * maxOffset * 0.75
        let eyeDistance = diameter * 0.18
        return (
            left: CGPoint(x: -eyeDistance + shiftX, y: shiftY),
            right: CGPoint(x: eyeDistance + shiftX, y: shiftY)
        )
    }

    public static func specularHighlightOffsets(lookX: CGFloat, lookY: CGFloat, diameter: CGFloat) -> (
        leftPrimary: CGPoint,
        rightPrimary: CGPoint,
        leftSecondary: CGPoint,
        rightSecondary: CGPoint
    ) {
        let eyes = eyeOffsets(lookX: lookX, lookY: lookY, diameter: diameter)
        let eyeW = max(3.0, diameter * 0.14)
        let eyeH = max(4.5, diameter * 0.24)

        let primOffsetX = -eyeW * 0.24
        let primOffsetY = -eyeH * 0.24
        let secOffsetX = eyeW * 0.20
        let secOffsetY = eyeH * 0.20

        return (
            leftPrimary: CGPoint(x: eyes.left.x + primOffsetX, y: eyes.left.y + primOffsetY),
            rightPrimary: CGPoint(x: eyes.right.x + primOffsetX, y: eyes.right.y + primOffsetY),
            leftSecondary: CGPoint(x: eyes.left.x + secOffsetX, y: eyes.left.y + secOffsetY),
            rightSecondary: CGPoint(x: eyes.right.x + secOffsetX, y: eyes.right.y + secOffsetY)
        )
    }

    public static func cheekBlushOffsets(diameter: CGFloat) -> (left: CGPoint, right: CGPoint, radius: CGFloat) {
        let cheekDist = diameter * 0.26
        let cheekY = diameter * 0.14
        let radius = max(1.5, diameter * 0.08)
        return (
            left: CGPoint(x: -cheekDist, y: cheekY),
            right: CGPoint(x: cheekDist, y: cheekY),
            radius: radius
        )
    }

    public static func draw(in context: CGContext, params: CompactRenderParams) {
        let rect = clampedDrawRect(in: params.size)
        guard rect.width >= 8 else { return }

        context.saveGState()

        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = rect.width / 2.0
        let badge = badgeColor(for: params.provider)

        // 1. Subsurface Glowing Aura & Body Path
        let glowBlur: CGFloat = params.isPulsing ? 6.0 : 4.0
        let glowAlpha: CGFloat = params.isPulsing ? 0.90 : 0.65
        context.setShadow(offset: .zero, blur: glowBlur, color: CGColor(red: badge.r, green: badge.g, blue: badge.b, alpha: glowAlpha))

        let bodyRect = rect.insetBy(dx: 2.0, dy: 2.0)
        let bodyPath: CGPath
        switch params.shape {
        case .squircle:
            let corner = radius * 0.45
            bodyPath = CGPath(roundedRect: bodyRect, cornerWidth: corner, cornerHeight: corner, transform: nil)
        case .orb:
            bodyPath = CGPath(ellipseIn: bodyRect, transform: nil)
        case .flameWisp:
            let path = CGMutablePath()
            path.move(to: CGPoint(x: center.x, y: bodyRect.minY))
            path.addQuadCurve(to: CGPoint(x: bodyRect.maxX, y: center.y), control: CGPoint(x: bodyRect.maxX + 1, y: bodyRect.minY + 2))
            path.addQuadCurve(to: CGPoint(x: center.x, y: bodyRect.maxY), control: CGPoint(x: bodyRect.maxX, y: bodyRect.maxY))
            path.addQuadCurve(to: CGPoint(x: bodyRect.minX, y: center.y), control: CGPoint(x: bodyRect.minX, y: bodyRect.maxY))
            path.addQuadCurve(to: CGPoint(x: center.x, y: bodyRect.minY), control: CGPoint(x: bodyRect.minX - 1, y: bodyRect.minY + 2))
            bodyPath = path
        }

        // 2. Translucent Gradient-Filled Spirit Body
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let gradientColors = [
            CGColor(red: 0.941, green: 0.973, blue: 1.0, alpha: 0.75), // celestial white rgba(240, 248, 255, 0.75)
            CGColor(red: 0.75, green: 0.86, blue: 1.0, alpha: 0.45),
            CGColor(red: 0.549, green: 0.745, blue: 1.0, alpha: 0.25)  // spirit blue rgba(140, 190, 255, 0.25)
        ] as CFArray

        if let gradient = CGGradient(colorsSpace: colorSpace, colors: gradientColors, locations: [0.0, 0.55, 1.0]) {
            context.saveGState()
            context.addPath(bodyPath)
            context.clip()
            let lightCenter = CGPoint(x: center.x - radius * 0.2, y: center.y - radius * 0.2)
            context.drawRadialGradient(gradient, startCenter: lightCenter, startRadius: 0, endCenter: center, endRadius: radius, options: [])
            context.restoreGState()
        }

        // 3. Ethereal Flame Crown Tuft at Top Center
        let tuftTip = CGPoint(x: center.x, y: rect.minY + 0.8)
        let tuftBaseY = rect.minY + rect.height * 0.24
        let tuftHalfW = rect.width * 0.10
        let tuftPath = CGMutablePath()
        tuftPath.move(to: CGPoint(x: center.x - tuftHalfW, y: tuftBaseY))
        tuftPath.addQuadCurve(to: tuftTip, control: CGPoint(x: center.x - tuftHalfW * 0.8, y: rect.minY + 1.2))
        tuftPath.addQuadCurve(to: CGPoint(x: center.x + tuftHalfW, y: tuftBaseY), control: CGPoint(x: center.x + tuftHalfW * 0.8, y: rect.minY + 1.2))
        tuftPath.closeSubpath()

        context.saveGState()
        context.setFillColor(CGColor(red: 0.941, green: 0.973, blue: 1.0, alpha: 0.85))
        context.setShadow(offset: .zero, blur: 3.0, color: CGColor(red: badge.r, green: badge.g, blue: badge.b, alpha: 0.7))
        context.addPath(tuftPath)
        context.fillPath()
        context.restoreGState()

        // 4. Subtle Outer Rim Stroke
        context.setShadow(offset: .zero, blur: 0, color: nil)
        context.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.65))
        context.setLineWidth(1.0)
        context.addPath(bodyPath)
        context.strokePath()

        // 5. Soft Rosy Blush Cheeks (#FF85A1 at 0.40 alpha)
        let blush = cheekBlushOffsets(diameter: rect.width)
        let blushColor = CGColor(red: 1.0, green: 0.52, blue: 0.63, alpha: 0.40)
        context.setFillColor(blushColor)
        let blushW = blush.radius * 2.0
        let blushH = blush.radius * 1.3
        let leftBlushRect = CGRect(x: center.x + blush.left.x - blushW / 2, y: center.y + blush.left.y - blushH / 2, width: blushW, height: blushH)
        let rightBlushRect = CGRect(x: center.x + blush.right.x - blushW / 2, y: center.y + blush.right.y - blushH / 2, width: blushW, height: blushH)
        context.fillEllipse(in: leftBlushRect)
        context.fillEllipse(in: rightBlushRect)

        // 6. Big Glossy Dark Oval Eyes
        let offsets = eyeOffsets(lookX: params.lookX, lookY: params.lookY, diameter: rect.width)
        let eyeW = max(3.0, rect.width * 0.14)
        let eyeH = max(4.5, rect.width * 0.24)
        let eyeColor = CGColor(red: 0.08, green: 0.10, blue: 0.16, alpha: 0.95)
        context.setFillColor(eyeColor)

        let leftEyeRect = CGRect(x: center.x + offsets.left.x - eyeW / 2, y: center.y + offsets.left.y - eyeH / 2, width: eyeW, height: eyeH)
        let rightEyeRect = CGRect(x: center.x + offsets.right.x - eyeW / 2, y: center.y + offsets.right.y - eyeH / 2, width: eyeW, height: eyeH)
        context.fillEllipse(in: leftEyeRect)
        context.fillEllipse(in: rightEyeRect)

        // 7. Specular White Highlight Dots Inside Each Eye
        let highlights = specularHighlightOffsets(lookX: params.lookX, lookY: params.lookY, diameter: rect.width)
        let primR = max(0.7, eyeW * 0.25)
        let secR = max(0.4, eyeW * 0.14)

        // Primary highlights (top-left glossy reflection)
        context.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.95))
        let leftPrimRect = CGRect(x: center.x + highlights.leftPrimary.x - primR, y: center.y + highlights.leftPrimary.y - primR, width: primR * 2, height: primR * 2)
        let rightPrimRect = CGRect(x: center.x + highlights.rightPrimary.x - primR, y: center.y + highlights.rightPrimary.y - primR, width: primR * 2, height: primR * 2)
        context.fillEllipse(in: leftPrimRect)
        context.fillEllipse(in: rightPrimRect)

        // Secondary highlights (bottom-right softer bounce)
        context.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.70))
        let leftSecRect = CGRect(x: center.x + highlights.leftSecondary.x - secR, y: center.y + highlights.leftSecondary.y - secR, width: secR * 2, height: secR * 2)
        let rightSecRect = CGRect(x: center.x + highlights.rightSecondary.x - secR, y: center.y + highlights.rightSecondary.y - secR, width: secR * 2, height: secR * 2)
        context.fillEllipse(in: leftSecRect)
        context.fillEllipse(in: rightSecRect)

        // 8. Micro Provider Jewel Badge with Outer Glow
        let badgeSize = max(3.5, rect.width * 0.16)
        let badgeRect = CGRect(x: rect.maxX - badgeSize - 1, y: rect.minY + 1, width: badgeSize, height: badgeSize)
        context.setFillColor(CGColor(red: badge.r, green: badge.g, blue: badge.b, alpha: 1.0))
        context.setShadow(offset: .zero, blur: 2.5, color: CGColor(red: badge.r, green: badge.g, blue: badge.b, alpha: 0.9))
        context.fillEllipse(in: badgeRect)

        context.restoreGState()
    }
}
