import SwiftUI

@MainActor
enum AstralIdleResources {
    /// Decode and cut all frames once. No image decoding or cropping on animation ticks.
    static let clip: AstralIdleClip? = {
        guard let url = Bundle.main.url(forResource: "atlas", withExtension: "json",
                                        subdirectory: "Mascots/AstralIdle") else { return nil }
        return try? AstralIdleClip.load(from: url.deletingLastPathComponent())
    }()
}

struct AstralIdleView: View {
    let clip: AstralIdleClip
    let size: CGSize
    var isPaused: Bool
    @State private var clock = AstralIdleClock()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / clip.metadata.nominalNewDrawingsPerSecond,
                                paused: isPaused)) { _ in
            let frame = clip.frameIndex(at: clock.elapsed(at: ProcessInfo.processInfo.systemUptime))
            Canvas { context, canvasSize in
                let side = min(canvasSize.width, canvasSize.height)
                context.withCGContext { cg in
                    clip.draw(in: cg, frame: frame,
                        rect: CGRect(x: (canvasSize.width - side) / 2,
                                     y: (canvasSize.height - side) / 2, width: side, height: side))
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .accessibilityLabel("Astral в состоянии покоя")
        .onAppear { clock.setRunning(!isPaused, at: ProcessInfo.processInfo.systemUptime) }
        .onChange(of: isPaused) { _, paused in
            clock.setRunning(!paused, at: ProcessInfo.processInfo.systemUptime)
        }
        .onDisappear { clock.setRunning(false, at: ProcessInfo.processInfo.systemUptime) }
    }
}

/// Preserve the existing notch size and overhang placement for both compact and expanded modes.
struct AstralIdleHostView: View {
    @ObservedObject var state: AppState
    let clip: AstralIdleClip
    var particleOverhang: CGFloat
    var paused: Bool

    var body: some View {
        GeometryReader { geo in
            let compact = ShapeshifterGeometry.isCompactMode(mode: state.mode, isMini: false)
            let size = ShapeshifterGeometry.targetMascotSize(isCompact: compact, isMini: false,
                canvasSize: geo.size, overhang: particleOverhang)
            AstralIdleView(clip: clip, size: size,
                           isPaused: paused || state.mode == .hidden)
                .frame(width: geo.size.width, height: geo.size.height)
                .offset(y: ShapeshifterGeometry.verticalOffset(particleOverhang: particleOverhang))
        }
    }
}
