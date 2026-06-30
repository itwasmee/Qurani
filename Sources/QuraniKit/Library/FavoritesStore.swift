import Foundation

/// The user's favorite reciters, persisted across launches as a JSON `[Int]` of reciter ids.
/// Every mutation writes the file back immediately. Backing load/save lives in `IntSetStore`.
@MainActor public final class FavoritesStore: ObservableObject {
    @Published public private(set) var reciterIDs: Set<Int> = []
    private let fileURL: URL

    /// Designated init: load favorites from `directory/favorites.json`
    /// (a missing or corrupt file loads as an empty set). The directory need not exist yet;
    /// it is created on first write. Injectable for tests.
    public init(directory: URL) {
        self.fileURL = directory.appendingPathComponent("favorites.json")
        self.reciterIDs = IntSetStore.load(fileURL)
    }

    /// Real path: `Application Support/Qurani/favorites.json`. The support directory is computed
    /// (and created) inside the call rather than defaulted as an argument.
    public convenience init() { self.init(directory: IntSetStore.applicationSupportDirectory()) }

    public func isFavorite(reciter id: Int) -> Bool { reciterIDs.contains(id) }

    /// Favorite the reciter if it isn't already, otherwise un-favorite it; persists immediately.
    public func toggle(reciter id: Int) {
        if reciterIDs.contains(id) { reciterIDs.remove(id) } else { reciterIDs.insert(id) }
        IntSetStore.save(reciterIDs, to: fileURL)
    }
}
