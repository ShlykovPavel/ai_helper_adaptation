import Foundation
import CoreGraphics
import ImageIO

// MARK: - Astral Hybrid Form

public enum AstralHybridForm: String, CaseIterable, Sendable {
    case ghost
    case orb
    case cube
    case wisp

    public static func form(for stateName: String) -> AstralHybridForm {
        let normalized = stateName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "finished", "done", "success":
            return .orb
        case "approval", "question", "permission", "choose", "prompt":
            return .cube
        case "error", "ratelimit", "dizzy", "securitypanic", "deadtunnelprompt", "warning":
            return .wisp
        default:
            return .ghost
        }
    }

    public static func form<S: RawRepresentable>(for state: S) -> AstralHybridForm where S.RawValue == String {
        return form(for: state.rawValue)
    }
}

// MARK: - Astral Hybrid State

public enum AstralHybridState: String, CaseIterable, Sendable {
    case idle
    case working
    case thinking
    case searching
    case finished
    case approval
    case question
    case permission
    case error
    case ratelimit
    case dizzy
    case sleeping

    public var form: AstralHybridForm {
        return AstralHybridForm.form(for: self.rawValue)
    }

    public static func form(for state: AstralHybridState) -> AstralHybridForm {
        return state.form
    }

    public static func form(for stateName: String) -> AstralHybridForm {
        return AstralHybridForm.form(for: stateName)
    }

    public static func form<S: RawRepresentable>(for state: S) -> AstralHybridForm where S.RawValue == String {
        return AstralHybridForm.form(for: state.rawValue)
    }
}

// MARK: - Eye Geometry

public struct AstralHybridEyeGeometry: Sendable, Equatable {
    public let leftX: CGFloat
    public let leftY: CGFloat
    public let rightX: CGFloat
    public let rightY: CGFloat
    public let rx: CGFloat
    public let ry: CGFloat

    public static func geometry(for form: AstralHybridForm) -> AstralHybridEyeGeometry {
        switch form {
        case .ghost:
            return AstralHybridEyeGeometry(
                leftX: 0.420, leftY: 0.329,
                rightX: 0.584, rightY: 0.329,
                rx: 0.040, ry: 0.065
            )
        case .orb:
            return AstralHybridEyeGeometry(
                leftX: 200.0 / 480.0, leftY: 193.0 / 480.0,
                rightX: 280.0 / 480.0, rightY: 193.0 / 480.0,
                rx: 0.046, ry: 0.072
            )
        case .cube:
            return AstralHybridEyeGeometry(
                leftX: 196.0 / 480.0, leftY: 190.0 / 480.0,
                rightX: 281.0 / 480.0, rightY: 190.0 / 480.0,
                rx: 0.046, ry: 0.072
            )
        case .wisp:
            return AstralHybridEyeGeometry(
                leftX: 208.0 / 480.0, leftY: 252.0 / 480.0,
                rightX: 272.0 / 480.0, rightY: 252.0 / 480.0,
                rx: 0.042, ry: 0.064
            )
        }
    }
}

// MARK: - Motion Physics

public enum AstralHybridMotion {
    public static func floatY(at elapsed: TimeInterval, amp: Double = 3.5, speed: Double = 1.0, isSleeping: Bool = false) -> Double {
        guard elapsed.isFinite else { return 0 }
        let freq = isSleeping ? 1.2 : 2.0
        let actualAmp = isSleeping ? amp * 0.75 : amp
        return sin(elapsed * freq * speed) * actualAmp
    }

    public static func breathScale(at elapsed: TimeInterval, speed: Double = 1.0, isSleeping: Bool = false) -> (scaleX: Double, scaleY: Double) {
        guard elapsed.isFinite else { return (1.0, 1.0) }
        let freq = isSleeping ? 1.2 : 2.0
        let delta = (isSleeping ? 0.022 : 0.015) * cos(elapsed * freq * speed)
        return (scaleX: 1.0 + delta, scaleY: 1.0 - delta)
    }

