import Foundation

@MainActor public final class PlaybackEngine: ObservableObject {
    @Published public private(set) var status: PlayerStatus = .idle
    @Published public private(set) var nowPlaying: NowPlaying?
    @Published public var volume: Float = 1.0 { didSet { player.volume = volume } }

    private let player: AudioPlayer
    private var surahs: [Surah] = []
    private var current: Station?

    public init(player: AudioPlayer) {
        self.player = player
        self.player.onStatus = { [weak self] isPlaying in
            self?.status = isPlaying ? .playing : .paused
        }
        self.player.onStreamTitle = { [weak self] title in
            guard let self, var np = self.nowPlaying else { return }
            np.surahHint = ICYMetadata.surahHint(from: title, surahs: self.surahs)
            self.nowPlaying = np
        }
    }

    public func attachSurahs(_ s: [Surah]) { surahs = s }

    public func play(_ station: Station) {
        current = station
        status = .loading
        nowPlaying = NowPlaying(title: station.name,
                                subtitle: station.reciter ?? station.region,
                                isLive: true, surahHint: nil)
        player.replace(url: station.url)
        player.volume = volume
        player.play()
    }

    public func toggle() {
        switch status {
        case .playing: player.pause()
        case .paused, .idle: if current != nil { player.play() }
        default: break
        }
    }

    public func stop() { player.pause(); status = .idle; nowPlaying = nil; current = nil }
}
