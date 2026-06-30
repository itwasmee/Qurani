import SwiftUI
import QuraniKit

@MainActor final class AppModel: ObservableObject {
    let engine: PlaybackEngine
    let sources: SourcesStore
    @AppStorage("theme") var themeRaw: String = Theme.system.rawValue
    @Published var surahs: [Surah] = []

    var theme: Theme { Theme(rawValue: themeRaw) ?? .system }

    init() {
        engine = PlaybackEngine(player: AVAudioPlayerAdapter())
        sources = SourcesStore()
    }

    func bootstrap() async {
        surahs = (try? QuranData.loadSurahs()) ?? []
        engine.attachSurahs(surahs)
        try? sources.loadFeatured()
        await sources.loadReciterStations { try await SourcesStore.fetchRadios() }
    }
}
