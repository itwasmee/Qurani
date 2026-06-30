import Foundation

@MainActor public protocol AudioPlayer: AnyObject {
    func replace(url: URL)
    func play()
    func pause()
    /// Seek the current item to `f` (0…1) of its duration. A no-op for items with no
    /// finite duration (live streams).
    func seek(toFraction f: Double)
    var onStatus: ((Bool) -> Void)? { get set }
    var onStreamTitle: ((String) -> Void)? { get set }
    /// Fired with a human-readable reason when the underlying stream fails to load,
    /// stalls, or times out. Live streams die routinely, so this is a first-class channel.
    var onFailure: ((String) -> Void)? { get set }
    /// Periodic playback position: `(elapsed, duration)` in seconds. `duration` is 0 when
    /// the item has no finite length (live). Drives the on-demand scrubber.
    var onTime: ((Double, Double) -> Void)? { get set }
    /// Fired once when the current item plays to its end.
    var onFinish: (() -> Void)? { get set }
    var volume: Float { get set }
}
