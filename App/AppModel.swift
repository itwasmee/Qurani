import SwiftUI
import Combine
import QuraniKit

@MainActor final class AppModel: ObservableObject {
    let engine: PlaybackEngine
    let sources: SourcesStore
    let catalog = CatalogStore()
    let favorites: FavoritesStore
    let pool: MixPoolStore
    let library: LibraryStore
    /// Owns the import pipeline (Add-files panel, drag-drop, watched folder). Holds the
    /// `pendingImports` the review sheet (Task 7) confirms; observe it directly from views.
    let importer: LibraryImporter
    @Published var surahs: [Surah] = []

    // App-lifetime singletons: created exactly once in `init` (see C1). `bootstrap()`
    // runs from `.task{}`, which re-fires on every panel open — building the bridge or
    // re-registering the hotkey there would stack duplicate command targets/handlers.
    private let bridge: NowPlayingBridge
    private var cancellables: Set<AnyCancellable> = []
    private var didLoad = false

    /// `storesDirectory` redirects the persisted stores (favorites / pool / library) to a given
    /// directory — nil uses the real Application Support path. Snapshots and tests pass a throwaway
    /// directory so rendering the Mix/Library/Explore tabs never reads or mutates the user's data.
    init(storesDirectory: URL? = nil) {
        let engine = PlaybackEngine(player: AVAudioPlayerAdapter())
        self.engine = engine
        self.sources = SourcesStore()
        self.bridge = NowPlayingBridge(engine: engine)
        if let dir = storesDirectory {
            self.favorites = FavoritesStore(directory: dir)
            self.pool = MixPoolStore(directory: dir)
            self.library = LibraryStore(directory: dir)
        } else {
            self.favorites = FavoritesStore()
            self.pool = MixPoolStore()
            self.library = LibraryStore()
        }
        self.importer = LibraryImporter(library: library)

        // Register media-key / remote-command targets and the global hotkey once.
        Hotkeys.register(engine)

        // Keep Now Playing + Control Center transport state in sync. Pass the emitted
        // value (I1): @Published fires in willSet, so re-reading would be stale.
        engine.$nowPlaying
            .sink { [bridge] np in bridge.update(np) }
            .store(in: &cancellables)
        engine.$status
            .sink { [bridge] status in bridge.updatePlaybackState(status) }
            .store(in: &cancellables)
    }

    func bootstrap() async {
        guard !didLoad else { return }   // async data load is one-shot too
        didLoad = true
        surahs = (try? QuranData.loadSurahs()) ?? []
        engine.attachSurahs(surahs)
        importer.surahs = surahs
        importer.startWatching()   // best-effort; a no-op until a library folder is granted
        try? sources.loadFeatured()
        await sources.loadReciterStations { try await SourcesStore.fetchRadios() }
        await catalog.load { try await CatalogStore.fetchReciters() }
    }

    /// Start finite playback of a single surah recitation. Builds the per-surah audio URL
    /// from the moshaf's server base, then hands a `.onDemand` item to the engine.
    func playOnDemand(reciter: Reciter, moshaf: Moshaf, surah: Surah) {
        if isMixing { stopMix() }   // an explicit single play ends any active random-mix session
        let url = CatalogService.audioURL(serverBase: moshaf.serverBase, surah: surah.number)
        engine.play(.onDemand(reciterID: reciter.id, reciterName: reciter.name,
                              moshafID: moshaf.id, surah: surah, url: url))
    }

    /// Play a library-imported local file. Resolving the track's security-scoped bookmark begins
    /// access (held for the session — released when the process exits); a track whose file has since
    /// moved or been deleted resolves to `nil` and is a no-op rather than a crash.
    func playLocal(_ track: LocalTrack) {
        guard let url = library.resolveURL(track) else { return }
        if isMixing { stopMix() }   // an explicit single play ends any active random-mix session
        engine.play(.localTrack(track: track, url: url))
    }

