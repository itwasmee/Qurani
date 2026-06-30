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
    /// Reflect the just-emitted now-playing value. `@Published` fires in `willSet`,
    /// so callers must pass the *new* value — re-reading `engine.nowPlaying` here would
    /// observe the pre-change value (nil on first play, stale on stop).
    func update(_ np: NowPlaying?) {
        guard let np else { MPNowPlayingInfoCenter.default().nowPlayingInfo = nil; return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: np.surahHint ?? np.title,
            MPMediaItemPropertyArtist: np.subtitle,
            MPNowPlayingInfoPropertyIsLiveStream: np.isLive
        ]
        // NEW-1: on-demand items have a finite position, so publish duration + elapsed for the
        // lock screen / Control Center progress bar. Live streams have no finite length — leave
        // these unset so the system renders them as position-less.
        if !np.isLive {
            info[MPMediaItemPropertyPlaybackDuration] = np.duration
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = np.elapsed
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// Mirror the engine status into Control Center's transport state so play/pause
    /// renders correctly there. Same `willSet` caveat — caller passes the new status.
    func updatePlaybackState(_ status: PlayerStatus) {
        let state: MPNowPlayingPlaybackState
        switch status {
        case .playing, .loading: state = .playing   // buffering reads as play intent
        case .paused:            state = .paused
        case .idle, .failed:     state = .stopped
        }
        MPNowPlayingInfoCenter.default().playbackState = state
    }
}
