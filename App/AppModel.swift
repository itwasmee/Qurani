import SwiftUI
import Combine
import QuraniKit

@MainActor final class AppModel: ObservableObject {
    let engine: PlaybackEngine
    let sources: SourcesStore
    let catalog = CatalogStore()
    /// Favorited live stations (string ids across featured/world/reciter feeds); surfaced in a
    /// section at the top of the Live tab. Uses the real Application Support path.
    let stationFavorites = StationFavoritesStore()
    let favorites: FavoritesStore
    let pool: MixPoolStore
    let library: LibraryStore
    /// Owns the import pipeline (Add-files panel, drag-drop, watched folder). Holds the
    /// `pendingImports` the review sheet (Task 7) confirms; observe it directly from views.
    let importer: LibraryImporter
    /// User preferences shown in the Settings screen (media-keys + auto-import toggles). Persisted
    /// like the other stores; observed directly by `SettingsView`.
    let settings: SettingsStore
    @Published var surahs: [Surah] = []

    /// Explore deep-link request: set to a reciter id to ask the Explore tab to open that reciter's
    /// detail page. Driven by tapping the now-playing bar while an on-demand item plays — `GlassPanel`
    /// sets it alongside switching to the Explore tab, and `ExploreTabView` watches it, opens the
    /// matching reciter from `catalog.reciters`, then clears it back to nil. nil == no pending request.
    @Published var exploreFocusReciterID: Int?

    // App-lifetime singletons: created exactly once in `init` (see C1). `bootstrap()`
    // runs from `.task{}`, which re-fires on every panel open — building the bridge or
    // re-registering the hotkey there would stack duplicate command targets/handlers.
    private let bridge: NowPlayingBridge
    private var cancellables: Set<AnyCancellable> = []
    private var didLoad = false

    /// Production: the persisted stores (favorites / pool / library / settings) use the real
    /// Application Support path.
    convenience init() {
        self.init(favorites: FavoritesStore(), pool: MixPoolStore(),
                  library: LibraryStore(), settings: SettingsStore())
    }

    #if DEBUG
    /// Snapshot/test seam: redirect the persisted stores to a throwaway `directory` so rendering the
    /// Mix/Library/Explore/Settings tabs never reads or mutates the user's real data. DEBUG-only — the
    /// seam must not ship in the release binary.
    convenience init(storesDirectory directory: URL) {
        self.init(favorites: FavoritesStore(directory: directory), pool: MixPoolStore(directory: directory),
                  library: LibraryStore(directory: directory), settings: SettingsStore(directory: directory))
    }
    #endif

    /// Designated init: wires the engine, Now Playing bridge, importer, hotkey, and Settings-driven
    /// system effects around the four persisted stores it is handed (real or throwaway).
    private init(favorites: FavoritesStore, pool: MixPoolStore, library: LibraryStore, settings: SettingsStore) {
        let engine = PlaybackEngine(player: AVAudioPlayerAdapter())
        self.engine = engine
        self.sources = SourcesStore()
        self.bridge = NowPlayingBridge(engine: engine)
        self.favorites = favorites
        self.pool = pool
        self.library = library
        self.settings = settings
        // Give the importer a live read of the Auto-import setting so `chooseLibraryFolder()` only
        // re-arms the watcher when auto-import is on (AppModel owns both the importer and settings).
        self.importer = LibraryImporter(library: library,
                                        autoImportEnabled: { [settings] in settings.autoImportEnabled })

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

        // Wire the two Settings toggles to their system effects. A `@Published` replays its current
        // value to each new sink on subscription (the same CurrentValueSubject semantics the
        // `engine.$nowPlaying` sink in `init` relies on to seed itself), so subscribing here both
        // applies the persisted state immediately and re-applies it on every later toggle — no
        // separate initial call needed. Subscribed inside the one-shot guard so a re-fired
        // `bootstrap()` (it runs from `.task{}`) can't stack duplicate sinks.
        settings.$mediaKeysEnabled
            .sink { [bridge] on in bridge.setMediaKeysEnabled(on) }
            .store(in: &cancellables)
        // Auto-import: arm / disarm the watched-folder DispatchSource. `startWatching()` self-guards
        // on a granted folder bookmark (best-effort — a no-op until the user picks a folder); toggling
        // off cancels the watch.
        settings.$autoImportEnabled
            .sink { [importer] on in
                if on { importer.startWatching() } else { importer.stopWatching() }
            }
            .store(in: &cancellables)

        // Hardware ⏮/⏭ (media keys / Control Center) drive mix skip; the buttons' enabled state is
        // refreshed from queue position as the mix advances/stops (see playMixIndex / stopMix).
        bridge.onNext = { [weak self] in self?.mixNext() }
        bridge.onPrevious = { [weak self] in self?.mixPrevious() }

        try? sources.loadFeatured()
        try? sources.loadWorld()
        await sources.loadReciterStations { try await SourcesStore.fetchRadios() }
        await catalog.load { try await CatalogStore.fetchReciters() }
    }

    /// Start finite playback of a single surah recitation. Builds the per-surah audio URL
    /// from the moshaf's server base, then hands a `.onDemand` item to the engine.
    func playOnDemand(reciter: Reciter, moshaf: Moshaf, surah: Surah) {
        if isMixing { stopMix() }   // an explicit single play ends any active random-mix session
        releaseLocalScope()         // switching to a streamed source — drop any held local file scope
        let url = CatalogService.audioURL(serverBase: moshaf.serverBase, surah: surah.number)
        engine.play(.onDemand(reciterID: reciter.id, reciterName: reciter.name,
                              moshafID: moshaf.id, surah: surah, url: url))
    }

