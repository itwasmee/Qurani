import MediaPlayer
import QuraniKit

@MainActor final class NowPlayingBridge {
    private let engine: PlaybackEngine
    init(engine: PlaybackEngine) {
        self.engine = engine
        let c = MPRemoteCommandCenter.shared()
        // MediaPlayer invokes these handlers on an arbitrary thread, so hop to the
        // main actor before touching the @MainActor engine (also required by Swift 6
        // strict concurrency — the imported ObjC block is non-isolated).
        c.playCommand.addTarget { [weak engine] _ in
            Task { @MainActor in engine?.toggle() }
            return .success
        }
        c.pauseCommand.addTarget { [weak engine] _ in
            Task { @MainActor in engine?.toggle() }
            return .success
        }
        c.togglePlayPauseCommand.addTarget { [weak engine] _ in
            Task { @MainActor in engine?.toggle() }
            return .success
        }
    }
    func update() {
        guard let np = engine.nowPlaying else { MPNowPlayingInfoCenter.default().nowPlayingInfo = nil; return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: np.surahHint ?? np.title,
            MPMediaItemPropertyArtist: np.subtitle,
            MPNowPlayingInfoPropertyIsLiveStream: np.isLive
        ]
    }
}
