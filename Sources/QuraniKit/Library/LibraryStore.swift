import Foundation

/// The user's imported local recitation files, persisted across launches as a JSON `[LocalTrack]`.
/// Every mutation writes the file back immediately (atomically). A missing file (first run) or a
/// corrupt one loads as an empty list rather than throwing into `init`.
///
/// Each track carries a security-scoped `bookmark`; `resolveURL(_:)` turns one back into a playable
/// URL and begins security-scoped access. The caller is responsible for calling
/// `stopAccessingSecurityScopedResource()` on the returned URL once it has finished reading.
@MainActor public final class LibraryStore: ObservableObject {
    @Published public private(set) var tracks: [LocalTrack]
    private let fileURL: URL

    /// Designated init: load tracks from `directory/library.json` (a missing or corrupt file loads
    /// as an empty list). The directory need not exist yet; it is created on first write. Injectable
    /// for tests.
    public init(directory: URL) {
        self.fileURL = directory.appendingPathComponent("library.json")
        self.tracks = Self.load(fileURL)
    }

    /// Real path: `Application Support/Qurani/library.json`. The support directory is computed
    /// (and created) inside the call rather than defaulted as an argument.
    public convenience init() { self.init(directory: IntSetStore.applicationSupportDirectory()) }

    /// Append the given tracks, skipping any whose `id` is already present, then persist.
    public func add(_ newTracks: [LocalTrack]) {
        var existing = Set(tracks.map(\.id))
        for t in newTracks where !existing.contains(t.id) {
            tracks.append(t)
            existing.insert(t.id)
        }
        save()
    }

    /// Remove the track with the given `id` (if present) and persist.
    public func remove(id: UUID) {
        tracks.removeAll { $0.id == id }
        save()
    }

    /// Tracks grouped by `reciterName`: each group's tracks sorted by `surahNumber` ascending, and
    /// the groups themselves sorted by reciter name.
    public func grouped() -> [(reciter: String, tracks: [LocalTrack])] {
        Dictionary(grouping: tracks, by: \.reciterName)
            .map { (reciter: $0.key, tracks: $0.value.sorted { $0.surahNumber < $1.surahNumber }) }
            .sorted { $0.reciter < $1.reciter }
    }

    /// Resolve a track's security-scoped bookmark back to a URL and begin security-scoped access.
    /// Returns `nil` (rather than throwing or crashing) if the bookmark can't be resolved — e.g. the
    /// synthetic `Data()` bookmarks used in tests, or a file that has since moved/been deleted. The
    /// caller must call `stopAccessingSecurityScopedResource()` on the returned URL when done.
    public func resolveURL(_ track: LocalTrack) -> URL? {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: track.bookmark,
                                 options: [.withSecurityScope],
                                 relativeTo: nil,
                                 bookmarkDataIsStale: &stale)
        else { return nil }
        _ = url.startAccessingSecurityScopedResource()
        return url
    }

    // MARK: - Persistence

    /// Decode a JSON `[LocalTrack]` file. A missing file (first run) or a corrupt/garbage file both
    /// yield an empty list rather than surfacing a throw.
    private static func load(_ url: URL) -> [LocalTrack] {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([LocalTrack].self, from: data)
        else { return [] }
        return decoded
    }

    /// Persist the tracks as a JSON `[LocalTrack]` array, writing atomically so a crash mid-write
    /// can't leave a half-written file behind. Creates the parent directory if it doesn't exist.
    private func save() {
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(tracks) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