    /// Play a library-imported local file. Resolving the track's security-scoped bookmark begins
    /// access; we retain the URL (see `retainLocalScope`) and release the prior local scope so distinct
    /// local plays don't accrue leaked scopes for the process lifetime. A track whose file has since
    /// moved or been deleted resolves to `nil` and is a no-op rather than a crash.
    func playLocal(_ track: LocalTrack) {
        guard let url = library.resolveURL(track) else { return }
        if isMixing { stopMix() }   // an explicit single play ends any active random-mix session
        retainLocalScope(url)       // release the prior local scope; keep at most one outstanding
        engine.play(.localTrack(track: track, url: url))
    }

    /// Play a live radio station. Routed through here (not `engine.playStation` directly) so an
    /// explicit live pick ends any active random-mix session — same contract as `playOnDemand` /
    /// `playLocal`. Without this, tapping a Live station while mixing leaves `isMixing` set (stale
    /// "up next" hint under a LIVE item, and a re-roll could hijack audio back off the station).
    func playStation(_ s: Station) {
        if isMixing { stopMix() }
        releaseLocalScope()   // switching to live — drop any held local file scope
        engine.playStation(s)
    }

    // MARK: - Local file scope
    //
    // `library.resolveURL` begins security-scoped access that the engine relies on while a local file
    // plays, but never stops it — so a distinct local play used to leak one scope per file for the
    // process lifetime. We retain the single resolved URL and release it before resolving the next
    // local item (and when switching to a non-local source or on mix teardown), keeping at most one
    // outstanding local scope at a time.

    /// The security-scoped local file URL currently held open (≤1 outstanding), or nil.
    private var scopedLocalURL: URL?

    /// Retain `url` as the held local scope, releasing the previous one first. (Resolving the same
    /// file twice begins access twice; stopping the prior reference rebalances to a single hold.)
    private func retainLocalScope(_ url: URL) {
        scopedLocalURL?.stopAccessingSecurityScopedResource()
        scopedLocalURL = url
    }

    /// Stop accessing the held local scope, if any.
    private func releaseLocalScope() {
        scopedLocalURL?.stopAccessingSecurityScopedResource()
        scopedLocalURL = nil
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
    /// Set when a non-empty pool selection builds an empty queue (no covered surah in the chosen
    /// range). The Mix tab surfaces a "no surahs in range" hint instead of tearing down whatever is
    /// currently playing. Cleared on a successful start.
    @Published var mixNoCoverage = false
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
    /// surah in range yields an empty queue: rather than stopping whatever is currently playing, this
    /// sets `mixNoCoverage` (the Mix tab's hint) and is otherwise a no-op (isMixing stays false).
    func startMix(config: MixConfig, pool: [PoolMember]) {
        mixConfig = config
        mixPool = pool
        rebuildQueue()
        mixIndex = 0
        // Non-empty selection but nothing in range covered → hint, don't tear down current audio.
        guard !mixQueue.isEmpty else { mixNoCoverage = true; return }
        mixNoCoverage = false
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
            releaseLocalScope()   // streamed item — drop any local file scope the prior item held
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
            retainLocalScope(url)   // release the prior local scope, hold this one (≤1 outstanding)
            engine.play(.localTrack(track: track, url: url))
        }
        bridge.setMixSkip(hasPrevious: mixHasPrevious, hasNext: mixHasNext)
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

    /// Skip forward to the next surah in the mix (⏭). Same as a natural finish — stops at the tail.
    func mixNext() { guard isMixing else { return }; advanceMix() }

    /// Skip back to the previous surah in the mix (⏮); no-op at the head of the queue.
    func mixPrevious() {
        guard isMixing else { return }
        let prev = mixIndex - 1
        if mixQueue.indices.contains(prev) { playMixIndex(prev) }
    }

    /// True when there is a previous/next item to skip to — drives the ⏮/⏭ enabled state.
    var mixHasPrevious: Bool { isMixing && mixQueue.indices.contains(mixIndex - 1) }
    var mixHasNext: Bool { isMixing && mixQueue.indices.contains(mixIndex + 1) }

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
        releaseLocalScope()   // drop any local file scope the mix was holding
        bridge.setMixSkip(hasPrevious: false, hasNext: false)
    }

    /// Rebuild `mixQueue` from the retained `mixPool` + `mixConfig` using system-RNG randomness.
    /// The surah→juz map (consulted only for `.juz` ranges) is derived from the loaded `surahs`.
    private func rebuildQueue() {
        let surahJuz = Dictionary(surahs.map { ($0.number, $0.juz) }, uniquingKeysWith: { first, _ in first })
        mixQueue = MixEngine.buildQueue(pool: mixPool, config: mixConfig, surahJuz: surahJuz,
                                        pickIndex: { Int.random(in: 0..<$0) },
                                        shuffle: { $0.shuffled() })
    }

    #if DEBUG
    /// Seed an active Mix session's display state directly, bypassing `startMix` (no engine, no
    /// audio) — for snapshots / tests of the playing list. Mirrors `LibraryImporter.seedPending`.
    /// DEBUG-only: the snapshot/test seam must not ship in the release binary.
    func seedMix(queue: [MixQueueItem], pool: [PoolMember], index: Int) {
        mixPool = pool
        mixQueue = queue
        mixIndex = index
        isMixing = true
    }
    #endif
}