    /// Commit the review sheet's confirmed imports to the library, then drop them from the pending
    /// list. Each `ReviewedImport` pairs with its `PendingImport` by id to recover the security-scoped
    /// bookmark, confidence, and duration captured at import time.
    func commitImports(_ reviewed: [ReviewedImport]) {
        let byID = Dictionary(importer.pendingImports.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let tracks = reviewed.compactMap { r -> LocalTrack? in
            guard let pending = byID[r.pendingID] else { return nil }
            return LocalTrack(bookmark: pending.bookmark, reciterName: r.reciterName,
                              surahNumber: r.surahNumber, confidence: pending.guess.confidence,
                              durationMs: pending.durationMs)
        }
        library.add(tracks)
        importer.clearPending(ids: Set(reviewed.map(\.pendingID)))
    }

    // MARK: - Mix session
    //
    // The Mix is a random per-surah "station": each surah in the configured range is played
    // by one randomly-chosen pool member that actually contributes it. The pure assignment
    // lives in `MixEngine.buildQueue`; this orchestration owns the live session — building the
    // pool from the catalog/library, walking the queue as items finish, and re-rolling/stopping.

    /// True while a Mix session is active (drives the Mix tab's play/stop affordance).
    @Published var isMixing = false
    /// The resolved per-surah playback order for the current session; empty when not mixing.
    @Published private(set) var mixQueue: [MixQueueItem] = []
    /// Index into `mixQueue` of the item currently playing. Published so the Mix playing list can
    /// highlight (and follow) the active row as the session advances.
    @Published private(set) var mixIndex = 0
    /// Config + pool the session was started with, retained so `rerollMix()` can rebuild. `mixConfig`
    /// is readable so the playing header can label the order + range.
    private(set) var mixConfig = MixConfig()
    private var mixPool: [PoolMember] = []

    /// Surah + member display-name of the item that plays after the current one, or nil at the
    /// tail of the queue. Powers the "up next" hint in the Mix UI; member resolved via the pool.
    var mixUpNext: (surah: Int, memberName: String)? {
        let next = mixIndex + 1
        guard mixQueue.indices.contains(next) else { return nil }
        let item = mixQueue[next]
        let name = mixMember(item.memberID)?.displayName ?? item.memberID
        return (surah: item.surah, memberName: name)
    }

    /// The pool member assigned to a queue row, by id — lets the Mix playing list render each row's
    /// reciter `displayName` + source badge. Nil if the id isn't in the current pool.
    func mixMember(_ id: String) -> PoolMember? { mixPool.first { $0.id == id } }

    /// Assemble the mix pool from the user's selections: one on-demand member per catalog reciter
    /// in `onDemandIDs` (using its first/primary moshaf), plus one local member per library reciter
    /// name in `localNames`. A member's `surahNumbers` is the set it can actually supply, which
    /// `MixEngine` consults to skip surahs no member covers.
    func buildPool(onDemandIDs: Set<Int>, localNames: Set<String>) -> [PoolMember] {
        var members: [PoolMember] = []
        for r in catalog.reciters where onDemandIDs.contains(r.id) {
            guard let m = r.moshafs.first else { continue }
            members.append(PoolMember(id: "od:\(r.id):\(m.id)", source: .onDemand,
                                      displayName: r.name, reciterName: r.name,
                                      surahNumbers: Set(m.surahNumbers),
                                      reciterID: r.id, moshaf: m))
        }
        for group in library.grouped() where localNames.contains(group.reciter) {
            members.append(PoolMember(id: "local:\(group.reciter)", source: .local,
                                      displayName: group.reciter, reciterName: group.reciter,
                                      surahNumbers: Set(group.tracks.map(\.surahNumber)),
                                      reciterID: nil, moshaf: nil))
        }
        return members
    }

    /// Begin a Mix session with the given config over the given pool. Builds the queue, wires the
    /// engine's finish callback to advance through it, and starts at the top. A pool that covers no
    /// surah in range yields an empty queue and a no-op (isMixing stays false).
    func startMix(config: MixConfig, pool: [PoolMember]) {
        mixConfig = config
        mixPool = pool
        rebuildQueue()
        mixIndex = 0
        // No covered surah → no session: tear down any prior one rather than just clearing the flag.
        guard !mixQueue.isEmpty else { stopMix(); return }
        isMixing = true
        engine.onFinish = { [weak self] in self?.advanceMix() }
        playMixIndex(0)
    }

    /// Load and play the queue item at `i`, resolving its pool member to a `PlaybackItem`:
    /// on-demand members stream their moshaf's per-surah URL; local members resolve the matching
    /// `LocalTrack`'s bookmark. Any unresolvable item — a member missing from the pool, an on-demand
    /// surah absent from the loaded data, or a local track that no longer resolves (moved/deleted) —
    /// is skipped to the next item rather than stalling the session. `mixIndex` is committed up front
    /// so those skips advance from `i` (not the previously-played index).
    private func playMixIndex(_ i: Int) {
        guard mixQueue.indices.contains(i) else { return }
        mixIndex = i
        let item = mixQueue[i]
        guard let member = mixPool.first(where: { $0.id == item.memberID }) else { advanceMix(); return }
        switch member.source {
        case .onDemand:
            guard let surah = surahs.first(where: { $0.number == item.surah }) else { advanceMix(); return }
            // moshaf/reciterID are non-nil for every on-demand member `buildPool` emits.
            let url = CatalogService.audioURL(serverBase: member.moshaf!.serverBase, surah: item.surah)
            engine.play(.onDemand(reciterID: member.reciterID!, reciterName: member.reciterName,
                                  moshafID: member.moshaf!.id, surah: surah, url: url))
        case .local:
            guard let track = library.tracks.first(where: {
                      $0.reciterName == member.reciterName && $0.surahNumber == item.surah
                  }),
                  let url = library.resolveURL(track)
            else { advanceMix(); return }
            engine.play(.localTrack(track: track, url: url))
        }
    }

    /// Advance to the next queue item when the current one finishes; stop the session at the tail.
    /// Invoked by `engine.onFinish` and (later) the Mix UI's skip control.
    func advanceMix() {
        let next = mixIndex + 1
        if mixQueue.indices.contains(next) {
            playMixIndex(next)
        } else {
            stopMix()
        }
    }

    /// Re-roll the session: rebuild the queue from the same pool + config with a fresh random
    /// assignment and ordering, then restart from the top of the new queue.
    func rerollMix() {
        guard isMixing else { return }   // no-op without an active session to re-roll
        rebuildQueue()
        mixIndex = 0
        playMixIndex(0)
    }

    /// Tear down the session: clear the finish callback (so a final natural finish can't re-enter),
    /// stop the engine, and empty the queue.
    func stopMix() {
        isMixing = false
        engine.onFinish = nil
        engine.stop()
        mixQueue = []
    }

    /// Rebuild `mixQueue` from the retained `mixPool` + `mixConfig` using system-RNG randomness.
    /// The surah→juz map (consulted only for `.juz` ranges) is derived from the loaded `surahs`.
    private func rebuildQueue() {
        let surahJuz = Dictionary(surahs.map { ($0.number, $0.juz) }, uniquingKeysWith: { first, _ in first })
        mixQueue = MixEngine.buildQueue(pool: mixPool, config: mixConfig, surahJuz: surahJuz,
                                        pickIndex: { Int.random(in: 0..<$0) },
                                        shuffle: { $0.shuffled() })
    }

    /// Seed an active Mix session's display state directly, bypassing `startMix` (no engine, no
    /// audio) — for snapshots / tests of the playing list. Mirrors `LibraryImporter.seedPending`.
    func seedMix(queue: [MixQueueItem], pool: [PoolMember], index: Int) {
        mixPool = pool
        mixQueue = queue
        mixIndex = index
        isMixing = true
    }
}
