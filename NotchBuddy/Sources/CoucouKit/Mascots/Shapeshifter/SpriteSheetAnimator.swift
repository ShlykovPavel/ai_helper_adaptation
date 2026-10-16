import Foundation
import CoreGraphics

public struct SpriteSheetConfig: Sendable {
    public var frameCount: Int
    public var fps: Double
    public var columns: Int
    public var rows: Int
    public var frameWidth: CGFloat
    public var frameHeight: CGFloat

    public init(frameCount: Int, fps: Double = 24.0, columns: Int, rows: Int = 1, frameWidth: CGFloat, frameHeight: CGFloat) {
        self.frameCount = max(1, frameCount)
        self.fps = max(1.0, fps)
        self.columns = max(1, columns)
        self.rows = max(1, rows)
        self.frameWidth = frameWidth
        self.frameHeight = frameHeight
    }

    public static func `default`(for action: MascotActionState) -> SpriteSheetConfig {
        switch action {
        case .idle:      return SpriteSheetConfig(frameCount: 20, fps: 24.0, columns: 20, frameWidth: 240, frameHeight: 240)
        case .writing:   return SpriteSheetConfig(frameCount: 24, fps: 24.0, columns: 24, frameWidth: 240, frameHeight: 240)
        case .reading:   return SpriteSheetConfig(frameCount: 20, fps: 24.0, columns: 20, frameWidth: 240, frameHeight: 240)
        case .thinking:  return SpriteSheetConfig(frameCount: 18, fps: 24.0, columns: 18, frameWidth: 240, frameHeight: 240)
        case .approval:  return SpriteSheetConfig(frameCount: 16, fps: 24.0, columns: 16, frameWidth: 240, frameHeight: 240)
        case .error:     return SpriteSheetConfig(frameCount: 16, fps: 24.0, columns: 16, frameWidth: 240, frameHeight: 240)
        case .sleeping:  return SpriteSheetConfig(frameCount: 16, fps: 16.0, columns: 16, frameWidth: 240, frameHeight: 240)
        }
    }
}

public final class SpriteSheetAnimator: @unchecked Sendable {
    public var config: SpriteSheetConfig
    public var isPaused: Bool = false
    public private(set) var currentAction: MascotActionState = .idle
    private var accumulatedTime: TimeInterval = 0

    public init(config: SpriteSheetConfig) {
        self.config = config
    }

    public var currentFrameIndex: Int {
        guard config.frameCount > 0 else { return 0 }
        let index = Int(floor(accumulatedTime * config.fps)) % config.frameCount
        return index >= 0 ? index : 0
    }

    @discardableResult
    public func update(dt: TimeInterval) -> Int {
        // Review Focus 2: When paused, skip time accumulation and math completely
        guard !isPaused, dt > 0 else { return currentFrameIndex }
        accumulatedTime += dt
        return currentFrameIndex
    }

    public func frameRect(for frameIndex: Int, imageSize: CGSize) -> CGRect {
        let validIndex = frameIndex % config.frameCount
        let col = validIndex % config.columns
        let row = validIndex / config.columns

        let x = CGFloat(col) * config.frameWidth
        let y = CGFloat(row) * config.frameHeight
        return CGRect(x: x, y: y, width: config.frameWidth, height: config.frameHeight)
    }

    public func setAction(_ action: MascotActionState) {
        if currentAction != action {
            currentAction = action
            config = SpriteSheetConfig.default(for: action)
            reset()
        }
    }

    public func reset() {
        accumulatedTime = 0
    }
}

public final class SpriteSheetLoader: @unchecked Sendable {
    public static let shared = SpriteSheetLoader()
    private var cache = [MascotActionState: CGImage]()
    private let lock = NSLock()

    public func image(for action: MascotActionState, bundle: Bundle = .main) -> CGImage? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[action] { return cached }
        let resourceName = "astral_\(action.rawValue)"
        guard let url = bundle.url(forResource: resourceName, withExtension: "png", subdirectory: "Mascots/Shapeshifter")
                ?? bundle.url(forResource: resourceName, withExtension: "png") else {
            return nil
        }
        guard let dataProvider = CGDataProvider(url: url as CFURL),
              let img = CGImage(pngDataProviderSource: dataProvider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else {
            return nil
        }
        cache[action] = img
        return img
    }

    public static func shouldUseVectorFallback(action: MascotActionState, bundle: Bundle = .main) -> Bool {
        return shared.image(for: action, bundle: bundle) == nil
    }

    public func clearCache() {
        lock.lock()
        defer { lock.unlock() }
        cache.removeAll()
    }
}
