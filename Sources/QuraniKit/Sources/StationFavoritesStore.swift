import Foundation

/// Persistence for a `Set<String>` of station ids, stored on disk as a JSON `[String]`.
/// Stations use string ids (`makkah_haram`, `radio_7`, `sd_quran_digital`), so the Int-keyed
/// `IntSetStore` used for reciters doesn't fit. Same guarantees: a missing/corrupt file yields
/// an empty set, writes are atomic and sorted for a stable on-disk form.
enum StringSetStore {
    static func load(_ url: URL) -> Set<String> {
        guard let data = try? Data(contentsOf: url),
              let ids = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return Set(ids)
    }
    static func save(_ set: Set<String>, to url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(set.sorted()) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

/// The user's favorite live stations (featured / world / per-reciter), persisted across launches
/// as `station_favorites.json`. Favorited stations surface in a section at the top of the Live tab.
@MainActor public final class StationFavoritesStore: ObservableObject {
    @Published public private(set) var ids: Set<String> = []
    private let fileURL: URL

    /// Designated init: load from `directory/station_favorites.json` (missing/corrupt → empty).
    /// Injectable for tests; the directory is created on first write.
    public init(directory: URL) {
        self.fileURL = directory.appendingPathComponent("station_favorites.json")
        self.ids = StringSetStore.load(fileURL)
    }
    /// Real path: `Application Support/Qurani/station_favorites.json`.
    public convenience init() { self.init(directory: IntSetStore.applicationSupportDirectory()) }

    public func contains(_ id: String) -> Bool { ids.contains(id) }

    /// Favorite the station if it isn't already, otherwise un-favorite it; persists immediately.
    public func toggle(station id: String) {
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        StringSetStore.save(ids, to: fileURL)
    }
}
