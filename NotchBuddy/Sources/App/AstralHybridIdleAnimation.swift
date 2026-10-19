import Foundation
import CoreGraphics
import ImageIO

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
}

public final class AstralHybridAssets: @unchecked Sendable {
    public static let shared = AstralHybridAssets()
    private var cachedImage: CGImage?
    private let lock = NSLock()

    public func bodyImage(bundle: Bundle = .main) -> CGImage? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cachedImage { return cached }

        let candidates = [
            bundle.url(forResource: "astral-body-480", withExtension: "png", subdirectory: "Mascots/AstralHybrid"),
            bundle.url(forResource: "astral-body-240", withExtension: "png", subdirectory: "Mascots/AstralHybrid"),
            bundle.url(forResource: "astral-body-480", withExtension: "png"),
            bundle.url(forResource: "astral-body-240", withExtension: "png")
        ]

        for url in candidates.compactMap({ $0 }) {
            if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
               let img = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) {
                cachedImage = img
                return img
            }
        }
        return nil
    }

    public func setExplicitImage(_ img: CGImage) {
        lock.lock()
        defer { lock.unlock() }
        cachedImage = img
    }
}

public enum AstralHybridRenderer {
    public static func draw(
        in context: CGContext,
        size: CGSize,
        elapsed: TimeInterval,
        lookX: CGFloat = 0,
        lookY: CGFloat = 0,
        isSleeping: Bool = false,
        imageOverride: CGImage? = nil
    ) {
        guard size.width > 0, size.height > 0 else { return }
        let side = min(size.width, size.height)

        context.saveGState()

        // 1. Center & apply physics (Float Y + Squash & Stretch Breath)
        let floatY = AstralHybridMotion.floatY(at: elapsed, amp: Double(side * 0.04), isSleeping: isSleeping)
        let (scaleX, scaleY) = AstralHybridMotion.breathScale(at: elapsed, isSleeping: isSleeping)

        let cx = size.width / 2.0
        let cy = size.height / 2.0

        context.translateBy(x: cx, y: cy + CGFloat(floatY))
        context.scaleBy(x: CGFloat(scaleX), y: CGFloat(scaleY))
        context.translateBy(x: -cx, y: -cy)

        let drawRect = CGRect(x: (size.width - side) / 2.0, y: (size.height - side) / 2.0, width: side, height: side)

        // 2. Draw 3D Base Body Image
        let bodyImg = imageOverride ?? AstralHybridAssets.shared.bodyImage()
        if let bodyImg = bodyImg {
            context.saveGState()
            context.interpolationQuality = .high
            // Flip for top-left Canvas origin
            context.translateBy(x: drawRect.minX, y: drawRect.maxY)
            context.scaleBy(x: 1, y: -1)
            context.draw(bodyImg, in: CGRect(origin: .zero, size: drawRect.size))
            context.restoreGState()
        }

        // 3. Draw Procedural Expressive Eyes
        drawEyes(
            in: context,
            rect: drawRect,
            elapsed: elapsed,
            lookX: lookX,
            lookY: lookY,
            isSleeping: isSleeping
        )

        context.restoreGState()
    }

    private static func drawEyes(
        in context: CGContext,
        rect: CGRect,
        elapsed: TimeInterval,
        lookX: CGFloat,
        lookY: CGFloat,
        isSleeping: Bool
    ) {
        let side = rect.width
        let rx = side * 0.040
        let ry = side * 0.065

        let maxShiftX = rx * 0.45
        let maxShiftY = ry * 0.35
        let clampedLookX = max(-1.0, min(1.0, lookX))
        let clampedLookY = max(-1.0, min(1.0, lookY))
        let shiftX = clampedLookX * maxShiftX
        let shiftY = clampedLookY * maxShiftY

        let leftCx = rect.minX + side * 0.420 + shiftX
        let leftCy = rect.minY + side * 0.329 + shiftY
        let rightCx = rect.minX + side * 0.584 + shiftX
        let rightCy = rect.minY + side * 0.329 + shiftY

        context.saveGState()

        if isSleeping {
            // Sleeping eyes: soft glowing curved lines ∪ ∪
            context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
            context.setLineWidth(max(1.8, side * 0.024))
            context.setLineCap(.round)
            context.setShadow(offset: .zero, blur: max(2, side * 0.035), color: CGColor(red: 1, green: 1, blue: 1, alpha: 0.8))

            drawSleepingArc(in: context, cx: leftCx, cy: leftCy, rx: rx * 1.05)
            drawSleepingArc(in: context, cx: rightCx, cy: rightCy, rx: rx * 1.05)
        } else {
            // Awake eyes: glowing white pill capsules with squash-blinking
            let blink = AstralHybridMotion.blinkProgress(at: elapsed)
            let curRy = max(1.0, ry * (1.0 - blink))

            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.98))
            context.setShadow(offset: .zero, blur: max(2, side * 0.035), color: CGColor(red: 1, green: 1, blue: 1, alpha: 0.75))

            drawPill(in: context, cx: leftCx, cy: leftCy, rx: rx, ry: curRy)
            drawPill(in: context, cx: rightCx, cy: rightCy, rx: rx, ry: curRy)
        }

        context.restoreGState()
    }

    private static func drawPill(in context: CGContext, cx: CGFloat, cy: CGFloat, rx: CGFloat, ry: CGFloat) {
        let pillRect = CGRect(x: cx - rx, y: cy - ry, width: rx * 2.0, height: ry * 2.0)
        let path = CGPath(roundedRect: pillRect, cornerWidth: rx, cornerHeight: min(rx, ry), transform: nil)
        context.addPath(path)
        context.fillPath()
    }

    private static func drawSleepingArc(in context: CGContext, cx: CGFloat, cy: CGFloat, rx: CGFloat) {
        context.beginPath()
        context.addArc(center: CGPoint(x: cx, y: cy), radius: rx, startAngle: 0.15 * .pi, endAngle: 0.85 * .pi, clockwise: false)
        context.strokePath()
    }
}
