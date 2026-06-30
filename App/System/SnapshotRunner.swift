import SwiftUI
import AppKit
import CoreText
import QuraniKit

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
/// real SwiftUI (via CoreGraphics `ImageRenderer`, no WindowServer needed) and exit(0)
/// before any window is shown. Vibrancy won't appear — layout / fonts / tokens will.
@MainActor enum SnapshotRunner {
    /// `--snapshot <dir>` → returns the output directory, or nil if absent.
    static func requestedOutputDir() -> String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

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
        var written: [String] = []

        // A throwaway root model that satisfies GlassPanel's initializer (Live-tab panels) and backs
        // the Mix renders below. Its persisted stores point at a throwaway directory, so seeding them
        // for the Mix build panel never reads or mutates real user data. Created once so
        // `Hotkeys.register` doesn't run per iteration.
        let snapshotTmp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let snapshotModel = AppModel(storesDirectory: snapshotTmp)

        // GlassPanel in both Noor (dark) and Sahar (light), Makkah playing.
        for (raw, isDark) in [("noor", true), ("sahar", false)] {
            UserDefaults.standard.set(raw, forKey: "theme")     // drives GlassPanel's @AppStorage
            let resolved = (Theme(rawValue: raw) ?? .system).resolved(systemIsDark: isDark)
            let sources = SourcesStore()
            sources.seed(featured: featured, reciterStations: reciters)
            let engine = PlaybackEngine(player: SnapshotPlayer())
            if let first = featured.first { engine.playStation(first) }   // one station playing
            let tmp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let library = LibraryStore(directory: tmp)
            let panel = GlassPanel(model: snapshotModel, sources: sources, engine: engine,
                                   catalog: CatalogStore(), favorites: FavoritesStore(directory: tmp),
                                   pool: MixPoolStore(directory: tmp),
                                   library: library, importer: LibraryImporter(library: library),
                                   settings: SettingsStore(directory: tmp),
                                   surahs: [],
                                   play: { _, _, _ in }, playLocal: { _ in },
                                   commitImports: { _ in })   // Live tab shown; others unused here
                .environment(\.colorScheme, isDark ? .dark : .light)  // fallback if @AppStorage is unset
                .background(Tokens.of(resolved).bg)                   // opaque backing for the vibrancy gap
            let path = "\(outDir)/panel-\(raw).png"
            if writePNG(panel, to: path) { written.append(path) }
        }

        // SurahNameView sample (Amiri + medallion).
        let surah = SurahNameView(number: 67, nameAr: "الْمُلْك", translit: "Al-Mulk",
                                  tokens: Tokens.of(.noor), playing: true)
            .padding(22).frame(width: 320).background(Tokens.of(.noor).bg)
        let surahPath = "\(outDir)/surah-name.png"
        if writePNG(surah, to: surahPath) { written.append(surahPath) }

        // Explore tab (Noor): the reciter catalog + a reciter opened, one surah streaming.
        renderExplore(outDir: outDir, written: &written)

        // Library tab (Noor): three reciters grouped, a few surahs each, one local file playing.
        renderLibrary(outDir: outDir, written: &written)

        // Tagger review sheet (Noor): four pending imports — one high-confidence ✓, one amber
        // (blank reciter, low-confidence guess).
        renderTaggerReview(outDir: outDir, written: &written)

        // Settings screen (Noor): the full preferences overlay — theme swatches, hotkey recorder,
        // toggles, library folder, launch-at-login, about.
        renderSettings(outDir: outDir, written: &written)

        // Now-playing bar mid-on-demand (scrubber + mm:ss labels), both themes.
        renderNowPlaying(outDir: outDir, written: &written)

        // Mix tab (Noor): the build panel (seeded pool candidates) + the playing queue (a seeded
        // session via `seedMix`, the first row highlighted). Reuses `snapshotModel` (tmp-dir stores).
        renderMix(model: snapshotModel, outDir: outDir, written: &written)

