import Foundation
import CoreGraphics

public struct ExpandedRenderParams: Sendable, Equatable {
    public var bounds: CGRect
    public var action: MascotActionState
    public var shape: MascotShape
    public var provider: ProviderCoreType
    public var lookX: CGFloat
    public var lookY: CGFloat
    public var corePhase: Double

    public init(
        bounds: CGRect,
        action: MascotActionState = .idle,
        shape: MascotShape = .squircle,
        provider: ProviderCoreType = .antigravity,
        lookX: CGFloat = 0,
        lookY: CGFloat = 0,
        corePhase: Double = 0
    ) {
        self.bounds = bounds
        self.action = action
        self.shape = shape
        self.provider = provider
        self.lookX = max(-1.0, min(1.0, lookX))
        self.lookY = max(-1.0, min(1.0, lookY))
        self.corePhase = corePhase
    }
}

public final class ShapeshifterExpandedRenderer: @unchecked Sendable {
    public static func harmonicCoreYOffset(phase: Double, amplitude: CGFloat = 2.5) -> CGFloat {
        return CGFloat(sin(phase * 2.0 * .pi)) * amplitude
    }

    public static func coreColor(for provider: ProviderCoreType) -> (r: Double, g: Double, b: Double, hex: String) {
        switch provider {
        case .claude:      return (0.851, 0.467, 0.341, "#D97757") // Terracotta
        case .gemini:      return (0.306, 0.502, 0.933, "#4E80EE") // Blue-purple
        case .openai:      return (0.063, 0.639, 0.498, "#10A37F") // Emerald
        case .antigravity: return (0.545, 0.361, 0.965, "#8B5CF6") // Violet
        case .custom:      return (0.392, 0.824, 1.000, "#64D2FF") // Review Focus 3 Fallback
        }
    }

    public static func clampedDrawRect(in bounds: CGSize) -> CGRect {
        // Review Focus 4: 1:1 aspect ratio clamp & centering
        let side = min(bounds.width, bounds.height)
        let ox = (bounds.width - side) / 2.0
        let oy = (bounds.height - side) / 2.0
        return CGRect(x: ox, y: oy, width: side, height: side)
    }

