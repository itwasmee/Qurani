import SwiftUI
import AppKit
import CoreText
import QuraniKit

// DEBUG-only: the entire snapshot/visual-review runtime path. It is launch-flag-gated (`--snapshot`)
// and inert in normal use, but must not compile into the release binary (Plan 5 DoD). The only
// dispatch site (`QuraniApp.init`) is likewise wrapped in `#if DEBUG`.
#if DEBUG

/// An AudioPlayer that confirms playback synchronously — lets the snapshot engine reach
/// `.playing` without real audio or a network.
@MainActor final class SnapshotPlayer: AudioPlayer {
    var onStatus: ((Bool) -> Void)?
    var onStreamTitle: ((String) -> Void)?
    var onFailure: ((String) -> Void)?
    var onTime: ((Double, Double) -> Void)?
    var onFinish: (() -> Void)?
    var volume: Float = 1.0
    func replace(url: URL) {}
    func play() { onStatus?(true) }
    func pause() { onStatus?(false) }
    func seek(toFraction f: Double) {}
}

/// Debug-only: when the app is launched with `--snapshot <outdir>`, render PNGs of the
/// real SwiftUI (via an offscreen `NSHostingView`, no visible window needed) and exit(0)
/// before any window is shown. Vibrancy + NSSwitch won't appear — layout / fonts / tokens will.
///
/// Every reviewable surface renders in BOTH shipped themes (Noor dark + Sahar light) so the
/// controller can compare each screen against the mockups side by side. Filenames are
/// `<screen>-<theme>.png` (e.g. `live-noor.png` / `library-sahar.png`).
@MainActor enum SnapshotRunner {
    /// `--snapshot <dir>` → returns the output directory, or nil if absent.
    static func requestedOutputDir() -> String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    /// The two shipped themes the controller reviews — every surface renders in both.
    private static let themes: [(raw: String, theme: ResolvedTheme, isDark: Bool)] =
        [("noor", .noor, true), ("sahar", .sahar, false)]

