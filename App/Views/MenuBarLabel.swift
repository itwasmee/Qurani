import SwiftUI
import QuraniKit

/// The 4-bar equalizer used both as the menubar icon and in the panel header.
/// `tint == nil` inherits the surrounding foreground color (template-style in the
/// menubar); pass a tint (e.g. the accent) to color it inside the glass panel.
struct MenuBarLabel: View {
    let isPlaying: Bool
    var tint: Color? = nil
    @State private var phase = false

    // The bars oscillate between a "low" and "high" endpoint set forever (easeInOut
    // .repeatForever autoreverses), so they're never perfectly still while the panel is
    // open. Idle is a gentle low-amplitude wave; playing is a taller, faster bounce.
    // Adjacent bars are anti-phase, giving the row a lively wave rather than a uniform pulse.
    private let idleLow:  [CGFloat] = [0.35, 0.50, 0.40, 0.52]
    private let idleHigh: [CGFloat] = [0.52, 0.38, 0.54, 0.40]
    private let playLow:  [CGFloat] = [0.30, 1.00, 0.40, 0.85]
    private let playHigh: [CGFloat] = [1.00, 0.40, 0.90, 0.50]

    var body: some View {
        HStack(spacing: 1.6) {
            ForEach(0..<4, id: \.self) { i in
                Capsule().frame(width: 2.4, height: 13 * barHeight(i))
            }
        }
        .frame(height: 15)
        .foregroundStyle(tint ?? Color.primary)
        // Kick off the perpetual wave as soon as the bars appear, and re-key it on
        // play/pause so the new cadence + amplitude take effect (a repeatForever animation
        // only re-commits when its `value` changes).
        .onAppear { phase = true }
        .onChange(of: isPlaying) { _, _ in phase.toggle() }
        .animation(.easeInOut(duration: isPlaying ? 0.42 : 0.9).repeatForever(), value: phase)
    }

    private func barHeight(_ i: Int) -> CGFloat {
        let low  = isPlaying ? playLow  : idleLow
        let high = isPlaying ? playHigh : idleHigh
        return phase ? high[i] : low[i]
    }
}

/// Observes the engine so the menubar icon animates when playback starts/stops
/// even while the panel is closed (`AppModel` does not republish engine changes).
///
/// Uses an SF Symbol (a template image), NOT the custom `MenuBarLabel` shape:
/// `MenuBarExtra` renders custom SwiftUI label views unreliably (they can come up
/// blank/clipped in the menubar), whereas a symbol always shows and auto-adapts to
/// the light/dark menubar. The custom bars are still used inside the glass panel.
struct EqualizerMenuBarLabel: View {
    @ObservedObject var engine: PlaybackEngine
    private var isPlaying: Bool { engine.status == .playing }
    var body: some View {
        Image(systemName: "waveform")
            // No `.dimInactiveLayers` — it makes the wave too subtle in the menubar. Plain
            // `.variableColor.iterative` cycles the layers clearly while `engine.status == .playing`.
            .symbolEffect(.variableColor.iterative, isActive: isPlaying)
    }
}
