/// User-tunable settings for how a mix plays: the ordering of pool members and which
/// portion (range) of the surahs to include.
public struct MixConfig: Sendable, Equatable {
    /// Playback order across the pool.
    public enum Order: Sendable, Equatable {
        case inOrder
        case shuffle
    }
    /// Which surahs of the pool to include.
    public enum Range: Sendable, Equatable {
        case full
        case juz(Int)
        case custom(ClosedRange<Int>)
    }
    public var order: Order = .shuffle
    public var range: Range = .full
    public init(order: Order = .shuffle, range: Range = .full) {
        self.order = order
        self.range = range
    }
}
