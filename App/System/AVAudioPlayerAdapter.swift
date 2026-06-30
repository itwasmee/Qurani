import AVFoundation
import QuraniKit

@MainActor final class AVAudioPlayerAdapter: NSObject, AudioPlayer, @preconcurrency AVPlayerItemMetadataOutputPushDelegate {
    var onStatus: ((Bool) -> Void)?
    var onStreamTitle: ((String) -> Void)?
    var volume: Float = 1.0 { didSet { player.volume = volume } }

    private let player = AVPlayer()
    private var statusObservation: NSKeyValueObservation?

    override init() {
        super.init()
        statusObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            let playing = player.timeControlStatus == .playing
            Task { @MainActor in self?.onStatus?(playing) }
        }
    }

    func replace(url: URL) {
        let item = AVPlayerItem(url: url)
        let md = AVPlayerItemMetadataOutput(identifiers: nil)
        md.setDelegate(self, queue: .main)
        item.add(md)
        player.replaceCurrentItem(with: item)
    }
    func play() { player.play() }
    func pause() { player.pause() }

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
