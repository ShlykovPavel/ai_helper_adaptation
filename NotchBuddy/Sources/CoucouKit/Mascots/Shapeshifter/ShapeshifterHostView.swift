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

#if STANDALONE_CLI
public enum IslandMode: Sendable {
    case hidden
    case compact
    case expanded
}
#endif

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
        let isCompact = ShapeshifterGeometry.isCompactMode(mode: state.mode, isMini: isMini)
        let action = ShapeshifterStateMapper.mapAction(state: state.effectiveState.rawValue)
        let provider = ProviderCoreType.from(pillId: state.focusTask?.id ?? state.mainPillId)
        let isPaused = paused || state.mode == .hidden
        let yOffset = ShapeshifterGeometry.verticalOffset(particleOverhang: particleOverhang)

        GeometryReader { geo in
            let mascotSize = ShapeshifterGeometry.targetMascotSize(
                isCompact: isCompact,
                isMini: isMini,
                canvasSize: geo.size,
                overhang: particleOverhang
            )
            ZStack(alignment: .center) {
                if isCompact {
                    ShapeshifterCompactView(
                        size: mascotSize,
                        lookX: 0,
                        lookY: 0,
                        shape: MascotSettings.shape,
                        provider: provider,
                        isPulsing: state.effectiveState == .thinking
                    )
                } else {
                    ShapeshifterExpandedView(
                        size: mascotSize,
                        action: action,
                        shape: MascotSettings.shape,
                        provider: provider,
                        lookX: 0,
                        lookY: 0,
                        isPaused: isPaused
                    )
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .offset(y: yOffset)
        }
    }
}
#endif
