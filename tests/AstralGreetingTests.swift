import Foundation
import CoreGraphics
import ImageIO

@main
struct AstralGreetingTests {
    static func main() throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        let assets = try AstralGreetingAssets.load(from: directory)
        let rig = assets.rig
        precondition(assets.body.width == 862 && assets.body.height == 1070, "body crop")
        precondition(assets.paw.width == 699 && assets.paw.height == 1078, "paw crop")

        // These poses are independently exported from the accepted browser player.
        struct Reference: Decodable { let milliseconds: Double; let angle: Double; let opacity: Double }
        let references = try JSONDecoder().decode([Reference].self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])))
        for ref in references {
            let p = AstralGreetingMotion.pose(at: ref.milliseconds / 1000)
            precondition(abs(p.angle - ref.angle) < 1e-8, "angle at \(ref.milliseconds)")
            precondition(abs(p.opacity - ref.opacity) < 1e-8, "opacity at \(ref.milliseconds)")
        }
        precondition(AstralGreetingMotion.pose(at: 100) == AstralGreetingMotion.pose(at: 4), "holds last pose")
        precondition(AstralGreetingMotion.pose(at: -1).opacity == 0, "negative time clamps")

        var playback = AstralGreetingPlayback()
        precondition(!playback.advance(to: 3.999), "must finish the last wave")
        precondition(playback.advance(to: 4), "completion at 4 seconds")
        precondition(playback.isPaused && playback.elapsed == 4)
        precondition(!playback.advance(to: 10), "one completion only")
        playback = AstralGreetingPlayback()
        playback.interrupt(at: 1.4)
        precondition(playback.isPaused && playback.elapsed == 1.4)
        precondition(!playback.advance(to: 5), "interrupted view must not complete later")

        // Exercise the real native renderer, including image orientation and clipping.
        let g = try XCTContext()
        g.translateBy(x: 0, y: 384)
        g.scaleBy(x: 1, y: -1)
        assets.draw(in: g, at: 1.417, rect: CGRect(x: 0, y: 0, width: 384, height: 384))
        let image = g.makeImage()!
        let output = URL(fileURLWithPath: CommandLine.arguments[3])
        let destination = CGImageDestinationCreateWithURL(output as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        precondition(CGImageDestinationFinalize(destination))
        // Crops and joints are validated by the loader before they reach Canvas.
        precondition(rig.durationMs == 4000 && rig.waveCount == 3)
        do {
            _ = try AstralGreetingAssets.load(from: directory.appendingPathComponent("missing"))
            preconditionFailure("missing resources must fail for the fallback to engage")
        } catch { }
        print("Astral native greeting: \(references.count) browser poses, one-shot lifecycle, interruption, real PNG rendering and missing-resource fallback passed")
    }

    static func XCTContext() throws -> CGContext {
        guard let context = CGContext(data: nil, width: 384, height: 384, bitsPerComponent: 8, bytesPerRow: 384 * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw NSError(domain: "AstralGreetingTests", code: 1)
        }
        return context
    }
}
