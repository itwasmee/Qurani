import Foundation

public enum RecentKind: String, Codable, Sendable { case live, onDemand, local }

/// One replayable entry in the "recently played" history. Holds primitives only (no model refs)
/// so it Codes cleanly; `AppModel` builds it from a play call and reconstructs the `PlaybackItem`
/// from these fields on replay. `sourceID` mirrors `PlaybackItem.sourceID` and is the dedupe key.
public struct RecentItem: Codable, Identifiable, Sendable, Equatable {
    public var id: String { sourceID }
    public let sourceID: String
    public let kind: RecentKind
    public let title: String
    public let subtitle: String
    // live
    public let stationID: String?
    // onDemand
    public let reciterID: Int?
    public let reciterName: String?
    public let moshafID: Int?
    public let serverBase: String?
    public let surahNumber: Int?
    // local
    public let trackID: String?

    public init(sourceID: String, kind: RecentKind, title: String, subtitle: String,
                stationID: String? = nil, reciterID: Int? = nil, reciterName: String? = nil,
                moshafID: Int? = nil, serverBase: String? = nil, surahNumber: Int? = nil,
                trackID: String? = nil) {
        self.sourceID = sourceID; self.kind = kind; self.title = title; self.subtitle = subtitle
        self.stationID = stationID; self.reciterID = reciterID; self.reciterName = reciterName
        self.moshafID = moshafID; self.serverBase = serverBase; self.surahNumber = surahNumber
        self.trackID = trackID
    }
}

/// The user's recently-played history, persisted as `recents.json`. Most-recent first, deduped by
/// `sourceID` (replaying an item moves it to the front), capped at `limit`.
@MainActor public final class RecentsStore: ObservableObject {
    @Published public private(set) var items: [RecentItem] = []
    private let fileURL: URL
    private let limit: Int

    public init(directory: URL, limit: Int = 20) {
        self.fileURL = directory.appendingPathComponent("recents.json")
        self.limit = limit
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([RecentItem].self, from: data) {
            self.items = decoded
        }
    }
    public convenience init() { self.init(directory: IntSetStore.applicationSupportDirectory()) }

    /// Record a play: drop any existing entry with the same `sourceID`, prepend, cap, persist.
    public func record(_ item: RecentItem) {
        items.removeAll { $0.sourceID == item.sourceID }
        items.insert(item, at: 0)
        if items.count > limit { items = Array(items.prefix(limit)) }
        save()
    }

    private func save() {
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
