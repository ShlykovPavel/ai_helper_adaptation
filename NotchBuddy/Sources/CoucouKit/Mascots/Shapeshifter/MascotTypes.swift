import Foundation
import CoreGraphics
#if !STANDALONE_CLI
import SwiftUI
#endif

public enum MascotType: String, CaseIterable, Sendable, Codable {
    case mochi = "mochi"
    case shapeshifter = "shapeshifter"
}

public enum MascotShape: String, CaseIterable, Sendable, Codable {
    case squircle = "squircle"
    case orb = "orb"
    case flameWisp = "flameWisp"
}

public enum MascotSizeVariant: Sendable, Equatable {
    case compact   // 20-32pt
    case expanded  // 44-66pt
    case hero      // 96-160pt
}

public enum ProviderCoreType: Sendable, Equatable {
    case claude
    case gemini
    case openai
    case antigravity
    case custom(String)

    public static func from(pillId: String?) -> ProviderCoreType {
        guard let id = pillId?.lowercased() else { return .antigravity }
        if id.contains("claude") { return .claude }
        if id.contains("gemini") { return .gemini }
        if id.contains("openai") || id.contains("gpt") { return .openai }
        if id.contains("antigravity") || id.contains("coucou") { return .antigravity }
        return .custom(id)
    }
}

public enum MascotActionState: String, CaseIterable, Sendable {
    case idle
    case writing
    case reading
    case thinking
    case approval
    case error
    case sleeping
}

public enum ShapeshifterGeometry: Sendable {
    public static func verticalOffset(particleOverhang: CGFloat) -> CGFloat {
        return particleOverhang / 2.0
    }

    #if STANDALONE_CLI
    public static func isCompactMode(mode: IslandMode, isMini: Bool) -> Bool {
        return isMini || mode == .compact || mode == .hidden
    }
    #else
    static func isCompactMode(mode: IslandMode, isMini: Bool) -> Bool {
        return isMini || mode == .compact || mode == .hidden
    }
    #endif

    public static func targetMascotSize(isCompact: Bool, isMini: Bool, canvasSize: CGSize, overhang: CGFloat) -> CGSize {
        if isMini {
            return CGSize(width: 18, height: 18)
        } else if isCompact {
            let availableHeight = max(0, canvasSize.height - overhang)
            let side = min(canvasSize.width, availableHeight > 0 ? availableHeight : canvasSize.height)
            let clamped = min(26.0, max(18.0, side))
            return CGSize(width: clamped, height: clamped)
        } else {
            let availableHeight = max(0, canvasSize.height - overhang)
            let side = min(canvasSize.width, availableHeight > 0 ? availableHeight : canvasSize.height)
            let clamped = max(44.0, side)
            return CGSize(width: clamped, height: clamped)
        }
    }
}
