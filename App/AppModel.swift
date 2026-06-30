import SwiftUI
import Combine
import QuraniKit

@MainActor final class AppModel: ObservableObject {
    let engine: PlaybackEngine
    let sources: SourcesStore
    let catalog = CatalogStore()
    let favorites = FavoritesStore()
    let pool = MixPoolStore()
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
}