        let log = written.isEmpty
            ? "Qurani snapshot: ImageRenderer produced no images (headless render unsupported).\n"
            : "Qurani snapshot wrote:\n" + written.joined(separator: "\n") + "\n"
        FileHandle.standardError.write(Data(log.utf8))
        exit(0)
    }

    /// Renders the two Explore surfaces in Noor: the reciter catalog (`explore-list.png`)
    /// and a reciter opened with one surah streaming (`reciter-detail.png`). Uses seeded
    /// sample reciters + the real surah list, and a `SnapshotPlayer` so the highlighted row
    /// reaches `.playing` without audio or a network.
    private static func renderExplore(outDir: String, written: inout [String]) {
        let noor = Tokens.of(.noor)
        let surahs = (try? QuranData.loadSurahs()) ?? []
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
            Reciter(id: 3, name: "Mahmoud Khalil Al-Husary", moshafs: [moshaf(5, "Muallim", [1, 2, 36])]),
            Reciter(id: 4, name: "Yasser Al-Dossari", moshafs: [moshaf(6, "Hafs", [1, 2, 67])]),
            Reciter(id: 5, name: "Saad Al-Ghamdi", moshafs: [moshaf(7, "Hafs", [1, 55, 112])]),
        ]
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        // A: reciter catalog — one reciter already added to the Mix pool (✓).
        let catalog = CatalogStore(); catalog.seed(reciters: reciters)
        let listPool = MixPoolStore(directory: tmp); listPool.toggle(reciter: 2)
        let list = ExploreTabView(
            catalog: catalog, favorites: FavoritesStore(directory: tmp), pool: listPool,
            engine: PlaybackEngine(player: SnapshotPlayer()), surahs: surahs,
            tokens: noor, play: { _, _, _ in })
            .frame(width: 344).background(noor.bg)
        let listPath = "\(outDir)/explore-list.png"
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
            surahs: surahs, tokens: noor, onBack: {}, play: { _, _, _ in })
            .frame(width: 344).background(noor.bg)
        let detailPath = "\(outDir)/reciter-detail.png"
        if writePNG(detail, to: detailPath) { written.append(detailPath) }
    }

    /// Renders the Library tab in Noor: three reciters grouped (Style-B surah rows with durations),
    /// the first group's first surah playing (highlighted) via a `SnapshotPlayer`. Synthetic `Data()`
    /// bookmarks never resolve, but the snapshot only displays + matches the source id — it never
    /// plays real audio. Durations mirror the mockup (18:02 / 38:12 / 12:40).
    private static func renderLibrary(outDir: String, written: inout [String]) {
        let noor = Tokens.of(.noor)
        let surahs = (try? QuranData.loadSurahs()) ?? []
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let library = LibraryStore(directory: tmp)
        func track(_ reciter: String, _ surah: Int, _ durationMs: Int) -> LocalTrack {
            LocalTrack(bookmark: Data(), reciterName: reciter, surahNumber: surah,
                       confidence: 1.0, durationMs: durationMs)
        }
        library.add([
            track("Abdul Basit Abdul Samad", 1, 96_000),     // Al-Fatiha · 1:36 (playing)
            track("Abdul Basit Abdul Samad", 36, 540_000),   // Ya-Sin · 9:00
            track("Mahmoud Al-Husary", 2, 1_082_000),        // Al-Baqarah · 18:02
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
                                  surahs: surahs, tokens: noor, playLocal: { _ in })
            .frame(width: 344).background(noor.bg)
        let path = "\(outDir)/library.png"
        if writePNG(view, to: path) { written.append(path) }
    }

    /// Renders the Task 7 tagger review sheet in Noor with four seeded pending imports, mirroring the
    /// mockup: two confident rows (✓), one amber row (blank reciter + low-confidence guess, shown
    /// "needs review"), and one medium row (~ chip). Pending imports are injected via the importer's
    /// `seedPending` seam; synthetic `Data()` bookmarks never resolve, but the sheet only displays the
    /// guesses and edits — it never commits or plays here.
    private static func renderTaggerReview(outDir: String, written: inout [String]) {
        let noor = Tokens.of(.noor)
        let surahs = (try? QuranData.loadSurahs()) ?? []
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let library = LibraryStore(directory: tmp)
        let importer = LibraryImporter(library: library); importer.surahs = surahs
        func pending(_ name: String, reciter: String?, surah: Int?, confidence: Double, _ ms: Int?) -> PendingImport {
            PendingImport(url: URL(fileURLWithPath: "/Music/Qurani/\(name)"), bookmark: Data(),
                          guess: Tagger.Guess(reciterName: reciter, surahNumber: surah, confidence: confidence),
                          durationMs: ms)
        }
        importer.seedPending([
            pending("002-husary.mp3", reciter: "Mahmoud Al-Husary", surah: 2, confidence: 0.9, 1_082_000),
            pending("sudais-018-alkahf.mp3", reciter: "Sudais", surah: 18, confidence: 0.9, 2_292_000),
            pending("track 12.mp3", reciter: nil, surah: 23, confidence: 0.3, 760_000),       // amber: blank reciter
            pending("alfatiha-basit.mp3", reciter: "Abdul Basit", surah: 1, confidence: 0.5, 96_000),
        ])
        let view = TaggerReviewView(importer: importer, surahs: surahs, tokens: noor, commit: { _ in })
            .frame(width: 344, height: 560)   // tall enough that all four seeded rows sit above the fold
            .background(noor.bg)
        let path = "\(outDir)/tagger-review.png"
        if writePNG(view, to: path) { written.append(path) }
    }

    /// Renders the full Settings screen in Noor: the Noor swatch shown selected (its `@AppStorage`
    /// theme is set first), the hotkey recorder, both toggles, the default library folder, and the
    /// About/attribution footer. Throwaway stores so nothing reads or mutates real user data. A tall
    /// frame so every section (through About) sits above the fold for review.
    private static func renderSettings(outDir: String, written: inout [String]) {
        UserDefaults.standard.set("noor", forKey: "theme")     // drives SettingsView's @AppStorage swatch
        let noor = Tokens.of(.noor)
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let library = LibraryStore(directory: tmp)
        let view = SettingsView(settings: SettingsStore(directory: tmp),
                                importer: LibraryImporter(library: library),
                                tokens: noor, onClose: {})
            .frame(width: 344, height: 620).background(noor.bg)
        let path = "\(outDir)/settings.png"
        if writePNG(view, to: path) { written.append(path) }
    }

    /// Renders the now-playing bar mid-on-demand in both Noor and Sahar: Ar-Rahman (55)
    /// streaming with `elapsed 92s / duration 760s` → labels "1:32 / 12:40" and the
    /// scrubber ~12% filled (`isLive == false`, so the draggable track shows).
    private static func renderNowPlaying(outDir: String, written: inout [String]) {
        let surahs = (try? QuranData.loadSurahs()) ?? []
        guard let surah = surahs.first(where: { $0.number == 55 }) else { return }   // Ar-Rahman
        let url = URL(string: "https://server.example/055.mp3")!
        for (raw, theme) in [("noor", ResolvedTheme.noor), ("sahar", .sahar)] {
            let player = SnapshotPlayer()
            let engine = PlaybackEngine(player: player)
            engine.play(.onDemand(reciterID: 1, reciterName: "Mishary Alafasy",
                                  moshafID: 1, surah: surah, url: url))
            player.onTime?(92, 760)    // feed position through the engine → elapsed 1:32 of 12:40
            let bar = NowPlayingBar(engine: engine, tokens: Tokens.of(theme))
                .frame(width: 344).background(Tokens.of(theme).bg)
            let path = "\(outDir)/nowplaying-\(raw).png"
            if writePNG(bar, to: path) { written.append(path) }
        }
    }

    /// Renders the Mix tab in Noor in both states, reusing `model` (its stores point at a throwaway
    /// directory): the **build** panel — seeded on-demand candidates (two pooled → pre-checked, one
    /// favorited → unchecked) plus local candidates — and the **playing** queue, seeded directly via
    /// `AppModel.seedMix` (no engine) with the first row highlighted. The build render runs first
    /// since `seedMix` flips `isMixing`, which switches the view to the playing branch.
    private static func renderMix(model: AppModel, outDir: String, written: inout [String]) {
        let noor = Tokens.of(.noor)
        let surahs = (try? QuranData.loadSurahs()) ?? []
        let base = URL(string: "https://server.example/")!

        // Build: seed catalog + pool/favorites (on-demand candidates) + library (local candidates).
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
        let build = MixTabView(model: model, tokens: noor)
            .frame(width: 344, height: 470).background(noor.bg)
        let buildPath = "\(outDir)/mix-build.png"
        if writePNG(build, to: buildPath) { written.append(buildPath) }

        // Playing: seed a small queue + its pool directly (no real audio); first row highlighted.
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
        let playing = MixTabView(model: model, tokens: noor)
            .frame(width: 344).background(noor.bg)
        let playingPath = "\(outDir)/mix-playing.png"
        if writePNG(playing, to: playingPath) { written.append(playingPath) }

        // The now-playing bar during a mix (Noor): the ⤮ MIX source chip + the "up next · random"
        // hint + the on-demand scrubber. A `SnapshotPlayer` lets the item reach `.playing`; feeding
        // `onTime(32, 90)` fills the scrubber (0:32 of 1:30) without real audio.
        if let s1 = surahs.first(where: { $0.number == 1 }) {
            let player = SnapshotPlayer()
            let engine = PlaybackEngine(player: player)
            engine.attachSurahs(surahs)
            engine.play(.onDemand(reciterID: 1, reciterName: "Abdul Rahman Al-Sudais",
                                  moshafID: 1, surah: s1, url: CatalogService.audioURL(serverBase: base, surah: 1)))
            player.onTime?(32, 90)
            let upNext = (memberName: "Abdul Basit Abdul Samad",
                          surahName: surahs.first { $0.number == 2 }?.nameAr ?? "Surah 2")
            let bar = NowPlayingBar(engine: engine, tokens: noor, isMixing: true, upNext: upNext)
                .frame(width: 344).background(noor.bg)
            let barPath = "\(outDir)/mix-nowplaying.png"
            if writePNG(bar, to: barPath) { written.append(barPath) }
        }
    }

    private static func registerBundledFonts() {
        for name in ["AmiriQuran-Regular", "NotoNaskhArabic-Regular"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "ttf") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }

    // Render via an offscreen NSHostingView in a borderless window. ImageRenderer (the
    // first choice) rasterizes SF Symbols as the prohibitory placeholder in this headless
    // agent context; hosting the real view tree captures symbols AND the AppKit vibrancy
    // at the window's backing scale (2x on Retina). Launch through LaunchServices
    // (`open -nW <app> --args --snapshot <dir>`) so the process has a WindowServer context.
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
