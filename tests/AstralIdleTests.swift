import Foundation
import CoreGraphics
import ImageIO

@main
struct AstralIdleTests {
    static func main() throws {
        let resources = URL(fileURLWithPath: CommandLine.arguments[1])
        let original = URL(fileURLWithPath: CommandLine.arguments[2])
        let clip = try AstralIdleClip.load(from: resources)
        // The browser holds each genuine drawing for two of its 24fps ticks.
        for tick in 0..<96 {
            let t = (Double(tick) + 0.1) / 24
            precondition(clip.frameIndex(at: t) == tick / 2, "browser tick \(tick)")
            precondition(clip.frameIndex(at: t + 40) == tick / 2, "loop \(tick)")
        }
        precondition(clip.frameIndex(at: 3.999) == 47)
        precondition(clip.frameIndex(at: 4) == 0)
        precondition(clip.frameIndex(at: -1) == 0)
        // Catch wrong atlas origin/row/column or source image changes in any frame.
        for index in 0..<48 {
            let file = original.appendingPathComponent(String(format: "frames/frame-%03d.png", index))
            let source = CGImageSourceCreateWithURL(file as CFURL, nil)!
            let frame = CGImageSourceCreateImageAtIndex(source, 0, nil)!
            precondition(pixels(clip.frames[index]) == pixels(frame), "frame \(index) differs from design")
        }
        var clock = AstralIdleClock()
        clock.setRunning(true, at: 10)
        precondition(clock.elapsed(at: 11) == 1)
        clock.setRunning(false, at: 11.25)
        precondition(clock.elapsed(at: 200) == 1.25, "hidden time must not advance")
        clock.setRunning(false, at: 201)
        clock.setRunning(true, at: 250)
        precondition(clock.elapsed(at: 250.5) == 1.75, "resume from held frame")
        clock.setRunning(true, at: 251)
        precondition(clock.elapsed(at: 251) == 2.25, "duplicate resume must not reset")
        do {
            _ = try AstralIdleClip.load(from: resources.appendingPathComponent("missing"))
            preconditionFailure("missing assets must allow the existing fallback")
        } catch { }
        let context = CGContext(data: nil, width: 384, height: 384, bitsPerComponent: 8, bytesPerRow: 384 * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.translateBy(x: 0, y: 384)
        context.scaleBy(x: 1, y: -1)
        clip.draw(in: context, frame: 24, rect: CGRect(x: 0, y: 0, width: 384, height: 384))
        let rendered = context.makeImage()!
        precondition(pixels(rendered) == pixels(clip.frames[24]), "native image orientation")
        let url = URL(fileURLWithPath: CommandLine.arguments[3])
        let output = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(output, rendered, nil)
        precondition(CGImageDestinationFinalize(output))
        print("Astral native idle: 96 browser ticks, 48 exact PNG crops, 4-second looping, pause/resume, fallback and upright render passed")
    }

    static func pixels(_ image: CGImage) -> Data {
        let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Data(bytes: context.data!, count: image.width * image.height * 4)
    }
}
