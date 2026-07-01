import Foundation

@MainActor public final class PlaybackEngine: ObservableObject {
    @Published public private(set) var status: PlayerStatus = .idle
    @Published public private(set) var nowPlaying: NowPlaying?
    /// Identity of the item currently loaded, independent of display title.
    /// Used to drive the row highlight (duplicate titles must not collide).
    /// Format (one of three, per `PlaybackItem.sourceID`):
    ///   • `"live:<station.id>"`
    ///   • `"ondemand:<reciterID>:<moshafID>:<surahNumber>"`
    ///   • `"local:<track.id>"`   (the `LocalTrack`'s UUID; `NowPlayingBar` keys the 📚 chip on this prefix)
    @Published public private(set) var currentSourceID: String?
    @Published public var volume: Float = 1.0 { didSet { player.volume = volume } }

    /// Fired when the current item plays to its end. Unused for live radio; consumed by the
    /// Mix engine (Plan 4) to advance to the next pool entry.
    public var onFinish: (() -> Void)?

    private let player: AudioPlayer
    private var surahs: [Surah] = []
    private var current: PlaybackItem?

    // MARK: Live auto-reconnect
    /// Decides whether a dropped/stalled LIVE stream should silently reconnect, and the backoff
    /// between attempts. Pure + injectable so the decision is unit-testable (see `LiveReconnectTests`).
    private let reconnect: LiveReconnectPolicy
    /// Silent reconnects already spent on the current live drop. Reset to 0 the moment playback
    /// resumes (`onStatus(true)`) or a new item is played; once it reaches `reconnect.maxAttempts`
    /// the next failure falls through to `.failed`.
    private var reconnectAttempts = 0
    /// The in-flight backoff-then-retry task, if any. Cancelled on stop / new play / user pause so a
    /// pending reconnect never fires for an item the listener already moved on from.
    private var reconnectTask: Task<Void, Never>?
    /// The backoff wait, injected so tests need not wait real seconds. Cancellation propagates
    /// through it (a cancelled `Task.sleep` throws, which the identity guard below then short-circuits).
    private let backoffSleep: @Sendable (Duration) async -> Void

