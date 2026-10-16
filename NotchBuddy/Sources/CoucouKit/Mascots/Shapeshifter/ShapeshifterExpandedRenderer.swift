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

public struct ExpandedFaceGeometry: Sendable, Equatable {
    public var leftEyeCenter: CGPoint
    public var rightEyeCenter: CGPoint
    public var eyeSize: CGSize
    public var leftSpecularPrimary: CGPoint
    public var rightSpecularPrimary: CGPoint
    public var leftSpecularSecondary: CGPoint
    public var rightSpecularSecondary: CGPoint
    public var leftCheekCenter: CGPoint
    public var rightCheekCenter: CGPoint
    public var cheekSize: CGSize
    public var mouthCenter: CGPoint
    public var mouthWidth: CGFloat

    public init(
        leftEyeCenter: CGPoint,
        rightEyeCenter: CGPoint,
        eyeSize: CGSize,
        leftSpecularPrimary: CGPoint,
        rightSpecularPrimary: CGPoint,
        leftSpecularSecondary: CGPoint,
        rightSpecularSecondary: CGPoint,
        leftCheekCenter: CGPoint,
        rightCheekCenter: CGPoint,
        cheekSize: CGSize,
        mouthCenter: CGPoint,
        mouthWidth: CGFloat
    ) {
        self.leftEyeCenter = leftEyeCenter
        self.rightEyeCenter = rightEyeCenter
        self.eyeSize = eyeSize
        self.leftSpecularPrimary = leftSpecularPrimary
        self.rightSpecularPrimary = rightSpecularPrimary
        self.leftSpecularSecondary = leftSpecularSecondary
        self.rightSpecularSecondary = rightSpecularSecondary
        self.leftCheekCenter = leftCheekCenter
        self.rightCheekCenter = rightCheekCenter
        self.cheekSize = cheekSize
        self.mouthCenter = mouthCenter
        self.mouthWidth = mouthWidth
    }
}

public struct ExpandedActionPropsGeometry: Sendable, Equatable {
    public var propBounds: CGRect
    public var primaryAnchor: CGPoint
    public var secondaryAnchor: CGPoint
    public var strokeColorHex: String
    public var handLeft: CGPoint
    public var handRight: CGPoint

