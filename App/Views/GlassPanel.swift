import SwiftUI
import QuraniKit

struct GlassPanel: View {
    @ObservedObject var sources: SourcesStore
    @ObservedObject var engine: PlaybackEngine
    // Explore stores observed directly here so they republish into the panel — AppModel
    // does not forward its child stores' changes (same lesson as Plan 1's engine).
    @ObservedObject var catalog: CatalogStore
    @ObservedObject var favorites: FavoritesStore
    @ObservedObject var pool: MixPoolStore
    @ObservedObject var library: LibraryStore
    @ObservedObject var importer: LibraryImporter
    let surahs: [Surah]
    let play: (Reciter, Moshaf, Surah) -> Void
    let playLocal: (LocalTrack) -> Void
    /// Commit the Task 7 review sheet's confirmed imports → `AppModel.commitImports`.
    let commitImports: ([ReviewedImport]) -> Void
    @Environment(\.colorScheme) private var scheme
    // Read the persisted theme directly here: @AppStorage is a reactive DynamicProperty,
    // so changing it from the gear menu re-renders the panel LIVE. (An @AppStorage on
    // AppModel — an ObservableObject — would NOT republish on change.)
    @AppStorage("theme") private var themeRaw: String = Theme.system.rawValue
    @State private var tab = 0

    private var theme: Theme { Theme(rawValue: themeRaw) ?? .system }
    private var resolved: ResolvedTheme { theme.resolved(systemIsDark: scheme == .dark) }
    private var tokens: Tokens { Tokens.of(resolved) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 7) {
                    MenuBarLabel(isPlaying: engine.status == .playing, tint: tokens.accent)
                    Text("Qurani").font(.system(size: 13, weight: .semibold))
                }
                Spacer()
                settingsMenu
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
                switch tab {
                case 0:
                    LiveTabView(sources: sources, engine: engine, tokens: tokens)
                case 1:
                    ExploreTabView(catalog: catalog, favorites: favorites, pool: pool,
                                   engine: engine, surahs: surahs, tokens: tokens, play: play)
                case 2:
                    LibraryTabView(library: library, importer: importer, engine: engine,
                                   surahs: surahs, tokens: tokens, playLocal: playLocal)
                default:
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
        // Task 7: the tagger review sheet takes over the panel whenever imports await confirmation.
        // An overlay (not `.sheet`) — reliable inside a MenuBarExtra `.window` popover — and it
        // matches the mockup, which replaces the whole panel surface.
        .overlay {
            if !importer.pendingImports.isEmpty {
                TaggerReviewView(importer: importer, surahs: surahs, tokens: tokens, commit: commitImports)
            }
        }
        .preferredColorScheme(theme == .system ? nil : (resolved == .sahar ? .light : .dark))
    }

    // MARK: - Settings (theme + launch at login)

    private var settingsMenu: some View {
        Menu {
            Picker("Theme", selection: $themeRaw) {
                Text("System").tag(Theme.system.rawValue)
                Text("Sahar (Light)").tag(Theme.sahar.rawValue)
                Text("Noor (Dark)").tag(Theme.noor.rawValue)
                Text("Layl (Night)").tag(Theme.layl.rawValue)
            }
            Divider()
            Toggle("Launch at Login", isOn: launchAtLogin)
        } label: {
            Image(systemName: "gearshape").font(.system(size: 15)).foregroundStyle(tokens.muted)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    /// Reads/writes the actual SMAppService state. `register()` throws from unsigned /
    /// DerivedData builds — that's expected, so we swallow it (the toggle just reverts
    /// on the next read). See LoginItem.
    private var launchAtLogin: Binding<Bool> {
        Binding(
            get: { LoginItem.isEnabled },
            set: { on in
                do { try LoginItem.set(on) }
                catch { print("Qurani: launch-at-login change failed (expected when unsigned): \(error)") }
            }
        )
    }
}
