import SwiftUI

struct AstralHybridIdleView: View {
    var size: CGSize
    var stateName: String
    var form: AstralHybridForm?
    var isPaused: Bool
    var lookX: CGFloat
    var lookY: CGFloat
    var isSleeping: Bool
    var slapElapsed: TimeInterval?

    @State private var clock = AstralIdleClock()

    init(
        size: CGSize,
        stateName: String = "idle",
        form: AstralHybridForm? = nil,
        isPaused: Bool = false,
        lookX: CGFloat = 0,
        lookY: CGFloat = 0,
        isSleeping: Bool = false,
        slapElapsed: TimeInterval? = nil
    ) {
        self.size = size
        self.stateName = stateName
        self.form = form
        self.isPaused = isPaused
        self.lookX = lookX
        self.lookY = lookY
        self.isSleeping = isSleeping
        self.slapElapsed = slapElapsed
    }

    var body: some View {
        TimelineView(.animation(paused: isPaused)) { _ in
            let elapsed = clock.elapsed(at: ProcessInfo.processInfo.systemUptime)
            Canvas { context, _ in
                context.withCGContext { cg in
                    let form = form ?? AstralHybridState.form(for: stateName)
                    AstralHybridRenderer.draw(
                        in: cg,
                        size: size,
                        elapsed: elapsed,
                        form: form,
                        stateName: stateName,
                        lookX: lookX,
                        lookY: lookY,
                        isSleeping: isSleeping,
                        slapElapsed: slapElapsed
                    )
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .frame(width: size.width, height: size.height)
        .accessibilityLabel(isSleeping ? "Astral спит" : (stateName == "idle" ? "Astral в состоянии покоя" : "Astral в состоянии \(stateName)"))
        .onAppear { clock.setRunning(!isPaused, at: ProcessInfo.processInfo.systemUptime) }
        .onChange(of: isPaused) { _, paused in
            clock.setRunning(!paused, at: ProcessInfo.processInfo.systemUptime)
        }
        .onDisappear { clock.setRunning(false, at: ProcessInfo.processInfo.systemUptime) }
    }
}

typealias AstralHybridView = AstralHybridIdleView

struct AstralHybridIdleHostView: View {
    @ObservedObject var state: AppState
    var particleOverhang: CGFloat
    var lookX: CGFloat
    var lookY: CGFloat
    var paused: Bool
    var isMini: Bool

    @State private var slapState = AstralHybridSlapState()

    init(
        state: AppState,
        particleOverhang: CGFloat = 0,
        lookX: CGFloat = 0,
        lookY: CGFloat = 0,
        paused: Bool = false,
        isMini: Bool = false
    ) {
        self.state = state
        self.particleOverhang = particleOverhang
        self.lookX = lookX
        self.lookY = lookY
        self.paused = paused
        self.isMini = isMini
    }

    var body: some View {
        GeometryReader { geo in
            let compact = ShapeshifterGeometry.isCompactMode(mode: state.mode, isMini: isMini)
            // 22pt in compact notch, 66pt in expanded card (matches Mochi's 58-62pt diameter), 13pt for mini pills
            let targetSize = isMini
                ? CGSize(width: 13, height: 13)
                : (compact ? CGSize(width: 22, height: 22) : CGSize(width: 66, height: 66))
            let isSleeping = state.effectiveState == .sleeping
            let yOffset = ShapeshifterGeometry.verticalOffset(particleOverhang: particleOverhang)

            let now = ProcessInfo.processInfo.systemUptime
            let currentSlap = slapState.elapsed(at: now)

            ZStack(alignment: .center) {
                AstralHybridIdleView(
                    size: targetSize,
                    stateName: state.effectiveState.rawValue,
                    isPaused: paused || state.mode == .hidden,
                    lookX: lookX,
                    lookY: lookY,
                    isSleeping: isSleeping,
                    slapElapsed: currentSlap
                )
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .offset(y: yOffset)
        }
        .onReceive(NotificationCenter.default.publisher(for: .triggerSlap)) { _ in
            guard !isMini, !paused, state.mode == .expanded else { return }
            slapState.trigger(at: ProcessInfo.processInfo.systemUptime)
        }
        .onChange(of: state.mode) { _, newMode in
            if newMode != .expanded {
                slapState.reset()
            }
        }
        .onChange(of: paused) { _, isPaused in
            if isPaused {
                slapState.reset()
            }
        }
    }
}

typealias AstralHybridHostView = AstralHybridIdleHostView