    public static func drawGlassmorphicBody(in context: CGContext, rect: CGRect, shape: MascotShape, tintColor: CGColor) {
        context.saveGState()

        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = rect.width / 2.0

        // Subsurface Scattering Outer Glow
        context.setShadow(offset: .zero, blur: 12.0, color: tintColor)

        // Glassmorphic Body Gradient Fill
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let gradientColors = [
            CGColor(red: 0.95, green: 0.98, blue: 1.0, alpha: 0.45),
            CGColor(red: 0.80, green: 0.88, blue: 1.0, alpha: 0.20),
            CGColor(red: 0.65, green: 0.78, blue: 1.0, alpha: 0.08)
        ] as CFArray

        if let gradient = CGGradient(colorsSpace: colorSpace, colors: gradientColors, locations: [0.0, 0.6, 1.0]) {
            context.saveGState()
            switch shape {
            case .squircle:
                let corner = radius * 0.48
                context.addPath(CGPath(roundedRect: rect.insetBy(dx: 4, dy: 4), cornerWidth: corner, cornerHeight: corner, transform: nil))
            case .orb:
                context.addEllipse(in: rect.insetBy(dx: 4, dy: 4))
            case .flameWisp:
                let path = CGMutablePath()
                path.move(to: CGPoint(x: center.x, y: rect.minY + 4))
                path.addQuadCurve(to: CGPoint(x: rect.maxX - 4, y: center.y), control: CGPoint(x: rect.maxX, y: rect.minY + 8))
                path.addQuadCurve(to: CGPoint(x: center.x, y: rect.maxY - 4), control: CGPoint(x: rect.maxX - 4, y: rect.maxY))
                path.addQuadCurve(to: CGPoint(x: rect.minX + 4, y: center.y), control: CGPoint(x: rect.minX + 4, y: rect.maxY))
                path.addQuadCurve(to: CGPoint(x: center.x, y: rect.minY + 4), control: CGPoint(x: rect.minX, y: rect.minY + 8))
                context.addPath(path)
            }
            context.clip()
            context.drawRadialGradient(gradient, startCenter: CGPoint(x: center.x - radius * 0.2, y: center.y - radius * 0.2), startRadius: 0, endCenter: center, endRadius: radius, options: [])
            context.restoreGState()
        }

        // Specular Rim Light
        context.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.7))
        context.setLineWidth(1.8)
        context.strokeEllipse(in: rect.insetBy(dx: 5, dy: 5))

        context.restoreGState()
    }

    public static func drawFloatingCore(in context: CGContext, center: CGPoint, provider: ProviderCoreType, phase: Double) {
        context.saveGState()

        let yOffset = harmonicCoreYOffset(phase: phase, amplitude: 2.5)
        let coreCenter = CGPoint(x: center.x, y: center.y + 6 + yOffset)
        let color = coreColor(for: provider)
        let cgColor = CGColor(red: color.r, green: color.g, blue: color.b, alpha: 0.9)

        context.setShadow(offset: .zero, blur: 8.0, color: cgColor)
        context.setFillColor(cgColor)

        let coreRadius: CGFloat = 8.0
        switch provider {
        case .claude:
            // 4-pointed radiant sparkle star
            let path = CGMutablePath()
            path.move(to: CGPoint(x: coreCenter.x, y: coreCenter.y - coreRadius))
            path.addQuadCurve(to: CGPoint(x: coreCenter.x + coreRadius, y: coreCenter.y), control: CGPoint(x: coreCenter.x + 2, y: coreCenter.y - 2))
            path.addQuadCurve(to: CGPoint(x: coreCenter.x, y: coreCenter.y + coreRadius), control: CGPoint(x: coreCenter.x + 2, y: coreCenter.y + 2))
            path.addQuadCurve(to: CGPoint(x: coreCenter.x - coreRadius, y: coreCenter.y), control: CGPoint(x: coreCenter.x - 2, y: coreCenter.y + 2))
            path.addQuadCurve(to: CGPoint(x: coreCenter.x, y: coreCenter.y - coreRadius), control: CGPoint(x: coreCenter.x - 2, y: coreCenter.y - 2))
            context.addPath(path)
            context.fillPath()
        case .gemini:
            // Dual diamond spark
            let diamondW: CGFloat = coreRadius * 0.7
            let path = CGMutablePath()
            path.move(to: CGPoint(x: coreCenter.x, y: coreCenter.y - coreRadius))
            path.addLine(to: CGPoint(x: coreCenter.x + diamondW, y: coreCenter.y))
            path.addLine(to: CGPoint(x: coreCenter.x, y: coreCenter.y + coreRadius))
            path.addLine(to: CGPoint(x: coreCenter.x - diamondW, y: coreCenter.y))
            path.closeSubpath()
            context.addPath(path)
            context.fillPath()
        default:
            // Orbital sphere
            context.fillEllipse(in: CGRect(x: coreCenter.x - coreRadius, y: coreCenter.y - coreRadius, width: coreRadius * 2, height: coreRadius * 2))
        }

        context.restoreGState()
    }

    public static func drawActionProps(in context: CGContext, rect: CGRect, action: MascotActionState) {
        context.saveGState()
        context.setLineWidth(1.5)

        let center = CGPoint(x: rect.midX, y: rect.midY)
        switch action {
        case .writing:
            // Mini glowing tablet + stylus
            context.setStrokeColor(CGColor(red: 0.4, green: 0.8, blue: 1.0, alpha: 0.9))
            let tabletRect = CGRect(x: center.x - 12, y: rect.maxY - 18, width: 24, height: 14)
            context.stroke(tabletRect)
            // Stylus
            context.move(to: CGPoint(x: tabletRect.maxX - 4, y: tabletRect.minY - 4))
            context.addLine(to: CGPoint(x: tabletRect.maxX - 8, y: tabletRect.midY))
            context.strokePath()
        case .reading:
            // Open book silhouette
            context.setStrokeColor(CGColor(red: 1.0, green: 0.9, blue: 0.5, alpha: 0.9))
            let bookY = rect.maxY - 16
            context.move(to: CGPoint(x: center.x, y: bookY))
            context.addLine(to: CGPoint(x: center.x - 14, y: bookY - 4))
            context.addLine(to: CGPoint(x: center.x - 14, y: bookY + 8))
            context.addLine(to: CGPoint(x: center.x, y: bookY + 10))
            context.addLine(to: CGPoint(x: center.x + 14, y: bookY + 8))
            context.addLine(to: CGPoint(x: center.x + 14, y: bookY - 4))
            context.addLine(to: CGPoint(x: center.x, y: bookY))
            context.strokePath()
        case .thinking:
            // Spark question swirl above head
            context.setStrokeColor(CGColor(red: 0.9, green: 0.7, blue: 1.0, alpha: 0.9))
            context.addArc(center: CGPoint(x: center.x + 10, y: rect.minY + 10), radius: 4, startAngle: 0, endAngle: .pi * 1.5, clockwise: false)
            context.strokePath()
        case .error:
            // Angry cracked spark
            context.setStrokeColor(CGColor(red: 1.0, green: 0.25, blue: 0.2, alpha: 0.95))
            context.move(to: CGPoint(x: center.x - 6, y: rect.minY + 6))
            context.addLine(to: CGPoint(x: center.x + 6, y: rect.minY + 14))
            context.move(to: CGPoint(x: center.x + 6, y: rect.minY + 6))
            context.addLine(to: CGPoint(x: center.x - 6, y: rect.minY + 14))
            context.strokePath()
        case .sleeping:
            // Closed eyes & 'z' trail
            context.setStrokeColor(CGColor(red: 0.7, green: 0.8, blue: 0.9, alpha: 0.8))
            let zX = rect.maxX - 10
            let zY = rect.minY + 8
            context.move(to: CGPoint(x: zX - 4, y: zY - 4))
            context.addLine(to: CGPoint(x: zX, y: zY - 4))
            context.addLine(to: CGPoint(x: zX - 4, y: zY))
            context.addLine(to: CGPoint(x: zX, y: zY))
            context.strokePath()
        case .approval, .idle:
            break
        }

        context.restoreGState()
    }

    public static func draw(in context: CGContext, params: ExpandedRenderParams) {
        let clamped = clampedDrawRect(in: params.bounds.size)
        guard clamped.width >= 16 else { return }

        let rect = CGRect(
            x: params.bounds.origin.x + clamped.origin.x,
            y: params.bounds.origin.y + clamped.origin.y,
            width: clamped.width,
            height: clamped.height
        )

        let color = coreColor(for: params.provider)
        let tint = CGColor(red: color.r, green: color.g, blue: color.b, alpha: 0.6)

        // 1. 3D Glassmorphic Body
        drawGlassmorphicBody(in: context, rect: rect, shape: params.shape, tintColor: tint)

        // 2. Floating AI Core with Harmonic Oscillation
        let center = CGPoint(x: rect.midX, y: rect.midY)
        drawFloatingCore(in: context, center: center, provider: params.provider, phase: params.corePhase)

        // 3. Action Props Layer
        drawActionProps(in: context, rect: rect, action: params.action)
    }
}
