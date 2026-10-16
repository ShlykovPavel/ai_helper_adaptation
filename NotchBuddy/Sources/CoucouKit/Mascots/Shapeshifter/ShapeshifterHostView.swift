import SwiftUI

public struct ShapeshifterStateMapper {
    public static func mapAction(state: String) -> MascotActionState {
        switch state.lowercased() {
        case "working":                 return .writing
        case "searching":               return .reading
        case "thinking":                return .thinking
        case "permission", "question":  return .approval
        case "error":                   return .error
        case "sleeping":                return .sleeping
        default:                        return .idle
        }
    }
}

#if !STANDALONE_CLI
struct ShapeshifterHostView: View {
    @ObservedObject var state: AppState
    var particleOverhang: CGFloat = 0
    var lookOriginOverride: CGPoint? = nil
    var paused: Bool = false
    var isMini: Bool = false

    init(state: AppState, particleOverhang: CGFloat = 0, lookOriginOverride: CGPoint? = nil, paused: Bool = false, isMini: Bool = false) {
        self.state = state
        self.particleOverhang = particleOverhang
        self.lookOriginOverride = lookOriginOverride
        self.paused = paused
        self.isMini = isMini
    }

    public var body: some View {
        let isCompact = isMini || state.mode == .compact
        let action = ShapeshifterStateMapper.mapAction(state: state.effectiveState.rawValue)
        let provider = ProviderCoreType.from(pillId: state.focusTask?.id ?? state.mainPillId)
        let isPaused = paused || state.mode == .hidden

        Group {
            if isCompact {
                ShapeshifterCompactView(
                    size: CGSize(width: isMini ? 18 : 24, height: isMini ? 18 : 24),
                    lookX: 0,
                    lookY: 0,
                    shape: MascotSettings.shape,
                    provider: provider,
                    isPulsing: state.effectiveState == .thinking
                )
            } else {
                ShapeshifterExpandedView(
                    size: CGSize(width: 64, height: 64),
                    action: action,
                    shape: MascotSettings.shape,
                    provider: provider,
                    lookX: 0,
                    lookY: 0,
                    isPaused: isPaused
                )
            }
        }
    }
}
#endif
