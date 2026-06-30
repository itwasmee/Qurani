/// One resolved step in a built mix queue: which surah to play and which pool member
/// supplies it. `id` is the surah number — each surah appears at most once per queue,
/// so the surah doubles as a stable, unique identity for SwiftUI lists.
public struct MixQueueItem: Sendable, Equatable, Identifiable {
    public let surah: Int
    public let memberID: String
    public var id: Int { surah }
    public init(surah: Int, memberID: String) {
        self.surah = surah
        self.memberID = memberID
    }
}
