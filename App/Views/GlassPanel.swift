import SwiftUI
import QuraniKit

struct GlassPanel: View {
    @ObservedObject var model: AppModel
    @ObservedObject var engine: PlaybackEngine   // observed directly so the header reacts to playback
    @Environment(\.colorScheme) private var scheme
    @State private var tab = 0

    private var resolved: ResolvedTheme { model.theme.resolved(systemIsDark: scheme == .dark) }
    private var tokens: Tokens { Tokens.of(resolved) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 7) {
                    MenuBarLabel(isPlaying: engine.status == .playing, tint: tokens.accent)
                    Text("Qurani").font(.system(size: 13, weight: .semibold))
                }
                Spacer()
                Image(systemName: "gearshape").font(.system(size: 15)).foregroundStyle(tokens.muted)
            }
            .padding(.horizontal, 15).padding(.top, 13).padding(.bottom, 8)
            .foregroundStyle(tokens.text)

            Picker("", selection: $tab) {
                Text("Live").tag(0); Text("Explore").tag(1); Text("Library").tag(2); Text("Mix").tag(3)
            }
            .pickerStyle(.segmented)
            .tint(tokens.accent)
            .padding(.horizontal, 12).padding(.bottom, 8)

            Group {
                if tab == 0 {
                    LiveTabView(sources: model.sources, engine: engine, tokens: tokens)
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "sparkles").font(.system(size: 22)).foregroundStyle(tokens.muted)
                        Text("Coming in a later plan").font(.system(size: 12)).foregroundStyle(tokens.muted)
                    }
                    .frame(height: 300).frame(maxWidth: .infinity)
                }
            }

            NowPlayingBar(engine: engine, tokens: tokens)
        }
        .frame(width: 344)
        .background {
            ZStack {
                VisualEffectBackground(material: .popover, blending: .behindWindow, isDark: tokens.isDark)
                tokens.glassTint
                RadialGradient(colors: [tokens.accent.opacity(0.14), .clear],
                               center: .top, startRadius: 0, endRadius: 220)
                    .allowsHitTesting(false)
            }
        }
        .preferredColorScheme(model.theme == .system ? nil : (model.theme == .sahar ? .light : .dark))
    }
}