    private static let reciterJSON = #"""
    {"radios":[
      {"id":11,"name":"عبد الباسط عبد الصمد","url":"https://qurango.net/radio/abdulbasit_mojawwad"},
      {"id":12,"name":"محمد صديق المنشاوي","url":"https://qurango.net/radio/menshawy_mojawwad"}
    ]}
    """#.data(using: .utf8)!

    static func run(outDir: String) -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()   // finalize launch so SF Symbols / asset rendering resolve
        registerBundledFonts()

        let fm = FileManager.default
        try? fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)

        let featured = (try? CuratedStations.load()) ?? []
        let reciters = (try? RadiosService.decode(reciterJSON)) ?? []
        let surahs = (try? QuranData.loadSurahs()) ?? []
        var written: [String] = []

        // A throwaway root model that satisfies GlassPanel's initializer (Live-tab panels) and backs
        // the Mix renders below. Its persisted stores point at a throwaway directory, so seeding them
        // for the Mix build panel never reads or mutates real user data. Created once so
        // `Hotkeys.register` doesn't run per iteration.
        let snapshotTmp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let snapshotModel = AppModel(storesDirectory: snapshotTmp)

        // Full GlassPanel on the Live tab, in both themes (Makkah playing). This is rendered before any
        // `seedMix` flips `snapshotModel.isMixing`, so its now-playing bar shows the live station cleanly.
        renderLive(model: snapshotModel, outDir: outDir, featured: featured, reciterStations: reciters,
                   surahs: surahs, written: &written)

        // SurahNameView sample (Amiri + medallion), both themes.
        renderSurahName(outDir: outDir, written: &written)

        // Explore (catalog list + a reciter opened, one surah streaming), both themes.
        renderExplore(outDir: outDir, surahs: surahs, written: &written)

        // Library tab (reciters grouped, durations, one local file playing), both themes.
        renderLibrary(outDir: outDir, surahs: surahs, written: &written)

        // Tagger review sheet (four pending imports), both themes.
        renderTaggerReview(outDir: outDir, surahs: surahs, written: &written)

        // Settings screen (theme swatches, hotkey recorder, toggles, library, about), both themes.
        renderSettings(outDir: outDir, written: &written)

        // Now-playing bar — every variant (live / on-demand / mix) in both themes.
        renderNowPlaying(outDir: outDir, surahs: surahs, written: &written)

        // Mix tab — build panel + playing queue, both themes. Last, because `seedMix` flips
        // `snapshotModel.isMixing` (used above by the Live GlassPanel's now-playing chip).
        renderMix(model: snapshotModel, outDir: outDir, surahs: surahs, written: &written)

        let log = written.isEmpty
            ? "Qurani snapshot: produced no images (headless render unsupported).\n"
            : "Qurani snapshot wrote \(written.count) images:\n" + written.joined(separator: "\n") + "\n"
        FileHandle.standardError.write(Data(log.utf8))
        // Surface the output directory for the controller, regardless of count.
        FileHandle.standardError.write(Data("Qurani snapshot dir: \(outDir)\n".utf8))
        exit(0)
    }

    // MARK: - Live (full GlassPanel)

    /// The whole panel on the Live tab in both themes — header chrome, the segmented control, the
    /// Live station list, and the now-playing bar with the first featured station playing. Each theme
    /// sets `@AppStorage("theme")` first (GlassPanel reads it) and gets a fresh sources/engine/library
    /// so the highlighted row reaches `.playing` without audio.
    private static func renderLive(model: AppModel, outDir: String, featured: [Station],
                                   reciterStations: [Station], surahs: [Surah], written: inout [String]) {
        let fm = FileManager.default
        for (raw, theme, isDark) in themes {
            UserDefaults.standard.set(raw, forKey: "theme")     // drives GlassPanel's @AppStorage
            let tokens = Tokens.of(theme)
            let sources = SourcesStore()
            sources.seed(featured: featured, reciterStations: reciterStations)
            let engine = PlaybackEngine(player: SnapshotPlayer())
            if let first = featured.first { engine.playStation(first) }   // one station playing
            let tmp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let library = LibraryStore(directory: tmp)
            let panel = GlassPanel(model: model, sources: sources, engine: engine,
                                   catalog: CatalogStore(), favorites: FavoritesStore(directory: tmp),
                                   pool: MixPoolStore(directory: tmp),
                                   library: library, importer: LibraryImporter(library: library),
                                   settings: SettingsStore(directory: tmp),
                                   updates: model.updates,
                                   surahs: surahs,
                                   play: { _, _, _ in }, playLocal: { _ in },
                                   commitImports: { _ in })   // Live tab shown; other tabs unused here
                .environment(\.colorScheme, isDark ? .dark : .light)  // fallback if @AppStorage is unset
                .background(tokens.bg)                                 // opaque backing for the vibrancy gap
            let path = "\(outDir)/live-\(raw).png"
            if writePNG(panel, to: path) { written.append(path) }
        }
    }

    // MARK: - SurahNameView sample

    private static func renderSurahName(outDir: String, written: inout [String]) {
        for (raw, theme, isDark) in themes {
            let tokens = Tokens.of(theme)
            let surah = SurahNameView(number: 67, nameAr: "الْمُلْك", translit: "Al-Mulk",
                                      tokens: tokens, playing: true)
                .padding(22).frame(width: 320)
                .environment(\.colorScheme, isDark ? .dark : .light)
                .background(tokens.bg)
            let path = "\(outDir)/surah-name-\(raw).png"
            if writePNG(surah, to: path) { written.append(path) }
        }
    }

    // MARK: - Explore (catalog list + reciter detail)

    /// Renders the two Explore surfaces in both themes: the reciter catalog (`explore-list-<theme>.png`)
    /// and a reciter opened with one surah streaming (`reciter-detail-<theme>.png`). Uses seeded sample
    /// reciters + the real surah list, and a `SnapshotPlayer` so the highlighted row reaches `.playing`
    /// without audio or a network.
    private static func renderExplore(outDir: String, surahs: [Surah], written: inout [String]) {
        let base = URL(string: "https://server.example/")!
        func moshaf(_ id: Int, _ name: String, _ nums: [Int]) -> Moshaf {
            Moshaf(id: id, name: name, serverBase: base, surahNumbers: nums)
        }
        let reciters = [
            Reciter(id: 1, name: "Mishary Alafasy",
                    // 55 kept high in the list so the streaming-row highlight is visible
                    // above the fold in the 300pt-tall detail snapshot.
                    moshafs: [moshaf(1, "Hafs · Murattal", [1, 55, 67, 112]),
                              moshaf(2, "Mujawwad", [1, 36, 55, 67])]),
            Reciter(id: 2, name: "Abdul Basit Abdul Samad",
                    moshafs: [moshaf(3, "Murattal", [1, 2, 112]),
                              moshaf(4, "Mujawwad", [1, 55, 112])]),
            Reciter(id: 3, name: "Mahmoud Khalil Al-Husary", moshafs: [moshaf(5, "Mujawwad", [1, 2, 36])]),
            Reciter(id: 4, name: "Yasser Al-Dossari", moshafs: [moshaf(6, "Hafs", [1, 2, 67])]),
            Reciter(id: 5, name: "Saad Al-Ghamdi", moshafs: [moshaf(7, "Hafs", [1, 55, 112])]),
        ]

        for (raw, theme, isDark) in themes {
            let tokens = Tokens.of(theme)
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

            // A: reciter catalog — one reciter already added to the Mix pool (✓).
            let catalog = CatalogStore(); catalog.seed(reciters: reciters)
            let listPool = MixPoolStore(directory: tmp); listPool.toggle(reciter: 2)
            let list = ExploreTabView(
                catalog: catalog, favorites: FavoritesStore(directory: tmp), pool: listPool,
                engine: PlaybackEngine(player: SnapshotPlayer()), surahs: surahs,
                tokens: tokens, play: { _, _, _ in }, focusReciterID: .constant(nil))
                .frame(width: 344)
                .environment(\.colorScheme, isDark ? .dark : .light).background(tokens.bg)
            let listPath = "\(outDir)/explore-list-\(raw).png"
            if writePNG(list, to: listPath) { written.append(listPath) }

            // B: reciter detail — favorited + pooled, Ar-Rahman (55) streaming on demand.
            let reciter = reciters[0]
            let favs = FavoritesStore(directory: tmp); favs.toggle(reciter: reciter.id)
            let pool = MixPoolStore(directory: tmp); pool.toggle(reciter: reciter.id)
            let engine = PlaybackEngine(player: SnapshotPlayer()); engine.attachSurahs(surahs)
            if let s55 = surahs.first(where: { $0.number == 55 }) {
                let url = CatalogService.audioURL(serverBase: reciter.moshafs[0].serverBase, surah: 55)
                engine.play(.onDemand(reciterID: reciter.id, reciterName: reciter.name,
                                      moshafID: reciter.moshafs[0].id, surah: s55, url: url))
            }
            let detail = ReciterDetailView(
                reciter: reciter, favorites: favs, pool: pool, engine: engine,
                surahs: surahs, tokens: tokens, onBack: {}, play: { _, _, _ in })
                .frame(width: 344)
                .environment(\.colorScheme, isDark ? .dark : .light).background(tokens.bg)
            let detailPath = "\(outDir)/reciter-detail-\(raw).png"
            if writePNG(detail, to: detailPath) { written.append(detailPath) }
        }
    }

    // MARK: - Library

    /// Renders the Library tab in both themes: three reciters grouped (Style-B surah rows with
    /// durations), the first group's first surah playing (highlighted) via a `SnapshotPlayer`. Synthetic
    /// `Data()` bookmarks never resolve, but the snapshot only displays + matches the source id — it never
    /// plays real audio. Durations mirror the mockup, plus one ≥ 1h track to exercise the h:mm:ss label.
    private static func renderLibrary(outDir: String, surahs: [Surah], written: inout [String]) {
        func track(_ reciter: String, _ surah: Int, _ durationMs: Int) -> LocalTrack {
            LocalTrack(bookmark: Data(), reciterName: reciter, surahNumber: surah,
                       confidence: 1.0, durationMs: durationMs)
        }
        for (raw, theme, isDark) in themes {
            let tokens = Tokens.of(theme)
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let library = LibraryStore(directory: tmp)
            library.add([
                track("Abdul Basit Abdul Samad", 1, 96_000),     // Al-Fatiha · 1:36 (playing)
                track("Abdul Basit Abdul Samad", 36, 540_000),   // Ya-Sin · 9:00
                track("Mahmoud Al-Husary", 2, 7_325_000),        // Al-Baqarah · 2:02:05 (h:mm:ss)
                track("Mahmoud Al-Husary", 18, 2_292_000),       // Al-Kahf · 38:12
                track("Mahmoud Al-Husary", 55, 760_000),         // Ar-Rahman · 12:40
                track("Abdul Rahman Al-Sudais", 112, 41_000),    // Al-Ikhlas · 0:41
            ])
            let importer = LibraryImporter(library: library); importer.surahs = surahs
            let engine = PlaybackEngine(player: SnapshotPlayer()); engine.attachSurahs(surahs)
            // Play the alphabetically-first group's first surah so the highlighted row sits at the top.
            if let playing = library.grouped().first?.tracks.first {
                engine.play(.localTrack(track: playing, url: URL(fileURLWithPath: "/dev/null")))
            }
            let view = LibraryTabView(library: library, importer: importer, engine: engine,
                                      surahs: surahs, tokens: tokens, playLocal: { _ in })
                .frame(width: 344)
                .environment(\.colorScheme, isDark ? .dark : .light).background(tokens.bg)
            let path = "\(outDir)/library-\(raw).png"
            if writePNG(view, to: path) { written.append(path) }
        }
    }

    // MARK: - Tagger review sheet

    /// Renders the tagger review sheet in both themes with four seeded pending imports, mirroring the
    /// mockup: two confident rows (✓), one amber row (blank reciter + low-confidence guess, "needs
    /// review"), and one medium row (~ chip). Pending imports are injected via the importer's
    /// `seedPending` seam; synthetic `Data()` bookmarks never resolve, but the sheet only displays the
    /// guesses and edits — it never commits or plays here.
    private static func renderTaggerReview(outDir: String, surahs: [Surah], written: inout [String]) {
        func pending(_ name: String, reciter: String?, surah: Int?, confidence: Double, _ ms: Int?) -> PendingImport {
            PendingImport(url: URL(fileURLWithPath: "/Music/Qurani/\(name)"), bookmark: Data(),
                          guess: Tagger.Guess(reciterName: reciter, surahNumber: surah, confidence: confidence),
                          durationMs: ms)
        }
        for (raw, theme, isDark) in themes {
            let tokens = Tokens.of(theme)
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let library = LibraryStore(directory: tmp)
            let importer = LibraryImporter(library: library); importer.surahs = surahs
            importer.seedPending([
                pending("002-husary.mp3", reciter: "Mahmoud Al-Husary", surah: 2, confidence: 0.9, 1_082_000),
                pending("sudais-018-alkahf.mp3", reciter: "Sudais", surah: 18, confidence: 0.9, 2_292_000),
                pending("track 12.mp3", reciter: nil, surah: 23, confidence: 0.3, 760_000),       // amber: blank reciter
                pending("alfatiha-basit.mp3", reciter: "Abdul Basit", surah: 1, confidence: 0.5, 96_000),
            ])
            let view = TaggerReviewView(importer: importer, surahs: surahs, tokens: tokens, commit: { _ in })
                .frame(width: 344, height: 560)   // tall enough that all four seeded rows sit above the fold
                .environment(\.colorScheme, isDark ? .dark : .light).background(tokens.bg)
            let path = "\(outDir)/tagger-review-\(raw).png"
            if writePNG(view, to: path) { written.append(path) }
        }
    }

    // MARK: - Settings

    /// Renders the full Settings screen in both themes: the matching swatch shown selected (its
    /// `@AppStorage` theme is set first), the hotkey recorder, both toggles, the default library folder,
    /// and the About/attribution footer. Throwaway stores so nothing reads or mutates real user data. A
    /// tall frame so every section (through About) sits above the fold for review.
    private static func renderSettings(outDir: String, written: inout [String]) {
        for (raw, theme, isDark) in themes {
            UserDefaults.standard.set(raw, forKey: "theme")     // drives SettingsView's @AppStorage swatch
            let tokens = Tokens.of(theme)
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let library = LibraryStore(directory: tmp)
            // An idle checker with a failing transport: the Updates row renders its resting
            // "Version 1.0" state and the snapshot can never hit the network.
            let view = SettingsView(settings: SettingsStore(directory: tmp),
                                    importer: LibraryImporter(library: library),
                                    updates: UpdateChecker(currentVersion: "1.0",
                                                           fetch: { _ in throw URLError(.notConnectedToInternet) }),
                                    updater: SelfUpdater(),
                                    tokens: tokens, onClose: {})
                .frame(width: 344, height: 760)   // tall enough for the UPDATES section + About
                .environment(\.colorScheme, isDark ? .dark : .light).background(tokens.bg)
            let path = "\(outDir)/settings-\(raw).png"
            if writePNG(view, to: path) { written.append(path) }
        }
    }

    // MARK: - Now-playing bar (live / on-demand / mix variants)

    /// Renders all three now-playing variants in both themes:
    ///   • `nowplaying-live-<theme>.png` — a live station (red LIVE pill, no scrubber).
    ///   • `nowplaying-ondemand-<theme>.png` — Ar-Rahman streaming, elapsed 1:32 of 12:40, scrubber ~12%.
    ///   • `nowplaying-mix-<theme>.png` — a mix item (⤮ MIX chip + "up next" hint + on-demand scrubber).
    /// A `SnapshotPlayer` lets each item reach `.playing`; feeding `onTime` fills the scrubber without
    /// real audio or a network.
    private static func renderNowPlaying(outDir: String, surahs: [Surah], written: inout [String]) {
        guard let rahman = surahs.first(where: { $0.number == 55 }) else { return }   // Ar-Rahman
        let base = URL(string: "https://server.example/")!
        let makkah = Station(id: "makkah", name: "Makkah — Al-Haram", region: "Makkah",
                             kind: .hls, url: URL(string: "https://server.example/makkah")!,
                             reciter: nil, hasVideo: true)

        for (raw, theme, isDark) in themes {
            let tokens = Tokens.of(theme)

            // Live: a featured station — LIVE pill, no progress control.
            let liveEngine = PlaybackEngine(player: SnapshotPlayer())
            liveEngine.playStation(makkah)
            let livePath = "\(outDir)/nowplaying-live-\(raw).png"
            if writePNG(NowPlayingBar(engine: liveEngine, tokens: tokens).frame(width: 344)
                .environment(\.colorScheme, isDark ? .dark : .light).background(tokens.bg),
                        to: livePath) { written.append(livePath) }

            // On-demand: Ar-Rahman, elapsed 1:32 of 12:40 → scrubber ~12% filled.
            let odPlayer = SnapshotPlayer()
            let odEngine = PlaybackEngine(player: odPlayer)
            odEngine.play(.onDemand(reciterID: 1, reciterName: "Mishary Alafasy", moshafID: 1,
                                    surah: rahman, url: URL(string: "https://server.example/055.mp3")!))
            odPlayer.onTime?(92, 760)
            let odPath = "\(outDir)/nowplaying-ondemand-\(raw).png"
            if writePNG(NowPlayingBar(engine: odEngine, tokens: tokens).frame(width: 344)
                .environment(\.colorScheme, isDark ? .dark : .light).background(tokens.bg),
                        to: odPath) { written.append(odPath) }

            // Mix: the ⤮ MIX source chip + "up next · random" hint + on-demand scrubber (0:32 of 1:30).
            if let s1 = surahs.first(where: { $0.number == 1 }) {
                let mixPlayer = SnapshotPlayer()
                let mixEngine = PlaybackEngine(player: mixPlayer); mixEngine.attachSurahs(surahs)
                mixEngine.play(.onDemand(reciterID: 1, reciterName: "Abdul Rahman Al-Sudais", moshafID: 1,
                                         surah: s1, url: CatalogService.audioURL(serverBase: base, surah: 1)))
                mixPlayer.onTime?(32, 90)
                let upNext = (memberName: "Abdul Basit Abdul Samad",
                              surahName: surahs.first { $0.number == 2 }?.nameAr ?? "Surah 2")
                let mixPath = "\(outDir)/nowplaying-mix-\(raw).png"
                if writePNG(NowPlayingBar(engine: mixEngine, tokens: tokens, isMixing: true, upNext: upNext)
                    .frame(width: 344)
                    .environment(\.colorScheme, isDark ? .dark : .light).background(tokens.bg),
                            to: mixPath) { written.append(mixPath) }
            }
        }
    }

    // MARK: - Mix (build panel + playing queue)

    /// Renders the Mix tab in both themes, reusing `model` (its stores point at a throwaway directory):
    /// the **build** panel — seeded on-demand candidates (two pooled → pre-checked, one favorited →
    /// unchecked) plus local candidates — and the **playing** queue, seeded directly via `AppModel.seedMix`
    /// (no engine) with the first row highlighted. All build renders run first, because `seedMix` flips
    /// `isMixing`, which switches the view to the playing branch for the rest of the function.
    private static func renderMix(model: AppModel, outDir: String, surahs: [Surah], written: inout [String]) {
        let base = URL(string: "https://server.example/")!

        // Seed catalog + pool/favorites (on-demand candidates) + library (local candidates) once.
        func onDemand(_ id: Int, _ name: String) -> Reciter {
            Reciter(id: id, name: name,
                    moshafs: [Moshaf(id: id * 10, name: "Hafs", serverBase: base, surahNumbers: Array(1...114))])
        }
        model.catalog.seed(reciters: [onDemand(1, "Mishary Alafasy"),
                                      onDemand(2, "Saad Al-Ghamdi"),
                                      onDemand(3, "Maher Al-Muaiqly")])
        model.pool.toggle(reciter: 1); model.pool.toggle(reciter: 2)   // pooled → pre-checked
        model.favorites.toggle(reciter: 3)                              // favorited → candidate, unchecked
        func local(_ reciter: String, _ surah: Int) -> LocalTrack {
            LocalTrack(bookmark: Data(), reciterName: reciter, surahNumber: surah, confidence: 1.0, durationMs: 600_000)
        }
        model.library.add([local("Mahmoud Al-Husary", 2),
                           local("Abdul Rahman Al-Sudais", 1),
                           local("Abdul Basit Abdul Samad", 36)])

        // Build state (isMixing still false) — both themes.
        for (raw, theme, isDark) in themes {
            let build = MixTabView(model: model, tokens: Tokens.of(theme))
                .frame(width: 344, height: 470)
                .environment(\.colorScheme, isDark ? .dark : .light).background(Tokens.of(theme).bg)
            let path = "\(outDir)/mix-build-\(raw).png"
            if writePNG(build, to: path) { written.append(path) }
        }

        // Seed a small queue + its pool directly (no real audio); first row highlighted.
        model.surahs = surahs
        let pool: [PoolMember] = [
            PoolMember(id: "local:Sudais", source: .local, displayName: "Abdul Rahman Al-Sudais",
                       reciterName: "Abdul Rahman Al-Sudais", surahNumbers: [1, 6], reciterID: nil, moshaf: nil),
            PoolMember(id: "local:Basit", source: .local, displayName: "Abdul Basit Abdul Samad",
                       reciterName: "Abdul Basit Abdul Samad", surahNumbers: [2, 5], reciterID: nil, moshaf: nil),
            PoolMember(id: "od:1", source: .onDemand, displayName: "Mishary Alafasy",
                       reciterName: "Mishary Alafasy", surahNumbers: [3], reciterID: 1, moshaf: nil),
            PoolMember(id: "od:2", source: .onDemand, displayName: "Saad Al-Ghamdi",
                       reciterName: "Saad Al-Ghamdi", surahNumbers: [4], reciterID: 2, moshaf: nil),
        ]
        let queue = [MixQueueItem(surah: 1, memberID: "local:Sudais"),
                     MixQueueItem(surah: 2, memberID: "local:Basit"),
                     MixQueueItem(surah: 3, memberID: "od:1"),
                     MixQueueItem(surah: 4, memberID: "od:2"),
                     MixQueueItem(surah: 5, memberID: "local:Basit"),
                     MixQueueItem(surah: 6, memberID: "local:Sudais")]
        model.seedMix(queue: queue, pool: pool, index: 0)

        // Playing state (isMixing now true) — both themes.
        for (raw, theme, isDark) in themes {
            let playing = MixTabView(model: model, tokens: Tokens.of(theme))
                .frame(width: 344)
                .environment(\.colorScheme, isDark ? .dark : .light).background(Tokens.of(theme).bg)
            let path = "\(outDir)/mix-playing-\(raw).png"
            if writePNG(playing, to: path) { written.append(path) }
        }
    }

    // MARK: - Helpers

    private static func registerBundledFonts() {
        for name in ["AmiriQuran-Regular", "NotoNaskhArabic-Regular"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "ttf") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }

    // Render via an offscreen NSHostingView in a borderless window. Hosting the real view tree (vs.
    // ImageRenderer, which rasterizes SF Symbols as the prohibitory placeholder in this headless agent
    // context) captures symbols AND the AppKit vibrancy at the window's backing scale (2x on Retina).
    // Launch through LaunchServices (`open -nW <app> --args --snapshot <dir>`) so the process has a
    // WindowServer context.
    private static func writePNG(_ view: some View, to path: String) -> Bool {
        let hosting = NSHostingView(rootView: view)
        hosting.layoutSubtreeIfNeeded()
        var size = hosting.fittingSize
        if size.width < 1 || size.height < 1 { size = CGSize(width: 344, height: 460) }
        hosting.frame = CGRect(origin: .zero, size: size)

        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return false }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: URL(fileURLWithPath: path))) != nil
    }
}

#endif