    public init(player: AudioPlayer,
                reconnect: LiveReconnectPolicy = .init(),
                backoffSleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }) {
        self.player = player
        self.reconnect = reconnect
        self.backoffSleep = backoffSleep
        self.player.onStatus = { [weak self] isPlaying in
            guard let self else { return }
            if isPlaying {
                // Playback resumed — a first connect OR a recovered live drop — so the reconnect
                // budget is fresh again.
                self.reconnectAttempts = 0
                self.status = .playing
            } else if self.status != .reconnecting {
                // A not-playing tick that lands mid-reconnect is the stream still catching up, not a
                // user pause — keep showing "Reconnecting…". Genuine pauses set `.paused` explicitly
                // (see `toggle`/`stop`).
                self.status = .paused
            }
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
            guard let self, self.currentSourceID != nil, let item = self.current else { return }
            // LIVE streams drop/stall routinely; try a few silent reconnects (with backoff) before
            // surfacing the retry bar. On-demand/local finite items never reconnect — a stopped surah
            // is finished or genuinely broken — so those fall straight through to `.failed` as before.
            if self.reconnect.shouldReconnect(sourceID: self.currentSourceID, attemptsUsed: self.reconnectAttempts) {
                self.scheduleReconnect(item)
            } else {
                self.cancelReconnect()
                self.status = .failed(reason)
            }
        }
        self.player.onTime = { [weak self] el, du in
            // Only on-demand items have a meaningful position. A live stream's player still
            // ticks ~2×/s; gating on `!isLive` keeps live elapsed/duration at 0 and avoids
            // churning `@Published nowPlaying` (and the scrubber) for an open-ended stream.
            guard let self, var np = self.nowPlaying, !np.isLive else { return }
            np.elapsed = el; np.duration = du; self.nowPlaying = np
        }
        self.player.onFinish = { [weak self] in self?.onFinish?() }
    }

    public func attachSurahs(_ s: [Surah]) { surahs = s }

    public func play(_ item: PlaybackItem) {
        // A brand-new play supersedes any live reconnect in flight and starts with a full budget.
        cancelReconnect()
        reconnectAttempts = 0
        load(item, status: .loading)
    }

    /// Load `item` into the player and reflect it in `nowPlaying`/`currentSourceID`, entering
    /// `newStatus`. Shared by `play` (fresh, `.loading`) and the auto-reconnect path (`.reconnecting`)
    /// so a reconnect re-issues the exact same item — rebuilding the AVPlayerItem from the same URL —
    /// without disturbing the attempt counter.
    private func load(_ item: PlaybackItem, status newStatus: PlayerStatus) {
        current = item
        currentSourceID = item.sourceID
        status = newStatus
        switch item {
        case .liveStation(let station):
            nowPlaying = NowPlaying(title: station.name,
                                    subtitle: station.reciter ?? station.region,
                                    isLive: true, surahHint: nil)
        case .onDemand(_, let reciterName, _, let surah, _):
            nowPlaying = NowPlaying(title: surah.nameAr,
                                    subtitle: reciterName,
                                    isLive: false, surahHint: nil)
        case .localTrack(let track, _):
            let title = surahs.first { $0.number == track.surahNumber }?.nameAr
                ?? "Surah \(track.surahNumber)"
            nowPlaying = NowPlaying(title: title,
                                    subtitle: track.reciterName,
                                    isLive: false, surahHint: nil)
        }
        player.replace(url: item.url)
        player.volume = volume
        player.play()
    }

    /// Convenience for live-radio playback — preserves the pre-Plan-2 call shape.
    public func playStation(_ s: Station) { play(.liveStation(s)) }

    public func toggle() {
        // NEW-3: an on-demand item that already played to its end leaves the player parked at
        // its tail (real players don't auto-rewind). A tap on play/pause should then restart it
        // from the top, not flip pause state. Detect "at end" from the last position tick
        // (elapsed ≈ duration, with a real finite duration — never true for live).
        if current != nil, isAtEnd {
            player.seek(toFraction: 0)
            player.play()
            return
        }
        switch status {
        case .playing: player.pause()
        case .paused, .idle: if current != nil { player.play() }
        case .reconnecting:
            // Tapping the transport during an auto-reconnect means "stop trying" — cancel the
            // pending retry and park paused rather than letting a zombie reconnect fire later.
            cancelReconnect()
            reconnectAttempts = 0
            status = .paused
            player.pause()
        default: break
        }
    }

    /// Whether the current on-demand item is parked within ~0.5 s of its end, per the last
    /// `onTime` tick recorded in `nowPlaying`. Always false for live (duration stays 0).
    private var isAtEnd: Bool {
        guard let np = nowPlaying, !np.isLive, np.duration > 0 else { return false }
        return np.elapsed >= np.duration - 0.5
    }

    /// Scrub the current item to `f` (0…1) of its duration. Delegates to the player; a
    /// no-op for live items (no finite duration).
    public func seek(toFraction f: Double) { player.seek(toFraction: f) }

    /// Re-attempt the current item after a failure (drives the now-playing retry tap). Routes through
    /// `play`, so a manual retry also clears the live reconnect counter (fresh budget).
    public func retry() {
        if let current { play(current) }
    }

    public func stop() {
        cancelReconnect()
        reconnectAttempts = 0
        player.pause()
        status = .idle
        nowPlaying = nil
        current = nil
        currentSourceID = nil
    }

    // MARK: Reconnect internals

    /// Spend one reconnect attempt: after `reconnect.backoff` (waited off the main actor), re-issue
    /// the same live `item` — but only if it's still the loaded item (guarding against a stop / station
    /// switch that happened during the wait) and the task wasn't cancelled.
    private func scheduleReconnect(_ item: PlaybackItem) {
        reconnectAttempts += 1
        let delay = reconnect.backoff(forAttempt: reconnectAttempts)
        let targetID = item.sourceID
        status = .reconnecting
        reconnectTask?.cancel()
        reconnectTask = Task { @MainActor [weak self] in
            guard let sleep = self?.backoffSleep else { return }
            await sleep(delay)
            guard let self, !Task.isCancelled else { return }
            // Identity guard: the same live station must still be loaded (item-identity discipline,
            // mirroring the adapter's `currentItem ===` checks). A superseded item is a no-op.
            guard self.current == item, self.currentSourceID == targetID else { return }
            self.load(item, status: .reconnecting)
        }
    }

    private func cancelReconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
    }

    // Cancel any in-flight reconnect if the engine goes away (mirrors the adapter's isolated deinit).
    isolated deinit { reconnectTask?.cancel() }

    // MARK: Test seams — module-internal, so `@testable` tests can settle/inspect the reconnect
    // deterministically while the app target (a separate module) can't see them.

    /// The in-flight reconnect task; tests `await` its `.value` to settle the backoff+retry
    /// without polling.
    var reconnectTaskForTesting: Task<Void, Never>? { reconnectTask }
    /// Silent reconnects spent on the current live drop (0 after a resume or a new play).
    var reconnectAttemptsForTesting: Int { reconnectAttempts }
}
