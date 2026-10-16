import SwiftUI

public struct ShapeshifterCompactView: View {
    public var size: CGSize
    public var lookX: CGFloat
    public var lookY: CGFloat
    public var shape: MascotShape
    public var provider: ProviderCoreType
    public var isPulsing: Bool

    public init(
        size: CGSize = CGSize(width: 24, height: 24),
        lookX: CGFloat = 0,
        lookY: CGFloat = 0,
        shape: MascotShape = .squircle,
        provider: ProviderCoreType = .antigravity,
        isPulsing: Bool = false
    ) {
        self.size = size
        self.lookX = lookX
        self.lookY = lookY
        self.shape = shape
        self.provider = provider
        self.isPulsing = isPulsing
    }

    public var body: some View {
        Canvas { context, canvasSize in
            context.withCGContext { cgContext in
                let params = CompactRenderParams(
                    size: canvasSize,
                    lookX: lookX,
                    lookY: lookY,
                    shape: shape,
                    provider: provider,
                    isPulsing: isPulsing
                )
                ShapeshifterCompactRenderer.draw(in: cgContext, params: params)
            }
        }
        .frame(width: size.width, height: size.height)
    }
}
