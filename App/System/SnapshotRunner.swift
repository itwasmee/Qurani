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
    var volume: Float = 1.0
    func replace(url: URL) {}
    func play() { onStatus?(true) }
    func pause() { onStatus?(false) }
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
            let panel = GlassPanel(sources: sources, engine: engine)
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

        let log = written.isEmpty
            ? "Qurani snapshot: ImageRenderer produced no images (headless render unsupported).\n"
            : "Qurani snapshot wrote:\n" + written.joined(separator: "\n") + "\n"
        FileHandle.standardError.write(Data(log.utf8))
        exit(0)
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
