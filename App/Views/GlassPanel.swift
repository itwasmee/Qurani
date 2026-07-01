import SwiftUI
import AppKit
import QuraniKit

struct GlassPanel: View {
    /// The root model — observed so the Mix session state it owns (`isMixing` / `mixUpNext`) drives
    /// the now-playing ⤮ MIX chip + "up next" hint live. The Mix tab also calls `buildPool`/`startMix`
    /// on it and derives its own `@ObservedObject` child stores (AppModel doesn't forward those).
    @ObservedObject var model: AppModel
    @ObservedObject var sources: SourcesStore
    @ObservedObject var engine: PlaybackEngine
    // Explore stores observed directly here so they republish into the panel — AppModel
    // does not forward its child stores' changes (same lesson as Plan 1's engine).
    @ObservedObject var catalog: CatalogStore
    @ObservedObject var favorites: FavoritesStore
    @ObservedObject var pool: MixPoolStore
    @ObservedObject var library: LibraryStore
    @ObservedObject var importer: LibraryImporter
    @ObservedObject var settings: SettingsStore
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
    /// Drives the full-panel Settings overlay opened from the header gear (and the ••• menu's
    /// "Settings…"). Replaces the old inline theme/login gear menu — Settings now owns those.
    @State private var showingSettings = false

    private var theme: Theme { Theme(rawValue: themeRaw) ?? .system }
    private var resolved: ResolvedTheme { theme.resolved(systemIsDark: scheme == .dark) }
    private var tokens: Tokens { Tokens.of(resolved) }

    /// Resolve `model.mixUpNext` (surah number + member name) into the display strings the
    /// now-playing "up next" hint renders — the surah's Arabic name comes from this panel's `surahs`.
    private var upNextDisplay: (memberName: String, surahName: String)? {
        guard let next = model.mixUpNext else { return nil }
        let name = surahs.first { $0.number == next.surah }?.nameAr ?? "Surah \(next.surah)"
        return (memberName: next.memberName, surahName: name)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 7) {
                    MenuBarLabel(isPlaying: engine.status == .playing, tint: tokens.accent)
                    Text("Qurani").font(.system(size: 13, weight: .semibold))
                }
                Spacer()
                HStack(spacing: 8) {
                    commandsMenu
                    settingsButton
                }
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
                    LiveTabView(sources: sources, engine: engine,
                                stationFavorites: model.stationFavorites, recents: model.recents,
                                tokens: tokens,
                                play: { model.playStation($0) },
                                playRecent: { model.playRecent($0) })
                case 1:
                    ExploreTabView(catalog: catalog, favorites: favorites, pool: pool,
                                   engine: engine, surahs: surahs, tokens: tokens, play: play,
                                   focusReciterID: $model.exploreFocusReciterID)
                case 2:
                    LibraryTabView(library: library, importer: importer, engine: engine,
                                   surahs: surahs, tokens: tokens, playLocal: playLocal)
                default:
                    MixTabView(model: model, tokens: tokens)
                }
            }

            NowPlayingBar(engine: engine, tokens: tokens,
                          isMixing: model.isMixing, upNext: upNextDisplay,
                          onTapSource: { goToNowPlayingSource() },
                          onMixPrev: { model.mixPrevious() }, onMixNext: { model.mixNext() },
                          mixHasPrevious: model.mixHasPrevious, mixHasNext: model.mixHasNext)
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
        // Plan 5: the gear (and the ••• "Settings…") slides the full Settings screen over the panel,
        // same overlay mechanism as the tagger review. Drawn after it so an open Settings sits on top.
        .overlay {
            if showingSettings {
                SettingsView(settings: settings, importer: importer, tokens: tokens,
                             onClose: { showingSettings = false })
            }
        }
        .preferredColorScheme(theme == .system ? nil : (resolved == .sahar ? .light : .dark))
    }

    // MARK: - Now-playing source navigation

    /// Tapping the now-playing bar's art/title region jumps the panel to wherever the current audio
    /// originates. `isMixing` is checked first because mix items carry on-demand/local source-ids that
    /// would otherwise mis-route to Explore/Library. On-demand additionally deep-links into the playing
    /// reciter's Explore detail page via `model.exploreFocusReciterID` (watched by `ExploreTabView`).
    private func goToNowPlayingSource() {
        if model.isMixing { tab = 3; return }
        guard let id = engine.currentSourceID else { return }
        if id.hasPrefix("live:") {
            tab = 0
        } else if id.hasPrefix("local:") {
            tab = 2
        } else if id.hasPrefix("ondemand:") {
            // "ondemand:<reciterID>:<moshafID>:<surahNum>" — the reciter id sits between the first two
            // colons. Parse it to focus Explore on that reciter; an unparsable id still lands on the tab.
            let parts = id.split(separator: ":")
            if parts.count >= 2, let reciterID = Int(parts[1]) {
                model.exploreFocusReciterID = reciterID
            }
            tab = 1
        }
    }

    // MARK: - Commands (the menubar-icon context menu, relocated)

    /// The mockup puts these on a right-click of the menubar icon, but a
    /// `MenuBarExtra(.menuBarExtraStyle(.window))` icon has no native right-click menu — a click
    /// is reserved for opening this panel. So the commands live here as a `•••` header menu beside
    /// the gear, which stays grouped as theme + launch-at-login. Observes `engine` (via the
    /// view's `@ObservedObject`), so the Play/Pause label tracks playback live.
    private var commandsMenu: some View {
        Menu {
            Button("Add Files to Library…") { importer.addFilesPanel() }
            Button("Reveal Library Folder") {
                NSWorkspace.shared.activateFileViewerSelecting([importer.libraryFolderURL])
            }
            Button("Choose Library Folder…") { importer.chooseLibraryFolder() }
            Divider()
            Button(engine.status == .playing ? "Pause" : "Play") { engine.toggle() }
            Divider()
            // Plan 5: opens the full Settings screen (theme, hotkey, media keys, library, login,
            // about) — the same overlay the gear presents.
            Button("Settings…") { showingSettings = true }
            Button("Quit Qurani") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Image(systemName: "ellipsis.circle").font(.system(size: 15)).foregroundStyle(tokens.muted)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    // MARK: - Settings (gear → full Settings screen)

    /// The header gear now opens the full `SettingsView` overlay (which owns theme + launch-at-login,
    /// formerly an inline menu here) rather than a small popover menu — one place for every preference,
    /// matching the mockup.
    private var settingsButton: some View {
        Button { showingSettings = true } label: {
            Image(systemName: "gearshape").font(.system(size: 15)).foregroundStyle(tokens.muted)
        }
        .buttonStyle(.plain)
        .help("Settings")
    }
}
