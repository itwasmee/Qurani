import Foundation

/// Shared persistence for a `Set<Int>` of reciter ids, stored on disk as a JSON `[Int]` array.
/// `FavoritesStore` and `MixPoolStore` differ only in their public API and filename, so the
/// load/save mechanism lives here once. Reads never throw into a store (a missing or corrupt
/// file simply yields an empty set); writes are atomic so a crash mid-write can't leave a
/// half-written file behind.
enum IntSetStore {
    /// `Application Support/Qurani/`, created if missing. If Application Support is somehow
    /// unavailable, falls back to a temp directory rather than throwing into a store `init`.
    static func applicationSupportDirectory() -> URL {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)) ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("Qurani", isDirectory: true)
        ensureDirectory(dir)
        return dir
    }

    /// Decode a JSON `[Int]` file into a set. A missing file (first run) or a corrupt/garbage
    /// file both yield an empty set rather than surfacing a throw.
    static func load(_ url: URL) -> Set<Int> {
        guard let data = try? Data(contentsOf: url),
              let ids = try? JSONDecoder().decode([Int].self, from: data)
        else { return [] }
        return Set(ids)
    }

    /// Persist the set as a JSON `[Int]` array, writing atomically. Sorted for a stable,
    /// diff-friendly on-disk representation. Creates the parent directory if it doesn't exist.
    static func save(_ set: Set<Int>, to url: URL) {
        ensureDirectory(url.deletingLastPathComponent())
        guard let data = try? JSONEncoder().encode(set.sorted()) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private static func ensureDirectory(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
