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

    /// Gate the hardware media keys / Control Center transport on the Settings "Media keys" toggle.
    /// The command *targets* stay registered (added once in `init`); flipping `.isEnabled` is the
    /// documented way to make the system ignore — and grey out — the play/pause commands without
    /// re-adding handlers, and toggling back on re-arms them. `MPNowPlayingInfoCenter` (the `update`
    /// / `updatePlaybackState` metadata below) is deliberately untouched, so the lock screen and
    /// Control Center keep *showing* what's playing even while the keys don't control it.
    func setMediaKeysEnabled(_ on: Bool) {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.isEnabled = on
        c.pauseCommand.isEnabled = on
        c.togglePlayPauseCommand.isEnabled = on
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
