import SwiftUI

/// Loaded/cropped once, never decoded on animation ticks.
@MainActor
private enum AstralGreetingResources {
    static let assets: AstralGreetingAssets? = {
        guard let url = Bundle.main.url(forResource: "rig", withExtension: "json",
                                        subdirectory: "Mascots/AstralGreeting") else { return nil }
        return try? AstralGreetingAssets.load(from: url.deletingLastPathComponent())
    }()
}

struct LaunchGreetingView: View {
    @ObservedObject var state: AppState
    @AppStorage(MascotSettings.selectedMascotKey) private var mascot = MascotType.shapeshifter.rawValue

    var body: some View {
        if MascotSettings.selectedMascot == .shapeshifter,
           let assets = AstralGreetingResources.assets {
            AstralGreetingView(assets: assets, notchHeight: state.notchHeight)
        } else {
            GreetingCanvasView(state: state, soundEnabled: mascot == MascotType.mochi.rawValue)
        }
    }
}

struct AstralGreetingView: View {
    let assets: AstralGreetingAssets
    var notchHeight: CGFloat
    @State private var startDate = Date()
    @State private var playback = AstralGreetingPlayback()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: playback.isPaused)) { timeline in
            let t = playback.isPaused ? playback.elapsed : timeline.date.timeIntervalSince(startDate)
            Canvas { context, size in
                // Keep the entire drawing below the physical notch and inside the existing panel.
                let top = max(34, notchHeight + 4)
                let side = min(128, max(0, size.height - top) * 384 / 342)
                let originY = top - side * 42 / 384
                context.withCGContext { cg in
                    assets.draw(in: cg, at: t,
                        rect: CGRect(x: (size.width - side) / 2, y: originY, width: side, height: side))
                }
            }
        }
        .accessibilityLabel("Astral приветствует вас")
        .task {
            startDate = Date()
            playback = AstralGreetingPlayback()
            do { try await Task.sleep(for: .seconds(AstralGreetingMotion.duration)) }
            catch { return }
            guard !Task.isCancelled, playback.advance(to: AstralGreetingMotion.duration) else { return }
            NotificationCenter.default.post(name: .greetComplete, object: nil)
        }
        .onReceive(NotificationCenter.default.publisher(for: .greetingInterrupt)) { _ in
            playback.interrupt(at: Date().timeIntervalSince(startDate))
        }
        .onDisappear {
            playback.interrupt(at: Date().timeIntervalSince(startDate))
        }
    }
}
