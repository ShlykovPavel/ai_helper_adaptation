import Foundation
import CoreGraphics
import ImageIO

/// Geometry and timing shared with the accepted two-layer browser prototype.
struct AstralGreetingRig: Decodable {
    struct Body: Decodable {
        let file: String
        let crop: [CGFloat]
        let headCenterX: CGFloat
        let shoulder: [CGFloat]
    }
    struct Paw: Decodable {
        let file: String
        let crop: [CGFloat]
        let pivot: [CGFloat]
    }
    let durationMs: Int
    let waveCount: Int
    let body: Body
    let paw: Paw
}

enum AstralGreetingMotion {
    static let duration: TimeInterval = 4

    struct Pose: Equatable {
        let angle: Double
        let opacity: Double
    }

    static func pose(at elapsed: TimeInterval) -> Pose {
        let t = min(duration, max(0, elapsed)) * 1000
        let idle = -125.0, raised = -6.0
        let angle: Double
        if t >= 650 && t < 1200 {
            angle = idle + (raised - idle) * smooth((t - 650) / 550)
        } else if t >= 1200 && t < 2500 {
            let progress = (t - 1200) / (1300.0 / 3)
            let cycle = min(2, Int(floor(progress)))
            let swing = (1 - cos(2 * .pi * (progress - Double(cycle)))) / 2
            angle = raised - [35.0, 30, 25][cycle] * swing
        } else if t >= 2500 && t < 3450 {
            angle = raised + (idle - raised) * smooth((t - 2500) / 950)
        } else {
            angle = idle
        }
        return Pose(angle: angle, opacity: smooth(t / 400))
    }

    private static func smooth(_ value: Double) -> Double {
        let t = min(1, max(0, value))
        return t * t * t * (t * (6 * t - 15) + 10)
    }
}

/// Completion is emitted once. Removing/interruption of the view cancels it.
struct AstralGreetingPlayback {
    private(set) var elapsed: TimeInterval = 0
    private(set) var isPaused = false

    mutating func advance(to time: TimeInterval) -> Bool {
        guard !isPaused else { return false }
        elapsed = min(AstralGreetingMotion.duration, max(elapsed, time))
        guard elapsed >= AstralGreetingMotion.duration else { return false }
        isPaused = true
        return true
    }

    mutating func interrupt(at time: TimeInterval) {
        guard !isPaused else { return }
        elapsed = min(AstralGreetingMotion.duration, max(0, time))
        isPaused = true
    }
}

struct AstralGreetingAssets {
    let rig: AstralGreetingRig
    let body: CGImage
    let paw: CGImage

    enum LoadError: Error { case invalidResource }

    static func load(from directory: URL) throws -> Self {
        let rig = try JSONDecoder().decode(AstralGreetingRig.self,
            from: Data(contentsOf: directory.appendingPathComponent("rig.json")))
        guard rig.durationMs == 4000, rig.waveCount == 3,
              rig.body.shoulder.count == 2, rig.paw.pivot.count == 2,
              rig.body.headCenterX.isFinite else { throw LoadError.invalidResource }

        func image(_ name: String, crop: [CGFloat], pivot: [CGFloat]) throws -> CGImage {
            guard crop.count == 4, crop.allSatisfy(\.isFinite), pivot.allSatisfy(\.isFinite),
                  let source = CGImageSourceCreateWithURL(directory.appendingPathComponent(name) as CFURL, nil),
                  let raw = CGImageSourceCreateImageAtIndex(source, 0,
                    [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
            else { throw LoadError.invalidResource }
            let rect = CGRect(x: crop[0], y: crop[1], width: crop[2] - crop[0], height: crop[3] - crop[1])
            guard rect.width > 0, rect.height > 0,
                  CGRect(x: 0, y: 0, width: raw.width, height: raw.height).contains(rect),
                  rect.contains(CGPoint(x: pivot[0], y: pivot[1])),
                  let cropped = raw.cropping(to: rect) else { throw LoadError.invalidResource }
            return cropped
        }
        return try Self(rig: rig,
            body: image(rig.body.file, crop: rig.body.crop, pivot: rig.body.shoulder),
            paw: image(rig.paw.file, crop: rig.paw.crop, pivot: rig.paw.pivot))
    }

    /// Draw into a top-left-origin context, as used by SwiftUI Canvas and the prototype.
    func draw(in context: CGContext, at elapsed: TimeInterval, rect: CGRect) {
        let pose = AstralGreetingMotion.pose(at: elapsed)
        let b = rig.body, p = rig.paw
        let bodyScale = 300 / (b.crop[3] - b.crop[1])
        let bodyRect = CGRect(x: 193 - (b.headCenterX - b.crop[0]) * bodyScale,
                              y: 42, width: CGFloat(body.width) * bodyScale, height: 300)
        let joint = CGPoint(x: bodyRect.minX + (b.shoulder[0] - b.crop[0]) * bodyScale,
                            y: bodyRect.minY + (b.shoulder[1] - b.crop[1]) * bodyScale)
        let pawScale = 90 / (p.crop[3] - p.crop[1])
        let pawRect = CGRect(x: -(p.pivot[0] - p.crop[0]) * pawScale,
                             y: -(p.pivot[1] - p.crop[1]) * pawScale,
                             width: CGFloat(paw.width) * pawScale, height: 90)

        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.minY)
        context.scaleBy(x: rect.width / 384, y: rect.height / 384)
        context.setAlpha(pose.opacity)
        context.interpolationQuality = .high
        drawUpright(body, in: bodyRect, context: context)
        context.translateBy(x: joint.x, y: joint.y)
        context.rotate(by: pose.angle * .pi / 180)
        drawUpright(paw, in: pawRect, context: context)
        context.restoreGState()
    }

    private func drawUpright(_ image: CGImage, in rect: CGRect, context: CGContext) {
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: rect.size))
        context.restoreGState()
    }
}