    public init(
        propBounds: CGRect = .zero,
        primaryAnchor: CGPoint = .zero,
        secondaryAnchor: CGPoint = .zero,
        strokeColorHex: String = "#64D2FF",
        handLeft: CGPoint = .zero,
        handRight: CGPoint = .zero
    ) {
        self.propBounds = propBounds
        self.primaryAnchor = primaryAnchor
        self.secondaryAnchor = secondaryAnchor
        self.strokeColorHex = strokeColorHex
        self.handLeft = handLeft
        self.handRight = handRight
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

    public static func faceGeometry(rect: CGRect, lookX: CGFloat, lookY: CGFloat) -> ExpandedFaceGeometry {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let diameter = min(rect.width, rect.height)

        let clampedLookX = max(-1.0, min(1.0, lookX))
        let clampedLookY = max(-1.0, min(1.0, lookY))
        let maxShift = diameter * 0.055
        let shiftX = clampedLookX * maxShift
        let shiftY = -clampedLookY * maxShift * 0.75

        let eyeDistance = diameter * 0.18
        let faceCenterY = center.y - diameter * 0.03
        let leftEye = CGPoint(x: center.x - eyeDistance + shiftX, y: faceCenterY + shiftY)
        let rightEye = CGPoint(x: center.x + eyeDistance + shiftX, y: faceCenterY + shiftY)

        let eyeW = max(5.0, diameter * 0.13)
        let eyeH = max(7.0, diameter * 0.20)
        let eyeSize = CGSize(width: eyeW, height: eyeH)

        // Specular highlights
        let primOffsetX = -eyeW * 0.24
        let primOffsetY = -eyeH * 0.24
        let secOffsetX = eyeW * 0.20
        let secOffsetY = eyeH * 0.20

        let leftSpecularPrimary = CGPoint(x: leftEye.x + primOffsetX, y: leftEye.y + primOffsetY)
        let rightSpecularPrimary = CGPoint(x: rightEye.x + primOffsetX, y: rightEye.y + primOffsetY)
        let leftSpecularSecondary = CGPoint(x: leftEye.x + secOffsetX, y: leftEye.y + secOffsetY)
        let rightSpecularSecondary = CGPoint(x: rightEye.x + secOffsetX, y: rightEye.y + secOffsetY)

        // Cheeks: positioned symmetrically below eyes
        let cheekDist = diameter * 0.26
        let cheekYOffset = diameter * 0.14
        let leftCheek = CGPoint(x: center.x - cheekDist + shiftX * 0.4, y: leftEye.y + cheekYOffset)
        let rightCheek = CGPoint(x: center.x + cheekDist + shiftX * 0.4, y: rightEye.y + cheekYOffset)
        let cheekSize = CGSize(width: max(4.0, diameter * 0.14), height: max(2.5, diameter * 0.09))

        // Mouth: centered between cheeks, positioned at or slightly below cheek Y
        let mouthCenter = CGPoint(x: center.x + shiftX * 0.5, y: leftCheek.y + 1.0)
        let mouthWidth = max(4.0, diameter * 0.10)

        return ExpandedFaceGeometry(
            leftEyeCenter: leftEye,
            rightEyeCenter: rightEye,
            eyeSize: eyeSize,
            leftSpecularPrimary: leftSpecularPrimary,
            rightSpecularPrimary: rightSpecularPrimary,
            leftSpecularSecondary: leftSpecularSecondary,
            rightSpecularSecondary: rightSpecularSecondary,
            leftCheekCenter: leftCheek,
            rightCheekCenter: rightCheek,
            cheekSize: cheekSize,
            mouthCenter: mouthCenter,
            mouthWidth: mouthWidth
        )
    }

    public static func actionPropsGeometry(rect: CGRect, action: MascotActionState) -> ExpandedActionPropsGeometry {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let diameter = min(rect.width, rect.height)

        switch action {
        case .writing:
            let tabletW = max(20.0, diameter * 0.32)
            let tabletH = max(12.0, diameter * 0.18)
            let tabletRect = CGRect(x: center.x - tabletW / 2, y: rect.maxY - tabletH - diameter * 0.04, width: tabletW, height: tabletH)
            let stylusStart = CGPoint(x: tabletRect.maxX - 4, y: tabletRect.minY - 5)
            let stylusEnd = CGPoint(x: tabletRect.maxX - 9, y: tabletRect.midY)
            let handL = CGPoint(x: tabletRect.minX + 3, y: tabletRect.midY)
            let handR = CGPoint(x: tabletRect.maxX - 5, y: tabletRect.minY)
            return ExpandedActionPropsGeometry(
                propBounds: tabletRect,
                primaryAnchor: stylusStart,
                secondaryAnchor: stylusEnd,
                strokeColorHex: "#64D2FF",
                handLeft: handL,
                handRight: handR
            )

        case .reading:
            let bookW = max(24.0, diameter * 0.36)
            let bookH = max(12.0, diameter * 0.18)
            let bookY = rect.maxY - bookH - diameter * 0.04
            let bookRect = CGRect(x: center.x - bookW / 2, y: bookY, width: bookW, height: bookH)
            let handL = CGPoint(x: bookRect.minX + 2, y: bookY + bookH * 0.5)
            let handR = CGPoint(x: bookRect.maxX - 2, y: bookY + bookH * 0.5)
            return ExpandedActionPropsGeometry(
                propBounds: bookRect,
                primaryAnchor: CGPoint(x: center.x, y: bookY),
                secondaryAnchor: CGPoint(x: center.x, y: bookY + bookH),
                strokeColorHex: "#FDE047",
                handLeft: handL,
                handRight: handR
            )

        case .thinking:
            let swirlSize = max(10.0, diameter * 0.18)
            let swirlRect = CGRect(x: center.x + diameter * 0.12, y: rect.minY + diameter * 0.08, width: swirlSize, height: swirlSize)
            let handL = CGPoint(x: center.x - diameter * 0.18, y: center.y + diameter * 0.16)
            let handR = CGPoint(x: center.x + diameter * 0.06, y: center.y + diameter * 0.16)
            return ExpandedActionPropsGeometry(
                propBounds: swirlRect,
                primaryAnchor: CGPoint(x: swirlRect.midX, y: swirlRect.midY),
                secondaryAnchor: handR,
                strokeColorHex: "#C084FC",
                handLeft: handL,
                handRight: handR
            )

        case .approval:
            let shieldW = max(14.0, diameter * 0.22)
            let shieldH = max(16.0, diameter * 0.24)
            let shieldRect = CGRect(x: center.x + diameter * 0.10, y: rect.maxY - shieldH - diameter * 0.06, width: shieldW, height: shieldH)
            let handL = CGPoint(x: center.x - diameter * 0.18, y: center.y + diameter * 0.18)
            let handR = CGPoint(x: center.x + diameter * 0.12, y: rect.maxY - shieldH * 0.6)
            return ExpandedActionPropsGeometry(
                propBounds: shieldRect,
                primaryAnchor: CGPoint(x: shieldRect.midX, y: shieldRect.minY),
                secondaryAnchor: CGPoint(x: shieldRect.midX, y: shieldRect.maxY),
                strokeColorHex: "#30D158",
                handLeft: handL,
                handRight: handR
            )

        case .error:
            let sparkSize = max(12.0, diameter * 0.18)
            let sparkRect = CGRect(x: center.x - sparkSize / 2, y: rect.minY + diameter * 0.06, width: sparkSize, height: sparkSize)
            let handL = CGPoint(x: center.x - diameter * 0.22, y: center.y + diameter * 0.12)
            let handR = CGPoint(x: center.x + diameter * 0.22, y: center.y + diameter * 0.12)
            return ExpandedActionPropsGeometry(
                propBounds: sparkRect,
                primaryAnchor: CGPoint(x: sparkRect.minX, y: sparkRect.minY),
                secondaryAnchor: CGPoint(x: sparkRect.maxX, y: sparkRect.maxY),
                strokeColorHex: "#EF4444",
                handLeft: handL,
                handRight: handR
            )

        case .sleeping:
            let zSize = max(12.0, diameter * 0.18)
            let zRect = CGRect(x: rect.maxX - zSize - diameter * 0.05, y: rect.minY + diameter * 0.06, width: zSize, height: zSize)
            let handL = CGPoint(x: center.x - diameter * 0.08, y: center.y + diameter * 0.20)
            let handR = CGPoint(x: center.x + diameter * 0.08, y: center.y + diameter * 0.20)
            return ExpandedActionPropsGeometry(
                propBounds: zRect,
                primaryAnchor: CGPoint(x: zRect.minX, y: zRect.minY),
                secondaryAnchor: CGPoint(x: zRect.maxX, y: zRect.maxY),
                strokeColorHex: "#94A3B8",
                handLeft: handL,
                handRight: handR
            )

        case .idle:
            let handL = CGPoint(x: center.x - diameter * 0.20, y: center.y + diameter * 0.18)
            let handR = CGPoint(x: center.x + diameter * 0.20, y: center.y + diameter * 0.18)
            return ExpandedActionPropsGeometry(
                propBounds: .zero,
                primaryAnchor: center,
                secondaryAnchor: center,
                strokeColorHex: "#64D2FF",
                handLeft: handL,
                handRight: handR
            )
        }
    }

    public static func drawGlassmorphicBody(in context: CGContext, rect: CGRect, shape: MascotShape, tintColor: CGColor) {
        context.saveGState()

        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = rect.width / 2.0

        // Subsurface Scattering Outer Glow
        context.setShadow(offset: .zero, blur: 12.0, color: tintColor)

        // Top Flickering Flame Crown Tuft
        let tuftTip = CGPoint(x: center.x, y: rect.minY + 2.0)
        let tuftBaseY = rect.minY + rect.height * 0.24
        let tuftHalfW = rect.width * 0.11
        let tuftPath = CGMutablePath()
        tuftPath.move(to: CGPoint(x: center.x - tuftHalfW, y: tuftBaseY))
        tuftPath.addQuadCurve(to: CGPoint(x: center.x - tuftHalfW * 0.3, y: rect.minY + rect.height * 0.09),
                              control: CGPoint(x: center.x - tuftHalfW * 0.85, y: rect.minY + rect.height * 0.14))
        tuftPath.addQuadCurve(to: tuftTip,
                              control: CGPoint(x: center.x - tuftHalfW * 0.15, y: rect.minY + 3.0))
        tuftPath.addQuadCurve(to: CGPoint(x: center.x + tuftHalfW * 0.3, y: rect.minY + rect.height * 0.09),
                              control: CGPoint(x: center.x + tuftHalfW * 0.15, y: rect.minY + 3.0))
        tuftPath.addQuadCurve(to: CGPoint(x: center.x + tuftHalfW, y: tuftBaseY),
                              control: CGPoint(x: center.x + tuftHalfW * 0.85, y: rect.minY + rect.height * 0.14))
        tuftPath.closeSubpath()

        context.saveGState()
        context.setFillColor(CGColor(red: 0.941, green: 0.973, blue: 1.0, alpha: 0.85))
        context.setShadow(offset: .zero, blur: 5.0, color: tintColor)
        context.addPath(tuftPath)
        context.fillPath()
        context.restoreGState()

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

    public static func drawExpressiveFace(in context: CGContext, face: ExpandedFaceGeometry, action: MascotActionState) {
        context.saveGState()

        // 1. Soft Rosy Blush Cheeks (#FF85A1 at 0.45 alpha)
        let blushColor = CGColor(red: 1.0, green: 0.521, blue: 0.631, alpha: 0.45)
        context.setFillColor(blushColor)
        let leftCheekRect = CGRect(
            x: face.leftCheekCenter.x - face.cheekSize.width / 2,
            y: face.leftCheekCenter.y - face.cheekSize.height / 2,
            width: face.cheekSize.width,
            height: face.cheekSize.height
        )
        let rightCheekRect = CGRect(
            x: face.rightCheekCenter.x - face.cheekSize.width / 2,
            y: face.rightCheekCenter.y - face.cheekSize.height / 2,
            width: face.cheekSize.width,
            height: face.cheekSize.height
        )
        context.fillEllipse(in: leftCheekRect)
        context.fillEllipse(in: rightCheekRect)

        // 2. Eyes
        let eyeColor = CGColor(red: 0.08, green: 0.10, blue: 0.18, alpha: 0.95)

        if action == .sleeping {
            // Cute closed sleeping eye arcs
            context.setStrokeColor(eyeColor)
            context.setLineWidth(max(2.0, face.eyeSize.width * 0.22))
            context.setLineCap(.round)

            let eyeR = face.eyeSize.width * 0.5
            let leftArc = CGMutablePath()
            leftArc.addArc(center: CGPoint(x: face.leftEyeCenter.x, y: face.leftEyeCenter.y - face.eyeSize.height * 0.05),
                           radius: eyeR, startAngle: 0.2, endAngle: .pi - 0.2, clockwise: false)
            context.addPath(leftArc)
            context.strokePath()

            let rightArc = CGMutablePath()
            rightArc.addArc(center: CGPoint(x: face.rightEyeCenter.x, y: face.rightEyeCenter.y - face.eyeSize.height * 0.05),
                            radius: eyeR, startAngle: 0.2, endAngle: .pi - 0.2, clockwise: false)
            context.addPath(rightArc)
            context.strokePath()
        } else {
            // Big dark glossy oval eyes
            context.setFillColor(eyeColor)
            let leftEyeRect = CGRect(
                x: face.leftEyeCenter.x - face.eyeSize.width / 2,
                y: face.leftEyeCenter.y - face.eyeSize.height / 2,
                width: face.eyeSize.width,
                height: face.eyeSize.height
            )
            let rightEyeRect = CGRect(
                x: face.rightEyeCenter.x - face.eyeSize.width / 2,
                y: face.rightEyeCenter.y - face.eyeSize.height / 2,
                width: face.eyeSize.width,
                height: face.eyeSize.height
            )
            context.fillEllipse(in: leftEyeRect)
            context.fillEllipse(in: rightEyeRect)

            // Primary bright white circular highlight dot in upper-left
            let primR = max(1.2, face.eyeSize.width * 0.25)
            context.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.95))
            let leftPrimRect = CGRect(
                x: face.leftSpecularPrimary.x - primR,
                y: face.leftSpecularPrimary.y - primR,
                width: primR * 2,
                height: primR * 2
            )
            let rightPrimRect = CGRect(
                x: face.rightSpecularPrimary.x - primR,
                y: face.rightSpecularPrimary.y - primR,
                width: primR * 2,
                height: primR * 2
            )
            context.fillEllipse(in: leftPrimRect)
            context.fillEllipse(in: rightPrimRect)

            // Secondary micro-dot in lower-right
            let secR = max(0.6, face.eyeSize.width * 0.13)
            context.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.70))
            let leftSecRect = CGRect(
                x: face.leftSpecularSecondary.x - secR,
                y: face.leftSpecularSecondary.y - secR,
                width: secR * 2,
                height: secR * 2
            )
            let rightSecRect = CGRect(
                x: face.rightSpecularSecondary.x - secR,
                y: face.rightSpecularSecondary.y - secR,
                width: secR * 2,
                height: secR * 2
            )
            context.fillEllipse(in: leftSecRect)
            context.fillEllipse(in: rightSecRect)
        }

        // 3. Expressive Mouth Arc Tailored to Action (smile, 'o', wavy, 'z')
        let mouthColor = CGColor(red: 0.12, green: 0.14, blue: 0.22, alpha: 0.85)
        context.setStrokeColor(mouthColor)
        context.setLineWidth(max(1.4, face.mouthWidth * 0.20))
        context.setLineCap(.round)
        context.setLineJoin(.round)

        let mw = face.mouthWidth
        let mc = face.mouthCenter

        switch action {
        case .idle, .approval:
            // Cute gentle smile arc
            let path = CGMutablePath()
            path.move(to: CGPoint(x: mc.x - mw * 0.5, y: mc.y - 0.5))
            path.addQuadCurve(to: CGPoint(x: mc.x + mw * 0.5, y: mc.y - 0.5),
                              control: CGPoint(x: mc.x, y: mc.y + mw * 0.45))
            context.addPath(path)
            context.strokePath()

        case .reading:
            // Focused small open 'o'
            let oRect = CGRect(x: mc.x - mw * 0.25, y: mc.y - mw * 0.20, width: mw * 0.5, height: mw * 0.55)
            context.strokeEllipse(in: oRect)

        case .thinking:
            // Curious small 'o' slightly pursed
            let oRect = CGRect(x: mc.x - mw * 0.20, y: mc.y - mw * 0.15, width: mw * 0.40, height: mw * 0.45)
            context.strokeEllipse(in: oRect)

        case .writing:
            // Cheerful focused smile
            let path = CGMutablePath()
            path.move(to: CGPoint(x: mc.x - mw * 0.45, y: mc.y - 0.5))
            path.addQuadCurve(to: CGPoint(x: mc.x + mw * 0.45, y: mc.y - 0.5),
                              control: CGPoint(x: mc.x, y: mc.y + mw * 0.35))
            context.addPath(path)
            context.strokePath()

        case .error:
            // Wavy mouth
            let path = CGMutablePath()
            path.move(to: CGPoint(x: mc.x - mw * 0.5, y: mc.y + 0.5))
            path.addCurve(to: CGPoint(x: mc.x + mw * 0.5, y: mc.y + 0.5),
                          control1: CGPoint(x: mc.x - mw * 0.2, y: mc.y - 2.0),
                          control2: CGPoint(x: mc.x + mw * 0.2, y: mc.y + 2.5))
            context.addPath(path)
            context.strokePath()

        case .sleeping:
            // Peaceful tiny smile
            let path = CGMutablePath()
            path.move(to: CGPoint(x: mc.x - mw * 0.3, y: mc.y))
            path.addQuadCurve(to: CGPoint(x: mc.x + mw * 0.3, y: mc.y),
                              control: CGPoint(x: mc.x, y: mc.y + mw * 0.25))
            context.addPath(path)
            context.strokePath()
        }

        context.restoreGState()
    }

    public static func drawExpressiveFace(in rect: CGRect, context: CGContext, face: ExpandedFaceGeometry, action: MascotActionState) {
        drawExpressiveFace(in: context, face: face, action: action)
    }

    public static func drawCuteHandsAndProps(in context: CGContext, rect: CGRect, action: MascotActionState) {
        context.saveGState()

        let props = actionPropsGeometry(rect: rect, action: action)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let diameter = min(rect.width, rect.height)
        let handRadius = max(3.0, diameter * 0.055)
        let handFill = CGColor(red: 0.94, green: 0.97, blue: 1.0, alpha: 0.85)
        let handStroke = CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.60)

        func drawHand(at pt: CGPoint) {
            context.saveGState()
            context.setFillColor(handFill)
            context.setStrokeColor(handStroke)
            context.setLineWidth(1.0)
            context.fillEllipse(in: CGRect(x: pt.x - handRadius, y: pt.y - handRadius, width: handRadius * 2, height: handRadius * 2))
            context.strokeEllipse(in: CGRect(x: pt.x - handRadius, y: pt.y - handRadius, width: handRadius * 2, height: handRadius * 2))
            context.restoreGState()
        }

        switch action {
        case .writing:
            // Mini glowing tablet
            let tabletRect = props.propBounds
            context.saveGState()
            context.setShadow(offset: .zero, blur: 4.0, color: CGColor(red: 0.392, green: 0.824, blue: 1.0, alpha: 0.8))
            context.setFillColor(CGColor(red: 0.12, green: 0.18, blue: 0.30, alpha: 0.75))
            context.setStrokeColor(CGColor(red: 0.392, green: 0.824, blue: 1.0, alpha: 0.95))
            context.setLineWidth(1.4)
            let tabletCorner: CGFloat = 3.0
            let tabletPath = CGPath(roundedRect: tabletRect, cornerWidth: tabletCorner, cornerHeight: tabletCorner, transform: nil)
            context.addPath(tabletPath)
            context.fillPath()
            context.addPath(tabletPath)
            context.strokePath()

            // Screen glow lines
            context.setStrokeColor(CGColor(red: 0.6, green: 0.9, blue: 1.0, alpha: 0.6))
            context.setLineWidth(1.0)
            context.move(to: CGPoint(x: tabletRect.minX + 4, y: tabletRect.midY - 2))
            context.addLine(to: CGPoint(x: tabletRect.maxX - 6, y: tabletRect.midY - 2))
            context.move(to: CGPoint(x: tabletRect.minX + 4, y: tabletRect.midY + 2))
            context.addLine(to: CGPoint(x: tabletRect.maxX - 10, y: tabletRect.midY + 2))
            context.strokePath()
            context.restoreGState()

            // Stylus
            context.saveGState()
            context.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.95))
            context.setLineWidth(1.6)
            context.setLineCap(.round)
            context.move(to: props.primaryAnchor)
            context.addLine(to: props.secondaryAnchor)
            context.strokePath()
            context.restoreGState()

            // Hands holding tablet and stylus
            drawHand(at: props.handLeft)
            drawHand(at: props.handRight)

        case .reading:
            let bookRect = props.propBounds
            let bookY = bookRect.minY
            context.saveGState()
            context.setShadow(offset: .zero, blur: 5.0, color: CGColor(red: 0.99, green: 0.88, blue: 0.28, alpha: 0.7))
            context.setStrokeColor(CGColor(red: 0.99, green: 0.88, blue: 0.28, alpha: 0.95))
            context.setFillColor(CGColor(red: 0.16, green: 0.18, blue: 0.24, alpha: 0.60))
            context.setLineWidth(1.4)

            // Open book pages
            let bookPath = CGMutablePath()
            bookPath.move(to: CGPoint(x: center.x, y: bookY + 2))
            bookPath.addLine(to: CGPoint(x: bookRect.minX, y: bookY))
            bookPath.addLine(to: CGPoint(x: bookRect.minX, y: bookRect.maxY))
            bookPath.addLine(to: CGPoint(x: center.x, y: bookRect.maxY + 2))
            bookPath.addLine(to: CGPoint(x: bookRect.maxX, y: bookRect.maxY))
            bookPath.addLine(to: CGPoint(x: bookRect.maxX, y: bookY))
            bookPath.closeSubpath()
            context.addPath(bookPath)
            context.fillPath()
            context.addPath(bookPath)
            context.strokePath()

            // Center spine line
            context.move(to: CGPoint(x: center.x, y: bookY + 2))
            context.addLine(to: CGPoint(x: center.x, y: bookRect.maxY + 2))
            context.strokePath()
            context.restoreGState()

            // Hands holding book edges
            drawHand(at: props.handLeft)
            drawHand(at: props.handRight)

        case .thinking:
            // Astral swirl and spark above head
            context.saveGState()
            context.setShadow(offset: .zero, blur: 6.0, color: CGColor(red: 0.75, green: 0.52, blue: 0.99, alpha: 0.8))
            context.setStrokeColor(CGColor(red: 0.75, green: 0.52, blue: 0.99, alpha: 0.95))
            context.setLineWidth(1.6)
            context.setLineCap(.round)

            let swirl = props.propBounds
            let arcPath = CGMutablePath()
            arcPath.addArc(center: CGPoint(x: swirl.midX, y: swirl.midY),
                           radius: swirl.width * 0.4, startAngle: 0.1, endAngle: .pi * 1.6, clockwise: false)
            context.addPath(arcPath)
            context.strokePath()

            // Small glowing star spark next to swirl
            context.setFillColor(CGColor(red: 1.0, green: 0.9, blue: 1.0, alpha: 0.95))
            let sparkC = CGPoint(x: swirl.maxX + 1, y: swirl.minY)
            let s: CGFloat = 3.0
            let starPath = CGMutablePath()
            starPath.move(to: CGPoint(x: sparkC.x, y: sparkC.y - s))
            starPath.addLine(to: CGPoint(x: sparkC.x + s * 0.3, y: sparkC.y))
            starPath.addLine(to: CGPoint(x: sparkC.x + s, y: sparkC.y))
            starPath.addLine(to: CGPoint(x: sparkC.x + s * 0.3, y: sparkC.y + s * 0.3))
            starPath.addLine(to: CGPoint(x: sparkC.x, y: sparkC.y + s))
            starPath.addLine(to: CGPoint(x: sparkC.x - s * 0.3, y: sparkC.y + s * 0.3))
            starPath.addLine(to: CGPoint(x: sparkC.x - s, y: sparkC.y))
            starPath.addLine(to: CGPoint(x: sparkC.x - s * 0.3, y: sparkC.y))
            starPath.closeSubpath()
            context.addPath(starPath)
            context.fillPath()
            context.restoreGState()

            // Left hand resting, right hand touching chin
            drawHand(at: props.handLeft)
            drawHand(at: props.handRight)

        case .approval:
            // Cute glowing shield / thumbs-up badge
            context.saveGState()
            context.setShadow(offset: .zero, blur: 5.0, color: CGColor(red: 0.19, green: 0.82, blue: 0.35, alpha: 0.8))
            context.setFillColor(CGColor(red: 0.19, green: 0.82, blue: 0.35, alpha: 0.85))
            context.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.95))
            context.setLineWidth(1.4)

            let shieldRect = props.propBounds
            let shieldPath = CGMutablePath()
            shieldPath.move(to: CGPoint(x: shieldRect.minX, y: shieldRect.minY))
            shieldPath.addLine(to: CGPoint(x: shieldRect.maxX, y: shieldRect.minY))
            shieldPath.addQuadCurve(to: CGPoint(x: shieldRect.midX, y: shieldRect.maxY),
                                    control: CGPoint(x: shieldRect.maxX, y: shieldRect.maxY - shieldRect.height * 0.2))
            shieldPath.addQuadCurve(to: CGPoint(x: shieldRect.minX, y: shieldRect.minY),
                                    control: CGPoint(x: shieldRect.minX, y: shieldRect.maxY - shieldRect.height * 0.2))
            shieldPath.closeSubpath()
            context.addPath(shieldPath)
            context.fillPath()
            context.addPath(shieldPath)
            context.strokePath()

            // Inner checkmark on shield
            context.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0))
            context.setLineWidth(1.6)
            context.setLineCap(.round)
            context.move(to: CGPoint(x: shieldRect.midX - 3.5, y: shieldRect.midY))
            context.addLine(to: CGPoint(x: shieldRect.midX - 0.5, y: shieldRect.midY + 3.0))
            context.addLine(to: CGPoint(x: shieldRect.midX + 4.0, y: shieldRect.midY - 2.5))
            context.strokePath()
            context.restoreGState()

            // Hands
            drawHand(at: props.handLeft)
            drawHand(at: props.handRight)

        case .error:
            // Angry cracked spark
            context.saveGState()
            context.setShadow(offset: .zero, blur: 6.0, color: CGColor(red: 0.94, green: 0.27, blue: 0.27, alpha: 0.85))
            context.setStrokeColor(CGColor(red: 0.94, green: 0.27, blue: 0.27, alpha: 0.95))
            context.setLineWidth(1.8)
            context.setLineCap(.round)
            context.move(to: props.primaryAnchor)
            context.addLine(to: props.secondaryAnchor)
            context.move(to: CGPoint(x: props.secondaryAnchor.x, y: props.primaryAnchor.y))
            context.addLine(to: CGPoint(x: props.primaryAnchor.x, y: props.secondaryAnchor.y))
            context.strokePath()
            context.restoreGState()

            // Hands raised in distress
            drawHand(at: props.handLeft)
            drawHand(at: props.handRight)

        case .sleeping:
            // Peaceful hands tucked together
            drawHand(at: props.handLeft)
            drawHand(at: props.handRight)

            // 'Z' trail
            context.saveGState()
            context.setStrokeColor(CGColor(red: 0.58, green: 0.64, blue: 0.72, alpha: 0.85))
            context.setLineWidth(1.4)
            context.setLineCap(.round)
            context.setLineJoin(.round)

            let zR = props.propBounds
            let zPath = CGMutablePath()
            zPath.move(to: CGPoint(x: zR.minX, y: zR.minY))
            zPath.addLine(to: CGPoint(x: zR.maxX, y: zR.minY))
            zPath.addLine(to: CGPoint(x: zR.minX, y: zR.maxY))
            zPath.addLine(to: CGPoint(x: zR.maxX, y: zR.maxY))
            context.addPath(zPath)
            context.strokePath()
            context.restoreGState()

        case .idle:
            // Cute little spirit hands resting at sides
            drawHand(at: props.handLeft)
            drawHand(at: props.handRight)
        }

        context.restoreGState()
    }

    public static func drawCuteHandsAndProps(in rect: CGRect, context: CGContext, action: MascotActionState) {
        drawCuteHandsAndProps(in: context, rect: rect, action: action)
    }

    public static func drawActionProps(in context: CGContext, rect: CGRect, action: MascotActionState) {
        drawCuteHandsAndProps(in: context, rect: rect, action: action)
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

        // 1. 3D Glassmorphic Body + Flickering Flame Crown Tuft
        drawGlassmorphicBody(in: context, rect: rect, shape: params.shape, tintColor: tint)

        // 2. Floating AI Core with Harmonic Oscillation
        let center = CGPoint(x: rect.midX, y: rect.midY)
        drawFloatingCore(in: context, center: center, provider: params.provider, phase: params.corePhase)

        // 3. Expressive Character Face (Big glossy eyes, specular dots, rosy blush, mouth arc)
        let face = faceGeometry(rect: rect, lookX: params.lookX, lookY: params.lookY)
        drawExpressiveFace(in: context, face: face, action: params.action)

        // 4. Cute Stubby Hands and Action Props
        drawCuteHandsAndProps(in: context, rect: rect, action: params.action)
    }
}
