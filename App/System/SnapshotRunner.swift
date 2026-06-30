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

        // GlassPanel in both Noor (dark) and Sahar (light), Makkah playing.
        for (raw, isDark) in [("noor", true), ("sahar", false)] {
            UserDefaults.standard.set(raw, forKey: "theme")     // drives GlassPanel's @AppStorage
            let resolved = (Theme(rawValue: raw) ?? .system).resolved(systemIsDark: isDark)
            let sources = SourcesStore()
            sources.seed(featured: featured, reciterStations: reciters)
            let engine = PlaybackEngine(player: SnapshotPlayer())
            if let first = featured.first { engine.playStation(first) }   // one station playing
            let tmp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let panel = GlassPanel(sources: sources, engine: engine,
                                   catalog: CatalogStore(), favorites: FavoritesStore(directory: tmp),
                                   pool: MixPoolStore(directory: tmp), surahs: [],
                                   play: { _, _, _ in })   // Live tab is shown; Explore data unused here
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

        // Now-playing bar mid-on-demand (scrubber + mm:ss labels), both themes.
        renderNowPlaying(outDir: outDir, written: &written)

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
            engine.play(.onDemand(reciterName: reciter.name, surah: s55, url: url))
        }
        let detail = ReciterDetailView(
            reciter: reciter, favorites: favs, pool: pool, engine: engine,
            surahs: surahs, tokens: noor, onBack: {}, play: { _, _, _ in })
            .frame(width: 344).background(noor.bg)
        let detailPath = "\(outDir)/reciter-detail.png"
        if writePNG(detail, to: detailPath) { written.append(detailPath) }
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
            engine.play(.onDemand(reciterName: "Mishary Alafasy", surah: surah, url: url))
            player.onTime?(92, 760)    // feed position through the engine → elapsed 1:32 of 12:40
            let bar = NowPlayingBar(engine: engine, tokens: Tokens.of(theme))
                .frame(width: 344).background(Tokens.of(theme).bg)
            let path = "\(outDir)/nowplaying-\(raw).png"
            if writePNG(bar, to: path) { written.append(path) }
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
