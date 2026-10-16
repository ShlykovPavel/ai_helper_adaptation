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
        case .custom:      return (0.392, 0.824, 1.000, "#64D2FF") // Review Focus 3: Astral Cyan Fallback
        }
    }

    public static func clampedDrawRect(in bounds: CGSize) -> CGRect {
        // Review Focus 4: 1:1 aspect ratio clamping & centering
        let side = min(bounds.width, bounds.height)
        let ox = (bounds.width - side) / 2.0
        let oy = (bounds.height - side) / 2.0
        return CGRect(x: ox, y: oy, width: side, height: side)
    }

    public static func eyeOffsets(lookX: CGFloat, lookY: CGFloat, diameter: CGFloat) -> (left: CGPoint, right: CGPoint) {
        let clampedLookX = max(-1.0, min(1.0, lookX))
        let clampedLookY = max(-1.0, min(1.0, lookY))
        let maxOffset = diameter * 0.08
        let shiftX = clampedLookX * maxOffset
        let shiftY = -clampedLookY * maxOffset * 0.75
        let eyeDistance = diameter * 0.22
        return (
            left: CGPoint(x: -eyeDistance + shiftX, y: shiftY),
            right: CGPoint(x: eyeDistance + shiftX, y: shiftY)
        )
    }

    public static func draw(in context: CGContext, params: CompactRenderParams) {
        let rect = clampedDrawRect(in: params.size)
        guard rect.width >= 8 else { return }

        context.saveGState()

        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = rect.width / 2.0
        let badge = badgeColor(for: params.provider)

        // 1. Neon Glowing Silhouette
        let glowBlur: CGFloat = params.isPulsing ? 6.0 : 4.0
        let glowAlpha: CGFloat = params.isPulsing ? 0.95 : 0.75
        context.setShadow(offset: .zero, blur: glowBlur, color: CGColor(red: badge.r, green: badge.g, blue: badge.b, alpha: glowAlpha))
        context.setLineWidth(1.5)
        context.setStrokeColor(CGColor(red: 0.9, green: 0.95, blue: 1.0, alpha: 0.95))

        switch params.shape {
        case .squircle:
            let corner = radius * 0.45
            let path = CGPath(roundedRect: rect.insetBy(dx: 2, dy: 2), cornerWidth: corner, cornerHeight: corner, transform: nil)
            context.addPath(path)
        case .orb:
            context.addEllipse(in: rect.insetBy(dx: 2, dy: 2))
        case .flameWisp:
            let path = CGMutablePath()
            path.move(to: CGPoint(x: center.x, y: rect.minY + 2))
            path.addQuadCurve(to: CGPoint(x: rect.maxX - 2, y: center.y), control: CGPoint(x: rect.maxX, y: rect.minY + 4))
            path.addQuadCurve(to: CGPoint(x: center.x, y: rect.maxY - 2), control: CGPoint(x: rect.maxX - 2, y: rect.maxY))
            path.addQuadCurve(to: CGPoint(x: rect.minX + 2, y: center.y), control: CGPoint(x: rect.minX + 2, y: rect.maxY))
            path.addQuadCurve(to: CGPoint(x: center.x, y: rect.minY + 2), control: CGPoint(x: rect.minX, y: rect.minY + 4))
            context.addPath(path)
        }
        context.strokePath()

        // 2. High-contrast White Pill Eyes
        context.setShadow(offset: .zero, blur: 0, color: nil)
        context.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0))

        let offsets = eyeOffsets(lookX: params.lookX, lookY: params.lookY, diameter: rect.width)
        let eyeW = max(2.5, rect.width * 0.12)
        let eyeH = max(4.0, rect.width * 0.22)

        let leftEyeRect = CGRect(x: center.x + offsets.left.x - eyeW / 2, y: center.y + offsets.left.y - eyeH / 2, width: eyeW, height: eyeH)
        let rightEyeRect = CGRect(x: center.x + offsets.right.x - eyeW / 2, y: center.y + offsets.right.y - eyeH / 2, width: eyeW, height: eyeH)

        context.fillEllipse(in: leftEyeRect)
        context.fillEllipse(in: rightEyeRect)

        // 3. Tiny AI Provider Indicator Badge
        let badgeSize = max(3.5, rect.width * 0.16)
        let badgeRect = CGRect(x: rect.maxX - badgeSize - 1, y: rect.minY + 1, width: badgeSize, height: badgeSize)
        context.setFillColor(CGColor(red: badge.r, green: badge.g, blue: badge.b, alpha: 1.0))
        context.setShadow(offset: .zero, blur: 2.0, color: CGColor(red: badge.r, green: badge.g, blue: badge.b, alpha: 0.9))
        context.fillEllipse(in: badgeRect)

        context.restoreGState()
    }
}
