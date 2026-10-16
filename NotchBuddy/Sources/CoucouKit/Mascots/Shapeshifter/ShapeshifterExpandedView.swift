import SwiftUI

public struct ShapeshifterExpandedView: View {
    public var size: CGSize
    public var action: MascotActionState
    public var shape: MascotShape
    public var provider: ProviderCoreType
    public var lookX: CGFloat
    public var lookY: CGFloat
    public var isPaused: Bool

    public init(
        size: CGSize = CGSize(width: 64, height: 64),
        action: MascotActionState = .idle,
        shape: MascotShape = .squircle,
        provider: ProviderCoreType = .antigravity,
        lookX: CGFloat = 0,
        lookY: CGFloat = 0,
        isPaused: Bool = false
    ) {
        self.size = size
        self.action = action
        self.shape = shape
        self.provider = provider
        self.lookX = lookX
        self.lookY = lookY
        self.isPaused = isPaused
    }

    public var body: some View {
        TimelineView(.animation(paused: isPaused)) { timeline in
            Canvas { context, canvasSize in
                context.withCGContext { cgContext in
                    let elapsed = isPaused ? 0 : timeline.date.timeIntervalSinceReferenceDate
                    let corePhase = (elapsed.truncatingRemainder(dividingBy: 2.0)) / 2.0
                    let params = ExpandedRenderParams(
                        bounds: CGRect(origin: .zero, size: canvasSize),
                        action: action,
                        shape: shape,
                        provider: provider,
                        lookX: lookX,
                        lookY: lookY,
                        corePhase: corePhase
                    )
                    ShapeshifterExpandedRenderer.draw(in: cgContext, params: params)
                }
            }
        }
        .frame(width: size.width, height: size.height)
    }
}