    public static func blinkProgress(at elapsed: TimeInterval, period: Double = 4.2) -> Double {
        guard elapsed.isFinite, elapsed > 0 else { return 0 }
        let cycle = elapsed.truncatingRemainder(dividingBy: period)
        let blinkDuration = 0.18
        if cycle < blinkDuration {
            let progress = cycle / blinkDuration
            return (1.0 - cos(progress * 2.0 * .pi)) / 2.0
        }
        return 0
    }

    public static func bounceY(at elapsed: TimeInterval, amp: Double = 6.0) -> Double {
        guard elapsed.isFinite else { return 0 }
        return -abs(sin(elapsed * 4.0)) * amp
    }

    public static func tiltAngle(at elapsed: TimeInterval, maxAngle: Double = 0.12) -> Double {
        guard elapsed.isFinite else { return 0 }
        return sin(elapsed * 1.5) * maxAngle
    }

    public static func flameShake(at elapsed: TimeInterval, amp: Double = 1.5) -> (dx: Double, dy: Double) {
        guard elapsed.isFinite else { return (0, 0) }
        let dx = sin(elapsed * 25.0) * amp
        let dy = cos(elapsed * 30.0) * (amp * 0.8)
        return (dx, dy)
    }

    public static func flickerOffset(at elapsed: TimeInterval, amp: Double = 1.5) -> (dx: Double, dy: Double) {
        return flameShake(at: elapsed, amp: amp)
    }

    public static func searchGazeX(at elapsed: TimeInterval) -> Double {
        guard elapsed.isFinite else { return 0 }
        return sin(elapsed * 2.0) * 0.75
    }
}

// MARK: - Assets Management

public final class AstralHybridAssets: @unchecked Sendable {
    public static let shared = AstralHybridAssets()
    private var cache: [AstralHybridForm: CGImage] = [:]
    private let lock = NSLock()

    public func bodyImage(for form: AstralHybridForm = .ghost, bundle: Bundle = .main) -> CGImage? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[form] { return cached }

        let prefix: String
        switch form {
        case .ghost: prefix = "astral-body"
        case .orb:   prefix = "astral-orb"
        case .cube:  prefix = "astral-cube"
        case .wisp:  prefix = "astral-wisp"
        }

        var candidateURLs: [URL] = [
            bundle.url(forResource: "\(prefix)-480", withExtension: "png", subdirectory: "Mascots/AstralHybrid"),
            bundle.url(forResource: "\(prefix)-240", withExtension: "png", subdirectory: "Mascots/AstralHybrid"),
            bundle.url(forResource: "\(prefix)-480", withExtension: "png"),
            bundle.url(forResource: "\(prefix)-240", withExtension: "png")
        ].compactMap { $0 }

        if candidateURLs.isEmpty {
            let localPaths = [
                "NotchBuddy/Resources/Mascots/AstralHybrid/\(prefix)-480.png",
                "NotchBuddy/Resources/Mascots/AstralHybrid/\(prefix)-240.png",
                "Resources/Mascots/AstralHybrid/\(prefix)-480.png",
                "Resources/Mascots/AstralHybrid/\(prefix)-240.png"
            ]
            for path in localPaths {
                if FileManager.default.fileExists(atPath: path) {
                    candidateURLs.append(URL(fileURLWithPath: path))
                }
            }
        }

        for url in candidateURLs {
            if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
               let img = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) {
                cache[form] = img
                return img
            }
        }
        return nil
    }

    public func setExplicitImage(_ img: CGImage, for form: AstralHybridForm = .ghost) {
        lock.lock()
        defer { lock.unlock() }
        cache[form] = img
    }

    public func clearCache() {
        lock.lock()
        defer { lock.unlock() }
        cache.removeAll()
    }
}

// MARK: - Renderer

