import SwiftUI
import Combine
import QuraniKit

@MainActor final class AppModel: ObservableObject {
    let engine: PlaybackEngine
    let sources: SourcesStore
    @AppStorage("theme") var themeRaw: String = Theme.system.rawValue
    @Published var surahs: [Surah] = []

    private var bridge: NowPlayingBridge?
    private var engineCancellable: AnyCancellable?

    var theme: Theme { Theme(rawValue: themeRaw) ?? .system }

    init() {
        engine = PlaybackEngine(player: AVAudioPlayerAdapter())
        sources = SourcesStore()
    }

    func bootstrap() async {
        surahs = (try? QuranData.loadSurahs()) ?? []
        engine.attachSurahs(surahs)
        bridge = NowPlayingBridge(engine: engine)
        Hotkeys.register(engine)
        // keep Now Playing info in sync
        engineCancellable = engine.$nowPlaying.sink { [weak self] _ in self?.bridge?.update() }
        try? sources.loadFeatured()
        await sources.loadReciterStations { try await SourcesStore.fetchRadios() }
    }
}
