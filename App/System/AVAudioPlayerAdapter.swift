import AVFoundation
import QuraniKit

@MainActor final class AVAudioPlayerAdapter: NSObject, AudioPlayer, @preconcurrency AVPlayerItemMetadataOutputPushDelegate {
    var onStatus: ((Bool) -> Void)?
    var onStreamTitle: ((String) -> Void)?
    var onFailure: ((String) -> Void)?
    var onTime: ((Double, Double) -> Void)?
    var onFinish: (() -> Void)?
    var volume: Float = 1.0 { didSet { player.volume = volume } }

    private let player = AVPlayer()
    private var statusObservation: NSKeyValueObservation?
    private var itemStatusObservation: NSKeyValueObservation?
    private var connectTimeout: Task<Void, Never>?
    /// Player-scoped periodic position observer; opaque token from `addPeriodicTimeObserver`.
    private var periodicObserver: Any?
    /// Item-scoped end-of-playback notification token.
    private var endObserverToken: (any NSObjectProtocol)?
    /// Position sampling cadence for the scrubber.
    private let timeObserverInterval = CMTime(seconds: 0.5, preferredTimescale: 600)

    /// If the stream hasn't begun playing within this window, treat it as a failure.
    private let connectTimeoutSeconds: UInt64 = 15

    override init() {
        super.init()
        statusObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            let playing = player.timeControlStatus == .playing
            Task { @MainActor in
                guard let self else { return }
                if playing { self.connectTimeout?.cancel() }   // connected — disarm the watchdog
                self.onStatus?(playing)
            }
        }
    }

    func replace(url: URL) {
        // Drop the previous item's position/end observers before swapping items, so a stale
        // periodic tick or end-notification can't outlive the item it described.
        teardownTimeObservers()
        let item = AVPlayerItem(url: url)
        // Observe item.status for hard load failures. KVO fires on an arbitrary thread,
        // so compute the Sendable reason String here, before hopping to the main actor
        // (same race-safe shape as the timeControlStatus observation above).
        itemStatusObservation = item.observe(\.status, options: [.new]) { [weak self] observedItem, _ in
            guard observedItem.status == .failed else { return }
            let reason = observedItem.error?.localizedDescription ?? "Stream unavailable"
            // A `.failed` callback for item A can land AFTER the user switched to station B
            // (which reassigned this observation). Re-validate identity on the main hop and
            // only fail if the failed item is still the player's current item.
            Task { @MainActor in
                guard let self, self.player.currentItem === observedItem else { return }
                self.fail(reason)
            }
        }
        let md = AVPlayerItemMetadataOutput(identifiers: nil)
        md.setDelegate(self, queue: .main)
        item.add(md)
        player.replaceCurrentItem(with: item)
        installTimeObservers(for: item)
        armConnectTimeout()
    }
    func play() { player.play() }
    func pause() { connectTimeout?.cancel(); player.pause() }

    func seek(toFraction f: Double) {
        guard let item = player.currentItem else { return }
        let total = item.duration.seconds
        // Live / not-yet-ready items report indefinite (NaN) or zero duration — seeking is
        // meaningless there, so ignore it rather than seek to NaN.
        guard total.isFinite, total > 0 else { return }
        // `min`/`max` propagate NaN (NaN compares unordered), so a NaN fraction would slip
        // through the clamp and produce a NaN seek time. Reject non-finite input up front.
        guard f.isFinite else { return }
        let clamped = min(max(f, 0), 1)
        player.seek(to: CMTime(seconds: total * clamped, preferredTimescale: 600))
    }

    /// Add the position sampler (player-scoped) and the end-of-item notification (scoped to
    /// `item`). Both deliver on `.main`, so the callbacks run on the main actor.
    private func installTimeObservers(for item: AVPlayerItem) {
        periodicObserver = player.addPeriodicTimeObserver(forInterval: timeObserverInterval, queue: .main) { [weak self] _ in
            // Delivered on `.main` → we're already on the main actor; assert it so the
            // isolated state below is reachable without an async hop.
            MainActor.assumeIsolated {
                guard let self else { return }
                let elapsed = self.player.currentTime().seconds
                let duration = self.player.currentItem?.duration.seconds ?? 0
                // Guard against the NaN/indefinite values AVPlayer reports before a finite
                // item is ready (and for live, where duration is indefinite → report 0).
                guard elapsed.isFinite else { return }
                self.onTime?(elapsed, duration.isFinite ? duration : 0)
            }
        }
        endObserverToken = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
        ) { [weak self] note in
            // The non-Sendable `Notification` must not cross the main-actor hop, so capture
            // the ended item's identity as a Sendable `ObjectIdentifier` first (same compute-
            // before-hop discipline as the item-status KVO above).
            let endedItemID = (note.object as? AVPlayerItem).map(ObjectIdentifier.init)
            MainActor.assumeIsolated {
                // A notification enqueued just before a `replace(url:)` could still land here;
                // only fire `onFinish` if the ended item is still the player's current item.
                guard let self, let endedItemID,
                      let current = self.player.currentItem,
                      ObjectIdentifier(current) == endedItemID else { return }
                self.onFinish?()
            }
        }
    }

    private func teardownTimeObservers() {
        if let periodicObserver {
            player.removeTimeObserver(periodicObserver)
            self.periodicObserver = nil
        }
        if let endObserverToken {
            NotificationCenter.default.removeObserver(endObserverToken)
            self.endObserverToken = nil
        }
    }

    // Runs on the main actor (the class is `@MainActor`) so it can reach the isolated
    // player/observer state; balances the observers added in `installTimeObservers`.
    isolated deinit { teardownTimeObservers() }

    private func armConnectTimeout() {
        connectTimeout?.cancel()
        connectTimeout = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: (self?.connectTimeoutSeconds ?? 15) * 1_000_000_000)
            guard let self, !Task.isCancelled, self.player.timeControlStatus != .playing else { return }
            self.fail("Connection timed out")
        }
    }

    private func fail(_ reason: String) {
        connectTimeout?.cancel()
        onFailure?(reason)
    }

    // The metadata delegate queue is `.main` (see `replace`), so callbacks arrive on the main
    // actor. The `@preconcurrency` on the protocol conformance (above) lets this `@MainActor`
    // method satisfy the otherwise-nonisolated delegate requirement, with a runtime main-actor
    // check that genuinely holds. Main-actor isolation keeps the non-Sendable `AVMetadataItem`s
    // confined to the main actor across the async string load; only the resulting `String` ever
    // reaches `onStreamTitle`. `.stringValue` is deprecated, so we use async `load(.stringValue)`.
    func metadataOutput(_ output: AVPlayerItemMetadataOutput,
                        didOutputTimedMetadataGroups groups: [AVTimedMetadataGroup],
                        from track: AVPlayerItemTrack?) {
        let candidates = groups.flatMap(\.items).filter {
            $0.commonKey?.rawValue == "title" || ($0.identifier?.rawValue.contains("StreamTitle") == true)
        }
        Task { @MainActor in
            for item in candidates {
                if let title = try? await item.load(.stringValue) {
                    self.onStreamTitle?(title)
                    return
                }
            }
        }
    }
}
