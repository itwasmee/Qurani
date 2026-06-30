import SwiftUI
import Combine
import QuraniKit

@MainActor final class AppModel: ObservableObject {
    let engine: PlaybackEngine
    let sources: SourcesStore
    let catalog = CatalogStore()
    let favorites = FavoritesStore()
    let pool = MixPoolStore()
    let library = LibraryStore()
    /// Owns the import pipeline (Add-files panel, drag-drop, watched folder). Holds the
    /// `pendingImports` the review sheet (Task 7) confirms; observe it directly from views.
    let importer: LibraryImporter
    @Published var surahs: [Surah] = []

    // App-lifetime singletons: created exactly once in `init` (see C1). `bootstrap()`
    // runs from `.task{}`, which re-fires on every panel open — building the bridge or
    // re-registering the hotkey there would stack duplicate command targets/handlers.
    private let bridge: NowPlayingBridge
    private var cancellables: Set<AnyCancellable> = []
    private var didLoad = false

    init() {
        let engine = PlaybackEngine(player: AVAudioPlayerAdapter())
        self.engine = engine
        self.sources = SourcesStore()
        self.bridge = NowPlayingBridge(engine: engine)
        self.importer = LibraryImporter(library: library)

        // Register media-key / remote-command targets and the global hotkey once.
        Hotkeys.register(engine)

        // Keep Now Playing + Control Center transport state in sync. Pass the emitted
        // value (I1): @Published fires in willSet, so re-reading would be stale.
        engine.$nowPlaying
            .sink { [bridge] np in bridge.update(np) }
            .store(in: &cancellables)
        engine.$status
            .sink { [bridge] status in bridge.updatePlaybackState(status) }
            .store(in: &cancellables)
    }

    func bootstrap() async {
        guard !didLoad else { return }   // async data load is one-shot too
        didLoad = true
        surahs = (try? QuranData.loadSurahs()) ?? []
        engine.attachSurahs(surahs)
        importer.surahs = surahs
        importer.startWatching()   // best-effort; a no-op until a library folder is granted
        try? sources.loadFeatured()
        await sources.loadReciterStations { try await SourcesStore.fetchRadios() }
        await catalog.load { try await CatalogStore.fetchReciters() }
    }

    /// Start finite playback of a single surah recitation. Builds the per-surah audio URL
    /// from the moshaf's server base, then hands a `.onDemand` item to the engine.
    func playOnDemand(reciter: Reciter, moshaf: Moshaf, surah: Surah) {
        let url = CatalogService.audioURL(serverBase: moshaf.serverBase, surah: surah.number)
        engine.play(.onDemand(reciterID: reciter.id, reciterName: reciter.name,
                              moshafID: moshaf.id, surah: surah, url: url))
    }

    /// Play a library-imported local file. Resolving the track's security-scoped bookmark begins
    /// access (held for the session — released when the process exits); a track whose file has since
    /// moved or been deleted resolves to `nil` and is a no-op rather than a crash.
    func playLocal(_ track: LocalTrack) {
        guard let url = library.resolveURL(track) else { return }
        engine.play(.localTrack(track: track, url: url))
    }

    /// Commit the review sheet's confirmed imports to the library, then drop them from the pending
    /// list. Each `ReviewedImport` pairs with its `PendingImport` by id to recover the security-scoped
    /// bookmark, confidence, and duration captured at import time.
    func commitImports(_ reviewed: [ReviewedImport]) {
        let byID = Dictionary(importer.pendingImports.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let tracks = reviewed.compactMap { r -> LocalTrack? in
            guard let pending = byID[r.pendingID] else { return nil }
            return LocalTrack(bookmark: pending.bookmark, reciterName: r.reciterName,
                              surahNumber: r.surahNumber, confidence: pending.guess.confidence,
                              durationMs: pending.durationMs)
        }
        library.add(tracks)
        importer.clearPending(ids: Set(reviewed.map(\.pendingID)))
    }
}
