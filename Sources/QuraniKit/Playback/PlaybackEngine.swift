import Foundation

@MainActor public final class PlaybackEngine: ObservableObject {
    @Published public private(set) var status: PlayerStatus = .idle
    @Published public private(set) var nowPlaying: NowPlaying?
    /// Identity of the item currently loaded, independent of display title.
    /// Used to drive the row highlight (duplicate titles must not collide).
    /// Format: `"live:<station.id>"` or `"ondemand:<reciterName>:<surahNumber>"`.
    @Published public private(set) var currentSourceID: String?
    @Published public var volume: Float = 1.0 { didSet { player.volume = volume } }

    /// Fired when the current item plays to its end. Unused for live radio; consumed by the
    /// Mix engine (Plan 4) to advance to the next pool entry.
    public var onFinish: (() -> Void)?

    private let player: AudioPlayer
    private var surahs: [Surah] = []
    private var current: PlaybackItem?

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
        self.player.onFailure = { [weak self] reason in
            // Ignore a late failure that arrives when nothing is loaded (e.g. after
            // `stop()`/idle): without a current item it would strand the UI in
            // `.failed` with `nowPlaying == nil`.
            guard let self, self.currentSourceID != nil else { return }
            self.status = .failed(reason)
        }
        self.player.onTime = { [weak self] el, du in
            guard let self, var np = self.nowPlaying else { return }
            np.elapsed = el; np.duration = du; self.nowPlaying = np
        }
        self.player.onFinish = { [weak self] in self?.onFinish?() }
    }

    public func attachSurahs(_ s: [Surah]) { surahs = s }

    public func play(_ item: PlaybackItem) {
        current = item
        currentSourceID = item.sourceID
        status = .loading
        switch item {
        case .liveStation(let station):
            nowPlaying = NowPlaying(title: station.name,
                                    subtitle: station.reciter ?? station.region,
                                    isLive: true, surahHint: nil)
        case .onDemand(let reciterName, let surah, _):
            nowPlaying = NowPlaying(title: surah.nameAr,
                                    subtitle: reciterName,
                                    isLive: false, surahHint: nil)
        }
        player.replace(url: item.url)
        player.volume = volume
        player.play()
    }

    /// Convenience for live-radio playback — preserves the pre-Plan-2 call shape.
    public func playStation(_ s: Station) { play(.liveStation(s)) }

    public func toggle() {
        switch status {
        case .playing: player.pause()
        case .paused, .idle: if current != nil { player.play() }
        default: break
        }
    }

    /// Scrub the current item to `f` (0…1) of its duration. Delegates to the player; a
    /// no-op for live items (no finite duration).
    public func seek(toFraction f: Double) { player.seek(toFraction: f) }

    /// Re-attempt the current item after a failure (drives the now-playing retry tap).
    public func retry() {
        if let current { play(current) }
    }

    public func stop() {
        player.pause()
        status = .idle
        nowPlaying = nil
        current = nil
        currentSourceID = nil
    }
}
