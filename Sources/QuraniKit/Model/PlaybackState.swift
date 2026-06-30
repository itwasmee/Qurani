public enum PlayerStatus: Sendable, Equatable { case idle, loading, playing, paused, failed(String) }

public struct NowPlaying: Sendable, Equatable {
    public var title: String
    public var subtitle: String
    public var isLive: Bool
    public var surahHint: String?
    public init(title: String, subtitle: String, isLive: Bool, surahHint: String? = nil) {
        self.title = title; self.subtitle = subtitle; self.isLive = isLive; self.surahHint = surahHint
    }
}
