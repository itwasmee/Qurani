import SwiftUI
import QuraniKit

/// The 4-bar equalizer used both as the menubar icon and in the panel header.
/// `tint == nil` inherits the surrounding foreground color (template-style in the
/// menubar); pass a tint (e.g. the accent) to color it inside the glass panel.
struct MenuBarLabel: View {
    let isPlaying: Bool
    var tint: Color? = nil
    @State private var phase = false
    private let idle: [CGFloat] = [0.45, 0.8, 0.6, 0.35]

    var body: some View {
        HStack(spacing: 1.6) {
            ForEach(0..<4, id: \.self) { i in
                Capsule().frame(width: 2.4, height: 13 * barHeight(i))
            }
        }
        .frame(height: 15)
        .foregroundStyle(tint ?? Color.primary)
        .onAppear { if isPlaying { phase = true } }
        .onChange(of: isPlaying) { _, now in phase = now }   // react to play/pause after first appear
        .animation(isPlaying ? .easeInOut(duration: 0.5).repeatForever() : .default, value: phase)
    }

    private func barHeight(_ i: Int) -> CGFloat {
        guard isPlaying else { return idle[i] }
        let base: [CGFloat] = phase ? [1.0, 0.4, 0.9, 0.5] : [0.3, 1.0, 0.4, 0.85]
        return base[i]
    }
}

/// Observes the engine so the menubar icon animates when playback starts/stops
/// even while the panel is closed (`AppModel` does not republish engine changes).
struct EqualizerMenuBarLabel: View {
    @ObservedObject var engine: PlaybackEngine
    var body: some View { MenuBarLabel(isPlaying: engine.status == .playing) }
}
