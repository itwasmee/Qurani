import Foundation

/// Membership of the random-Mix pool, persisted across launches as a JSON `[Int]` of reciter ids.
/// This store tracks *which* reciters are in the pool only; the random Mix engine that draws from
/// it is Plan 4. Every mutation writes the file back immediately. Backing load/save lives in
/// `IntSetStore`.
@MainActor public final class MixPoolStore: ObservableObject {
    @Published public private(set) var reciterIDs: Set<Int> = []
    private let fileURL: URL

    /// Designated init: load the pool from `directory/mixpool.json`
    /// (a missing or corrupt file loads as an empty set). The directory need not exist yet;
    /// it is created on first write. Injectable for tests.
    public init(directory: URL) {
        self.fileURL = directory.appendingPathComponent("mixpool.json")
        self.reciterIDs = IntSetStore.load(fileURL)
    }

    /// Real path: `Application Support/Qurani/mixpool.json`. The support directory is computed
    /// (and created) inside the call rather than defaulted as an argument.
    public convenience init() { self.init(directory: IntSetStore.applicationSupportDirectory()) }

    public func contains(_ id: Int) -> Bool { reciterIDs.contains(id) }

    /// Add the reciter to the pool if absent, otherwise remove it; persists immediately.
    public func toggle(reciter id: Int) {
        if reciterIDs.contains(id) { reciterIDs.remove(id) } else { reciterIDs.insert(id) }
        IntSetStore.save(reciterIDs, to: fileURL)
    }
}
