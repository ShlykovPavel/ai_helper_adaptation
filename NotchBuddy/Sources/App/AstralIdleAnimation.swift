import Foundation
import CoreGraphics
import ImageIO

/// Reads the saved v2 atlas contract, rather than the old 20-frame sprite-strip contract.
struct AstralIdleClip {
    struct Metadata: Decodable {
        struct Frame: Decodable {
            let id: Int
            let atlasRect: [Int]
        }
        let atlas: String
        let frameSizePx: [Int]
        let atlasSizePx: [Int]
        let uniqueDrawings: Int
        let displayFps: Double
        let displayTicks: Int
        let durationMs: Int
        let nominalNewDrawingsPerSecond: Double
        let ticks: [Int]
        let frames: [Frame]
    }

    let metadata: Metadata
    let frames: [CGImage]
    enum LoadError: Error { case invalidAtlas }

    static func load(from directory: URL) throws -> Self {
        let metadata = try JSONDecoder().decode(Metadata.self,
            from: Data(contentsOf: directory.appendingPathComponent("atlas.json")))
        guard metadata.frameSizePx.count == 2, metadata.atlasSizePx.count == 2,
              metadata.frameSizePx.allSatisfy({ $0 > 0 }),
              metadata.uniqueDrawings > 0, metadata.uniqueDrawings <= 256,
              metadata.frames.count == metadata.uniqueDrawings,
              metadata.displayFps.isFinite, metadata.displayFps > 0,
              metadata.displayTicks == metadata.ticks.count, !metadata.ticks.isEmpty,
              metadata.durationMs > 0,
              abs(Double(metadata.displayTicks) / metadata.displayFps * 1000 - Double(metadata.durationMs)) < 0.001,
              metadata.nominalNewDrawingsPerSecond.isFinite,
              metadata.nominalNewDrawingsPerSecond > 0,
              metadata.ticks.allSatisfy({ metadata.frames.indices.contains($0) }),
              let source = CGImageSourceCreateWithURL(directory.appendingPathComponent(metadata.atlas) as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0,
                [kCGImageSourceShouldCacheImmediately: true] as CFDictionary),
              image.width == metadata.atlasSizePx[0], image.height == metadata.atlasSizePx[1]
        else { throw LoadError.invalidAtlas }

        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let frames = try metadata.frames.enumerated().map { index, frame -> CGImage in
            guard frame.id == index, frame.atlasRect.count == 4 else { throw LoadError.invalidAtlas }
            let r = frame.atlasRect
            let rect = CGRect(x: r[0], y: r[1], width: r[2], height: r[3])
            guard r[2] == metadata.frameSizePx[0], r[3] == metadata.frameSizePx[1],
                  bounds.contains(rect), let crop = image.cropping(to: rect)
            else { throw LoadError.invalidAtlas }
            return crop
        }
        return Self(metadata: metadata, frames: frames)
    }

    func frameIndex(at elapsed: TimeInterval) -> Int {
        guard elapsed.isFinite, elapsed > 0 else { return metadata.ticks[0] }
        let duration = Double(metadata.durationMs) / 1000
        let phase = elapsed.truncatingRemainder(dividingBy: duration)
        let tick = min(metadata.ticks.count - 1, Int(floor(phase * metadata.displayFps)))
        return metadata.ticks[tick]
    }

    /// Canvas has a top-left origin; CGImage drawing needs a local vertical flip.
    func draw(in context: CGContext, frame index: Int, rect: CGRect) {
        guard frames.indices.contains(index) else { return }
        context.saveGState()
        context.interpolationQuality = .high
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(frames[index], in: CGRect(origin: .zero, size: rect.size))
        context.restoreGState()
    }
}

/// Accumulates only visible playback time, so resume never skips ahead through a hidden interval.
struct AstralIdleClock {
    private var accumulated: TimeInterval = 0
    private var anchor: TimeInterval?

    func elapsed(at now: TimeInterval) -> TimeInterval {
        accumulated + (anchor.map { max(0, now - $0) } ?? 0)
    }

    mutating func setRunning(_ running: Bool, at now: TimeInterval) {
        if running {
            if anchor == nil { anchor = now }
        } else if anchor != nil {
            accumulated = elapsed(at: now)
            anchor = nil
        }
    }
}