public enum AstralHybridRenderer {
    public static func draw(
        in context: CGContext,
        size: CGSize,
        elapsed: TimeInterval,
        form: AstralHybridForm = .ghost,
        stateName: String = "idle",
        lookX: CGFloat = 0,
        lookY: CGFloat = 0,
        isSleeping: Bool = false,
        imageOverride: CGImage? = nil
    ) {
        guard size.width > 0, size.height > 0 else { return }
        let side = min(size.width, size.height)

        let normalizedState = (isSleeping || stateName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "sleeping")
            ? "sleeping"
            : stateName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let effectiveForm: AstralHybridForm
        if form != .ghost {
            effectiveForm = form
        } else {
            let stateForm = AstralHybridForm.form(for: normalizedState)
            effectiveForm = (stateForm != .ghost) ? stateForm : form
        }

        let cx = size.width / 2.0
        let cy = size.height / 2.0
        let baseAmp = Double(side * 0.04)

        var transX: Double = 0.0
        var transY: Double = 0.0
        var rotation: Double = 0.0
        var scaleX: Double = 1.0
        var scaleY: Double = 1.0

        switch effectiveForm {
        case .orb:
            let bounceAmp = Double(side * 0.08)
            let bounceVal = AstralHybridMotion.bounceY(at: elapsed, amp: bounceAmp)
            transY = bounceVal
            let floorThreshold = -Double(side * 0.02)
            if bounceVal > floorThreshold {
                scaleX = 1.10
                scaleY = 0.90
            } else {
                scaleX = 0.96
                scaleY = 1.04
            }
            rotation = sin(elapsed * 2.0) * 0.03

        case .cube:
            transY = sin(elapsed * 1.5) * (baseAmp * 0.7)
            rotation = AstralHybridMotion.tiltAngle(at: elapsed, maxAngle: 0.12)
            scaleX = 1.0 + cos(elapsed * 1.5) * 0.01
            scaleY = 1.0 - cos(elapsed * 1.5) * 0.01

        case .wisp:
            let shake = AstralHybridMotion.flameShake(at: elapsed, amp: max(1.2, Double(side * 0.016)))
            transX = shake.dx
            transY = shake.dy
            rotation = sin(elapsed * 8.0) * 0.04
            scaleY = 1.0 + sin(elapsed * 15.0) * 0.04
            scaleX = 1.0 - sin(elapsed * 15.0) * 0.02

        case .ghost:
            if normalizedState == "sleeping" {
                transY = AstralHybridMotion.floatY(at: elapsed, amp: baseAmp, isSleeping: true)
                let breath = AstralHybridMotion.breathScale(at: elapsed, isSleeping: true)
                scaleX = breath.scaleX
                scaleY = breath.scaleY
                rotation = 0
            } else if normalizedState == "thinking" {
                transY = sin(elapsed * 1.5) * (baseAmp * 0.8)
                scaleX = 1.0 + cos(elapsed * 1.5) * 0.012
                scaleY = 1.0 - cos(elapsed * 1.5) * 0.012
                rotation = 0.06
            } else if normalizedState == "searching" {
                transY = sin(elapsed * 2.0) * baseAmp
                scaleX = 1.0 + cos(elapsed * 2.0) * 0.014
                scaleY = 1.0 - cos(elapsed * 2.0) * 0.014
                rotation = 0
            } else if normalizedState == "working" {
                transY = sin(elapsed * 2.5) * baseAmp
                let typingPulse = sin(elapsed * 18.0) * 0.012
                scaleY = 1.0 + typingPulse
                scaleX = 1.0 - typingPulse * 0.5
                rotation = 0
            } else {
                transY = AstralHybridMotion.floatY(at: elapsed, amp: baseAmp, isSleeping: false)
                let breath = AstralHybridMotion.breathScale(at: elapsed, isSleeping: false)
                scaleX = breath.scaleX
                scaleY = breath.scaleY
                rotation = 0
            }
        }

        var effectiveLookX = lookX
        var effectiveLookY = lookY

        if normalizedState == "sleeping" {
            effectiveLookX = 0
            effectiveLookY = 0
        } else if normalizedState == "searching" {
            effectiveLookX = CGFloat(AstralHybridMotion.searchGazeX(at: elapsed))
            effectiveLookY = CGFloat(cos(elapsed * 1.0) * 0.12)
        } else if normalizedState == "thinking" {
            effectiveLookX = 0.55 + max(-0.2, min(0.2, lookX * 0.2))
            effectiveLookY = -0.65 + max(-0.2, min(0.2, lookY * 0.2))
        } else {
            effectiveLookX = max(-1.0, min(1.0, lookX))
            effectiveLookY = max(-1.0, min(1.0, lookY))
        }

        context.saveGState()

        // 1. Center & apply physics
        context.translateBy(x: cx + CGFloat(transX), y: cy + CGFloat(transY))
        if rotation != 0 {
            context.rotate(by: CGFloat(rotation))
        }
        context.scaleBy(x: CGFloat(scaleX), y: CGFloat(scaleY))
        context.translateBy(x: -cx, y: -cy)

        let drawRect = CGRect(x: (size.width - side) / 2.0, y: (size.height - side) / 2.0, width: side, height: side)

        // 2. Background aura for special forms (Finished Orb & Error Wisp)
        if effectiveForm == .orb || normalizedState == "finished" {
            drawAura(in: context, center: CGPoint(x: cx, y: cy + side * 0.05), radius: side * 0.48, colors: [
                CGColor(red: 1.0, green: 0.84, blue: 0.04, alpha: 0.22),
                CGColor(red: 0.39, green: 0.82, blue: 1.0, alpha: 0.12),
                CGColor(red: 0.39, green: 0.82, blue: 1.0, alpha: 0.0)
            ], locations: [0.0, 0.6, 1.0])
        } else if effectiveForm == .wisp || normalizedState == "error" || normalizedState == "ratelimit" || normalizedState == "dizzy" {
            drawAura(in: context, center: CGPoint(x: cx, y: cy + side * 0.05), radius: side * 0.46, colors: [
                CGColor(red: 1.0, green: 0.27, blue: 0.23, alpha: 0.25),
                CGColor(red: 1.0, green: 0.62, blue: 0.04, alpha: 0.10),
                CGColor(red: 1.0, green: 0.27, blue: 0.23, alpha: 0.0)
            ], locations: [0.0, 0.7, 1.0])
        }

        // 3. Draw 3D Base Body Image
        let bodyImg = imageOverride ?? AstralHybridAssets.shared.bodyImage(for: effectiveForm)
        if let bodyImg = bodyImg {
            context.saveGState()
            context.interpolationQuality = .high
            // Flip for top-left Canvas origin
            context.translateBy(x: drawRect.minX, y: drawRect.maxY)
            context.scaleBy(x: 1, y: -1)
            context.draw(bodyImg, in: CGRect(origin: .zero, size: drawRect.size))
            context.restoreGState()
        } else {
            drawFallbackBody(in: context, rect: drawRect, form: effectiveForm)
        }

        // 4. Draw Procedural Expressive Eyes
        drawEyes(
            in: context,
            rect: drawRect,
            elapsed: elapsed,
            form: effectiveForm,
            stateName: normalizedState,
            lookX: effectiveLookX,
            lookY: effectiveLookY,
            isSleeping: (normalizedState == "sleeping")
        )

        context.restoreGState()
    }

