/// Builds the random per-surah playback queue that drives a mix — the app's signature
/// algorithm. For each surah in the configured range (kept in order or shuffled), one
/// pool member that actually contributes that surah is chosen uniformly at random; surahs
/// that no member covers are skipped.
///
/// Randomness is **injected** so the result is deterministic for given closures: the engine
/// touches no `Date`, `random`, or global state. The app passes a system-RNG-backed
/// `pickIndex`/`shuffle`; tests pass fixed permutations and indices.
public enum MixEngine {
    /// - Parameters:
    ///   - pool: the available members, each declaring which `surahNumbers` it contributes.
    ///   - config: ordering (`inOrder`/`shuffle`) and surah range (`full`/`juz`/`custom`).
    ///   - surahJuz: surah-number → juz-number, consulted only for `.juz` ranges.
    ///   - pickIndex: given the number of candidate members for a surah, returns an index
    ///     in `0..<count` selecting one of them.
    ///   - shuffle: given the in-order surah-number list, returns a permutation of it
    ///     (used only when `config.order == .shuffle`).
    /// - Returns: one `MixQueueItem` per covered surah, in playback order.
    public static func buildQueue(
        pool: [PoolMember],
        config: MixConfig,
        surahJuz: [Int: Int],
        pickIndex: (Int) -> Int,
        shuffle: ([Int]) -> [Int]
    ) -> [MixQueueItem] {
        // 1. Surah-number list for the configured range (always ascending here).
        let surahs: [Int]
        switch config.range {
        case .full:
            surahs = Array(1...114)
        case .custom(let range):
            surahs = Array(range)
        case .juz(let juz):
            surahs = (1...114).filter { surahJuz[$0] == juz }
        }

        // 2. Apply ordering.
        let ordered: [Int]
        switch config.order {
        case .inOrder:
            ordered = surahs
        case .shuffle:
            ordered = shuffle(surahs)
        }

        // 3. Assign one covering member per surah; skip surahs no member contributes.
        var queue: [MixQueueItem] = []
        queue.reserveCapacity(ordered.count)
        for surah in ordered {
            let candidates = pool.filter { $0.surahNumbers.contains(surah) }
            guard !candidates.isEmpty else { continue }
            let member = candidates[pickIndex(candidates.count)]
            queue.append(MixQueueItem(surah: surah, memberID: member.id))
        }
        return queue
    }
}
