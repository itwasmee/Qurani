import AVFoundation
import QuraniKit

@MainActor final class AVAudioPlayerAdapter: NSObject, AudioPlayer, @preconcurrency AVPlayerItemMetadataOutputPushDelegate {
    var onStatus: ((Bool) -> Void)?
    var onStreamTitle: ((String) -> Void)?
    var onFailure: ((String) -> Void)?
    var volume: Float = 1.0 { didSet { player.volume = volume } }

    private let player = AVPlayer()
    private var statusObservation: NSKeyValueObservation?
    private var itemStatusObservation: NSKeyValueObservation?
    private var connectTimeout: Task<Void, Never>?

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
        armConnectTimeout()
    }
    func play() { player.play() }
    func pause() { connectTimeout?.cancel(); player.pause() }

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
