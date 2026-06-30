import Foundation

public enum StationKind: String, Codable, Sendable { case hls, icecast }

public struct Station: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let region: String
    public let kind: StationKind
    public let url: URL
    public let reciter: String?
    public let hasVideo: Bool
    public init(id: String, name: String, region: String, kind: StationKind, url: URL, reciter: String? = nil, hasVideo: Bool = false) {
        self.id = id; self.name = name; self.region = region; self.kind = kind; self.url = url; self.reciter = reciter; self.hasVideo = hasVideo
    }
}
