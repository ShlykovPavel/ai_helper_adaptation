import Foundation

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
