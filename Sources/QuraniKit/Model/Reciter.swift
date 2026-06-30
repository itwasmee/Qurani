import Foundation

/// A single riwaya/recording set for a reciter (mp3quran "moshaf"). `serverBase` is the
/// directory URL audio files hang off of; `surahNumbers` is which surahs this moshaf offers.
public struct Moshaf: Codable, Sendable, Equatable, Identifiable {
    public let id: Int
    public let name: String
    public let serverBase: URL
    public let surahNumbers: [Int]
    public init(id: Int, name: String, serverBase: URL, surahNumbers: [Int]) {
        self.id = id; self.name = name; self.serverBase = serverBase; self.surahNumbers = surahNumbers
    }
}

/// A reciter (qari) and their available moshafs.
public struct Reciter: Codable, Sendable, Equatable, Identifiable {
    public let id: Int
    public let name: String
    public let moshafs: [Moshaf]
    public init(id: Int, name: String, moshafs: [Moshaf]) {
        self.id = id; self.name = name; self.moshafs = moshafs
    }
}
