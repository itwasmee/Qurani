import Foundation

@MainActor public protocol AudioPlayer: AnyObject {
    func replace(url: URL)
    func play()
    func pause()
    var onStatus: ((Bool) -> Void)? { get set }
    var onStreamTitle: ((String) -> Void)? { get set }
    var volume: Float { get set }
}
