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
            Canvas { context, canvasSize in
                context.withCGContext { cg in
                    AstralHybridRenderer.draw(
                        in: cg,
                        size: canvasSize,
                        elapsed: elapsed,
                        lookX: lookX,
                        lookY: lookY,
                        isSleeping: isSleeping
                    )
                }
            }
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
            let size = ShapeshifterGeometry.targetMascotSize(
                isCompact: compact,
                isMini: false,
                canvasSize: geo.size,
                overhang: particleOverhang
            )
            let isSleeping = state.effectiveState == .sleeping

            AstralHybridIdleView(
                size: size,
                isPaused: paused || state.mode == .hidden,
                lookX: lookX,
                lookY: lookY,
                isSleeping: isSleeping
            )
            .frame(width: geo.size.width, height: geo.size.height)
            .offset(y: ShapeshifterGeometry.verticalOffset(particleOverhang: particleOverhang))
        }
    }
}