    public static func draw(
        in context: CGContext,
        size: CGSize,
        elapsed: TimeInterval,
        lookX: CGFloat = 0,
        lookY: CGFloat = 0,
        isSleeping: Bool = false,
        imageOverride: CGImage? = nil
    ) {
        draw(
            in: context,
            size: size,
            elapsed: elapsed,
            form: .ghost,
            stateName: isSleeping ? "sleeping" : "idle",
            lookX: lookX,
            lookY: lookY,
            isSleeping: isSleeping,
            imageOverride: imageOverride
        )
    }

    private static func drawAura(
        in context: CGContext,
        center: CGPoint,
        radius: CGFloat,
        colors: [CGColor],
        locations: [CGFloat]
    ) {
        guard let colorSpace = colors.first?.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) else { return }
        guard let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: locations) else { return }
        context.saveGState()
        context.drawRadialGradient(
            gradient,
            startCenter: center,
            startRadius: 0,
            endCenter: center,
            endRadius: radius,
            options: [.drawsAfterEndLocation]
        )
        context.restoreGState()
    }

    private static func drawFallbackBody(in context: CGContext, rect: CGRect, form: AstralHybridForm) {
        let side = rect.width
        let cx = rect.midX
        let cy = rect.midY

        context.saveGState()
        context.setFillColor(CGColor(red: 0.6, green: 0.85, blue: 1.0, alpha: 0.5))
        context.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.35))
        context.setLineWidth(max(1.0, side * 0.015))

        switch form {
        case .orb:
            let r = side * 0.38
            context.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
            context.drawPath(using: .fillStroke)

        case .cube:
            let s = side * 0.70
            let corner = side * 0.16
            let cubeRect = CGRect(x: cx - s / 2, y: cy - s / 2, width: s, height: s)
            let path = CGPath(roundedRect: cubeRect, cornerWidth: corner, cornerHeight: corner, transform: nil)
            context.addPath(path)
            context.drawPath(using: .fillStroke)

        case .wisp:
            let r = side * 0.34
            context.addEllipse(in: CGRect(x: cx - r, y: cy - r + side * 0.08, width: r * 2, height: r * 2))
            context.drawPath(using: .fillStroke)

        case .ghost:
            context.beginPath()
            let r = side * 0.34
            context.addArc(center: CGPoint(x: cx, y: cy - side * 0.08), radius: r, startAngle: .pi, endAngle: 0, clockwise: false)
            context.addLine(to: CGPoint(x: cx + r, y: cy + side * 0.32))
            context.addLine(to: CGPoint(x: cx - r, y: cy + side * 0.32))
            context.closePath()
            context.drawPath(using: .fillStroke)
        }

        context.restoreGState()
    }

    private static func drawEyes(
        in context: CGContext,
        rect: CGRect,
        elapsed: TimeInterval,
        form: AstralHybridForm,
        stateName: String,
        lookX: CGFloat,
        lookY: CGFloat,
        isSleeping: Bool
    ) {
        let side = rect.width
        let geom = AstralHybridEyeGeometry.geometry(for: form)
        let rx = side * geom.rx
        let ry = side * geom.ry

        let maxShiftX = rx * 0.45
        let maxShiftY = ry * 0.35
        let shiftX = lookX * maxShiftX
        let shiftY = lookY * maxShiftY

        let leftCx = rect.minX + side * geom.leftX + shiftX
        let leftCy = rect.minY + side * geom.leftY + shiftY
        let rightCx = rect.minX + side * geom.rightX + shiftX
        let rightCy = rect.minY + side * geom.rightY + shiftY

        context.saveGState()

        let normalized = (isSleeping || stateName == "sleeping") ? "sleeping" : stateName

        if normalized == "sleeping" {
            // Sleeping eyes: soft glowing curved lines ∪ ∪
            context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
            context.setLineWidth(max(1.8, side * 0.024))
            context.setLineCap(.round)
            context.setShadow(offset: .zero, blur: max(2, side * 0.035), color: CGColor(red: 1, green: 1, blue: 1, alpha: 0.8))

            drawSleepingArc(in: context, cx: leftCx, cy: leftCy, rx: rx * 1.05)
            drawSleepingArc(in: context, cx: rightCx, cy: rightCy, rx: rx * 1.05)

        } else if form == .orb || normalized == "finished" {
            // Finished eyes: happy squinting arcs ^ ^ (cheerful upward arches)
            context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.98))
            context.setLineWidth(max(1.8, side * 0.026))
            context.setLineCap(.round)
            context.setShadow(offset: .zero, blur: max(2, side * 0.04), color: CGColor(red: 1.0, green: 0.94, blue: 0.63, alpha: 0.90))

            let arcRadius = rx * 1.08
            let arcLiftY = ry * 0.25

            drawHappyArc(in: context, cx: leftCx, cy: leftCy + arcLiftY, rx: arcRadius)
            drawHappyArc(in: context, cx: rightCx, cy: rightCy + arcLiftY, rx: arcRadius)

        } else if form == .wisp || normalized == "error" || normalized == "ratelimit" || normalized == "dizzy" {
            // Error / Dizzy eyes: dizzy spinning spirals @ @ with alert glow
            context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
            context.setLineWidth(max(1.8, side * 0.022))
            context.setLineCap(.round)
            context.setShadow(offset: .zero, blur: max(2, side * 0.04), color: CGColor(red: 1.0, green: 0.35, blue: 0.35, alpha: 0.95))

            let spinAngle = CGFloat(elapsed * 5.0)
            drawSpiralEye(in: context, cx: leftCx, cy: leftCy, maxR: rx * 1.15, angle: spinAngle)
            drawSpiralEye(in: context, cx: rightCx, cy: rightCy, maxR: rx * 1.15, angle: spinAngle)

        } else if form == .cube || normalized == "question" || normalized == "approval" || normalized == "permission" {
            // Questioning eyes: inquisitive asymmetry
            // Left eye normal pill, right eye raised slightly and enlarged (~1.22x)
            let blink = AstralHybridMotion.blinkProgress(at: elapsed)
            let blinkScale = CGFloat(max(0.04, 1.0 - blink))
            let leftRy = max(1.0, ry * blinkScale)
            let rightRy = max(1.0, (ry * 1.25) * blinkScale)
            let rightRx = rx * 1.22
            let raisedRightCy = rightCy - 0.025 * side

            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.98))
            context.setShadow(offset: .zero, blur: max(2, side * 0.035), color: CGColor(red: 1, green: 1, blue: 1, alpha: 0.8))

            drawPill(in: context, cx: leftCx, cy: leftCy, rx: rx, ry: leftRy)
            drawPill(in: context, cx: rightCx, cy: raisedRightCy, rx: rightRx, ry: rightRy)

        } else {
            // Awake / Idle / Working / Thinking / Searching: glowing white pill capsules with blinking
            let blink = AstralHybridMotion.blinkProgress(at: elapsed)
            let blinkScale = CGFloat(max(0.04, 1.0 - blink))
            let curRy = max(1.0, ry * blinkScale)
            let curRx = (normalized == "working") ? rx * 0.95 : rx

            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.98))
            context.setShadow(offset: .zero, blur: max(2, side * 0.035), color: CGColor(red: 1, green: 1, blue: 1, alpha: 0.75))

            drawPill(in: context, cx: leftCx, cy: leftCy, rx: curRx, ry: curRy)
            drawPill(in: context, cx: rightCx, cy: rightCy, rx: curRx, ry: curRy)
        }

        context.restoreGState()
    }

    private static func drawPill(in context: CGContext, cx: CGFloat, cy: CGFloat, rx: CGFloat, ry: CGFloat) {
        if ry <= rx {
            context.addEllipse(in: CGRect(x: cx - rx, y: cy - ry, width: rx * 2.0, height: ry * 2.0))
            context.fillPath()
        } else {
            let pillRect = CGRect(x: cx - rx, y: cy - ry, width: rx * 2.0, height: ry * 2.0)
            let path = CGPath(roundedRect: pillRect, cornerWidth: rx, cornerHeight: min(rx, ry), transform: nil)
            context.addPath(path)
            context.fillPath()
        }
    }

    private static func drawSleepingArc(in context: CGContext, cx: CGFloat, cy: CGFloat, rx: CGFloat) {
        context.beginPath()
        context.addArc(center: CGPoint(x: cx, y: cy), radius: rx, startAngle: 0.15 * .pi, endAngle: 0.85 * .pi, clockwise: false)
        context.strokePath()
    }

    private static func drawHappyArc(in context: CGContext, cx: CGFloat, cy: CGFloat, rx: CGFloat) {
        context.beginPath()
        context.addArc(center: CGPoint(x: cx, y: cy), radius: rx, startAngle: 1.15 * .pi, endAngle: 1.85 * .pi, clockwise: false)
        context.strokePath()
    }

    private static func drawSpiralEye(in context: CGContext, cx: CGFloat, cy: CGFloat, maxR: CGFloat, angle: CGFloat) {
        context.saveGState()
        context.translateBy(x: cx, y: cy)
        context.rotate(by: angle)
        context.beginPath()
        let coils: CGFloat = 2.2
        let steps = 40
        for i in 0...steps {
            let frac = CGFloat(i) / CGFloat(steps)
            let theta = frac * coils * 2.0 * .pi
            let r = frac * maxR
            let x = r * cos(theta)
            let y = r * sin(theta)
            if i == 0 {
                context.move(to: CGPoint(x: x, y: y))
            } else {
                context.addLine(to: CGPoint(x: x, y: y))
            }
        }
        context.strokePath()
        context.restoreGState()
    }
}
