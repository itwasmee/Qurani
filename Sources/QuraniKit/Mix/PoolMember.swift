import Foundation

/// Where a pool member's audio comes from: a recording already in the local library,
/// or a surah fetched on demand from a reciter's moshaf on the server.
public enum PoolSource: String, Codable, Sendable {
    case local
    case onDemand
}

/// One entry in a mix pool: a reciter (optionally a specific moshaf) together with the
/// set of surahs it contributes. `reciterID`/`moshaf` are nil for purely-local members.
public struct PoolMember: Identifiable, Sendable, Equatable {
    public let id: String
    public let source: PoolSource
    public let displayName: String
    public let reciterName: String
    public let surahNumbers: Set<Int>
    public let reciterID: Int?
    public let moshaf: Moshaf?
    public init(
        id: String,
        source: PoolSource,
        displayName: String,
        reciterName: String,
        surahNumbers: Set<Int>,
        reciterID: Int?,
        moshaf: Moshaf?
    ) {
        self.id = id
        self.source = source
        self.displayName = displayName
        self.reciterName = reciterName
        self.surahNumbers = surahNumbers
        self.reciterID = reciterID
        self.moshaf = moshaf
    }
}
