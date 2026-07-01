public enum PlayerStatus: Sendable, Equatable { case idle, loading, playing, paused, reconnecting, failed(String) }

public struct NowPlaying: Sendable, Equatable {
    public var title: String
    public var subtitle: String
    public var isLive: Bool
    public var surahHint: String?
    /// Playback position in seconds. Meaningful for on-demand items; stays 0 for live.
    public var elapsed: Double = 0
    /// Total length in seconds. Meaningful for on-demand items; stays 0 for live.
    public var duration: Double = 0
    public init(title: String, subtitle: String, isLive: Bool, surahHint: String? = nil,
                elapsed: Double = 0, duration: Double = 0) {
        self.title = title; self.subtitle = subtitle; self.isLive = isLive; self.surahHint = surahHint
        self.elapsed = elapsed; self.duration = duration
    }
}
