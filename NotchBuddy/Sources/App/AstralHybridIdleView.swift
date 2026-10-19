import SwiftUI

struct AstralHybridIdleView: View {
    var size: CGSize
    var isPaused: Bool
    var lookX: CGFloat
    var lookY: CGFloat
    var isSleeping: Bool

    @State private var clock = AstralIdleClock()

    init(
        size: CGSize,
        isPaused: Bool = false,
        lookX: CGFloat = 0,
        lookY: CGFloat = 0,
        isSleeping: Bool = false
    ) {
        self.size = size
        self.isPaused = isPaused
        self.lookX = lookX
        self.lookY = lookY
        self.isSleeping = isSleeping
    }

    var body: some View {
        TimelineView(.animation(paused: isPaused)) { _ in
            let elapsed = clock.elapsed(at: ProcessInfo.processInfo.systemUptime)
            Canvas { context, _ in
                context.withCGContext { cg in
                    AstralHybridRenderer.draw(
                        in: cg,
                        size: size,
                        elapsed: elapsed,
                        lookX: lookX,
                        lookY: lookY,
                        isSleeping: isSleeping
                    )
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .frame(width: size.width, height: size.height)
        .accessibilityLabel(isSleeping ? "Astral спит" : "Astral в состоянии покоя")
        .onAppear { clock.setRunning(!isPaused, at: ProcessInfo.processInfo.systemUptime) }
        .onChange(of: isPaused) { _, paused in
            clock.setRunning(!paused, at: ProcessInfo.processInfo.systemUptime)
        }
        .onDisappear { clock.setRunning(false, at: ProcessInfo.processInfo.systemUptime) }
    }
}

struct AstralHybridIdleHostView: View {
    @ObservedObject var state: AppState
    var particleOverhang: CGFloat
    var lookX: CGFloat
    var lookY: CGFloat
    var paused: Bool

    init(
        state: AppState,
        particleOverhang: CGFloat,
        lookX: CGFloat = 0,
        lookY: CGFloat = 0,
        paused: Bool
    ) {
        self.state = state
        self.particleOverhang = particleOverhang
        self.lookX = lookX
        self.lookY = lookY
        self.paused = paused
    }

    var body: some View {
        GeometryReader { geo in
            let compact = ShapeshifterGeometry.isCompactMode(mode: state.mode, isMini: false)
            // Sized to comfortably fit inside notch (22pt) and expanded card (52pt) without clipping
            let targetSize = compact
                ? CGSize(width: 22, height: 22)
                : CGSize(width: 52, height: 52)
            let isSleeping = state.effectiveState == .sleeping
            let yOffset = ShapeshifterGeometry.verticalOffset(particleOverhang: particleOverhang)

            ZStack(alignment: .center) {
                AstralHybridIdleView(
                    size: targetSize,
                    isPaused: paused || state.mode == .hidden,
                    lookX: lookX,
                    lookY: lookY,
                    isSleeping: isSleeping
                )
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .offset(y: yOffset)
        }
    }
}
