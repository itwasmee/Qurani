import Foundation

/// A unit of playback the engine can load: either an open-ended live station, or a
/// finite on-demand surah recitation. `sourceID` is the stable identity used to drive
/// row highlights (so duplicate display titles never collide).
public enum PlaybackItem: Sendable, Equatable {
    case liveStation(Station)
    case onDemand(reciterName: String, surah: Surah, url: URL)

    public var isLive: Bool { if case .liveStation = self { return true }; return false }

    public var url: URL {
        switch self {
        case .liveStation(let s): return s.url
        case .onDemand(_, _, let u): return u
        }
    }

    public var sourceID: String {
        switch self {
        case .liveStation(let s): return "live:\(s.id)"
        case .onDemand(let r, let s, _): return "ondemand:\(r):\(s.number)"
        }
    }
}
