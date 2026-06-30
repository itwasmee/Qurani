import AVFoundation
import QuraniKit

@MainActor final class AVAudioPlayerAdapter: NSObject, AudioPlayer, AVPlayerItemMetadataOutputPushDelegate {
    var onStatus: ((Bool) -> Void)?
    var onStreamTitle: ((String) -> Void)?
    var volume: Float = 1.0 { didSet { player.volume = volume } }

    private let player = AVPlayer()
    private var timeObserver: Any?

    override init() {
        super.init()
        player.addObserver(self, forKeyPath: "timeControlStatus", options: [.new], context: nil)
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

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "timeControlStatus" {
            onStatus?(player.timeControlStatus == .playing)
        }
    }

    nonisolated func metadataOutput(_ output: AVPlayerItemMetadataOutput,
                                    didOutputTimedMetadataGroups groups: [AVTimedMetadataGroup],
                                    from track: AVPlayerItemTrack?) {
        let title = groups.flatMap(\.items)
            .first { ($0.commonKey?.rawValue == "title") || ($0.identifier?.rawValue.contains("StreamTitle") == true) }?
            .stringValue
        if let title { Task { @MainActor in self.onStreamTitle?(title) } }
    }
}
