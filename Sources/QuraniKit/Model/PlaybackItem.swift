import Foundation

/// A unit of playback the engine can load: either an open-ended live station, or a
/// finite on-demand surah recitation. `sourceID` is the stable identity used to drive
/// row highlights (so duplicate display titles never collide).
public enum PlaybackItem: Sendable, Equatable {
    case liveStation(Station)
    case onDemand(reciterID: Int, reciterName: String, moshafID: Int, surah: Surah, url: URL)

    public var isLive: Bool { if case .liveStation = self { return true }; return false }

    public var url: URL {
        switch self {
        case .liveStation(let s): return s.url
        case .onDemand(_, _, _, _, let u): return u
        }
    }

    /// Identity is keyed on `reciterID`/`moshafID` (not the display name): two reciters can
    /// share a name, and one reciter's riwayat differ per moshaf — ids keep highlights and the
    /// Mix engine from colliding.
    public var sourceID: String {
        switch self {
        case .liveStation(let s): return "live:\(s.id)"
        case .onDemand(let reciterID, _, let moshafID, let surah, _):
            return "ondemand:\(reciterID):\(moshafID):\(surah.number)"
        }
    }
}
