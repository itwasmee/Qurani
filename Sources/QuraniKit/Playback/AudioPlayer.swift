import Foundation

@MainActor public protocol AudioPlayer: AnyObject {
    func replace(url: URL)
    func play()
    func pause()
    var onStatus: ((Bool) -> Void)? { get set }
    var onStreamTitle: ((String) -> Void)? { get set }
    /// Fired with a human-readable reason when the underlying stream fails to load,
    /// stalls, or times out. Live streams die routinely, so this is a first-class channel.
    var onFailure: ((String) -> Void)? { get set }
    var volume: Float { get set }
}
