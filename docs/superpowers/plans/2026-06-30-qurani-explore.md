# Qurani — Plan 2: Explore (on-demand reciter catalog) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Browse the free mp3quran reciter catalog, stream any surah on demand with a working scrubber, and favorite / add reciters to the Mix pool.

**Architecture:** First pay down Plan 1's deferred debt — generalize `PlaybackEngine` from `Station`-only to a `PlaybackItem` enum and widen the `AudioPlayer` seam with time/seek/finish — so on-demand playback gets real progress. Then add a `CatalogService`/`CatalogStore` (mp3quran v3 REST), persisted `FavoritesStore`/`MixPoolStore`, and the Explore tab UI. Logic stays in `QuraniKit` (Swift Testing); UI in the app target.

**Tech Stack:** Swift 6, SwiftUI, AVFoundation, Combine, Swift Testing, XcodeGen.

## Global Constraints

- macOS 26.0+, Swift 6 `-strict-concurrency=complete`, **pristine build (zero source warnings)**. UI `@MainActor`.
- One third-party runtime dep stays `KeyboardShortcuts`. mp3quran v3 REST hit directly, no key.
- mp3quran v3 base `https://www.mp3quran.net/api/v3`; reciters at `/reciters?language=eng`; audio = `{moshaf.server}{NNN}.mp3` (NNN = 3-digit zero-padded surah). Some `server` are `http://` → upgrade to `https://`.
- Surah names Style-B (Amiri Quran + Noto Naskh medallion, vowelized) via the existing `SurahNameView`.
- No fabricated metadata. On-demand now-playing shows exact surah + reciter + real progress (`isLive=false`).
- Persist favorites / mix-pool as JSON in `Application Support/Qurani/`.
- Tests use Swift Testing. Commit after each task. `swift test`/`xcodebuild`/`git` run with the command sandbox disabled (env quirk); `gh api` works sandboxed.
- DO NOT build Library import/tagging (Plan 3) or the Mix random engine (Plan 4) — only the **pool membership** store + Explore's "add to pool" action belong here.

## File Structure

```
Sources/QuraniKit/
├── Model/
│   ├── PlaybackItem.swift        # NEW enum (liveStation | onDemand)
│   ├── Reciter.swift             # NEW Reciter + Moshaf
│   └── PlaybackState.swift       # MODIFY NowPlaying (+ elapsed/duration/progress)
├── Playback/
│   ├── AudioPlayer.swift         # MODIFY seam (+ onTime, seek, onFinish)
│   └── PlaybackEngine.swift      # MODIFY play(PlaybackItem), progress, seek, finish
├── Catalog/
│   ├── CatalogService.swift      # NEW decode reciters + audio URL builder
│   └── CatalogStore.swift        # NEW @MainActor: fetch/cache/search/filter
└── Library/
    ├── FavoritesStore.swift      # NEW persisted favorites
    └── MixPoolStore.swift        # NEW persisted reciter pool
App/
├── System/AVAudioPlayerAdapter.swift  # MODIFY (+ periodic time, seek, didPlayToEnd)
├── AppModel.swift                     # MODIFY (catalog, favorites, pool)
└── Views/
    ├── ExploreTabView.swift      # NEW reciter list + search + riwaya filter
    ├── ReciterDetailView.swift   # NEW surah list + actions
    ├── ReciterRow.swift          # NEW
    └── NowPlayingBar.swift       # MODIFY (scrubber for on-demand)
```

## Interfaces (locked)

```swift
public enum PlaybackItem: Sendable, Equatable {
    case liveStation(Station)
    case onDemand(reciterName: String, surah: Surah, url: URL)
    var isLive: Bool { if case .liveStation = self { true } else { false } }
    var sourceID: String   // stable id for highlight gating
}

// NowPlaying gains (keep title/subtitle/isLive/surahHint):
//   var elapsed: Double      // seconds
//   var duration: Double     // seconds (0 if unknown/live)

@MainActor public protocol AudioPlayer: AnyObject {
    func replace(url: URL); func play(); func pause()
    func seek(toFraction f: Double)
    var onStatus: ((Bool) -> Void)? { get set }
    var onStreamTitle: ((String) -> Void)? { get set }
    var onFailure: ((String) -> Void)? { get set }
    var onTime: ((_ elapsed: Double, _ duration: Double) -> Void)? { get set }
    var onFinish: (() -> Void)? { get set }
    var volume: Float { get set }
}

@MainActor public final class PlaybackEngine: ObservableObject {
    func play(_ item: PlaybackItem)        // replaces play(_ station:)
    func playStation(_ s: Station)         // convenience → play(.liveStation(s))
    func seek(toFraction f: Double)
    @Published private(set) var currentSourceID: String?   // replaces currentStationID
    var onFinish: (() -> Void)?            // hook for Mix (Plan 4); nil here
}

public struct Moshaf: Codable, Sendable, Equatable, Identifiable {
    public let id: Int; public let name: String; public let serverBase: URL; public let surahNumbers: [Int]
}
public struct Reciter: Codable, Sendable, Equatable, Identifiable {
    public let id: Int; public let name: String; public let moshafs: [Moshaf]
}
public enum CatalogService {
    static func decodeReciters(_ data: Data) throws -> [Reciter]   // mp3quran v3 shape, http→https
    static func audioURL(serverBase: URL, surah: Int) -> URL       // {base}{NNN}.mp3
}
@MainActor public final class CatalogStore: ObservableObject {
    @Published private(set) var reciters: [Reciter]
    func load(_ fetch: () async throws -> Data) async
    func filtered(search: String, riwaya: String?) -> [Reciter]
    static func fetchReciters() async throws -> Data
}

@MainActor public final class FavoritesStore: ObservableObject {
    @Published private(set) var reciterIDs: Set<Int>
    func toggle(reciter id: Int); func isFavorite(reciter id: Int) -> Bool
}
@MainActor public final class MixPoolStore: ObservableObject {     // membership only; engine is Plan 4
    @Published private(set) var reciterIDs: Set<Int>
    func toggle(reciter id: Int); func contains(_ id: Int) -> Bool
}
```

---

## Task 1: `PlaybackItem` + engine generalization

**Files:** Create `Sources/QuraniKit/Model/PlaybackItem.swift`; Modify `Sources/QuraniKit/Model/PlaybackState.swift`, `Sources/QuraniKit/Playback/PlaybackEngine.swift`; Test `Tests/QuraniKitTests/PlaybackEngineTests.swift`.

**Interfaces:** Produces `PlaybackItem`, `PlaybackEngine.play(_:)`/`playStation(_:)`, `currentSourceID`, `NowPlaying.elapsed/duration`.

- [ ] **Step 1: Failing tests** — add to `PlaybackEngineTests`:
```swift
@MainActor @Test func playsOnDemandItem() {
    let p = FakePlayer(); let e = PlaybackEngine(player: p)
    let s = Surah(number: 67, nameAr: "الْمُلْك", translit: "Al-Mulk", nameEn: "", ayahCount: 30, makki: true, juz: 29)
    let url = URL(string: "https://server.example/067.mp3")!
    e.play(.onDemand(reciterName: "Sudais", surah: s, url: url))
    #expect(p.lastURL == url)
    #expect(e.nowPlaying?.title == "الْمُلْك")
    #expect(e.nowPlaying?.subtitle == "Sudais")
    #expect(e.nowPlaying?.isLive == false)
    #expect(e.currentSourceID == "ondemand:Sudais:67")
}
@MainActor @Test func stationStillPlaysViaConvenience() {
    let p = FakePlayer(); let e = PlaybackEngine(player: p)
    let st = Station(id: "x", name: "Makkah", region: "Makkah", kind: .hls, url: URL(string:"https://e/x.m3u8")!, reciter: nil, hasVideo: true)
    e.playStation(st)
    #expect(e.currentSourceID == "live:x")
    #expect(e.nowPlaying?.isLive == true)
}
```
Update `FakePlayer` to add the new seam members (`seek`, `onTime`, `onFinish`) as no-ops/stored.

- [ ] **Step 2: Run, fails** — `swift test --filter PlaybackEngineTests` → compile error (no `PlaybackItem`).

- [ ] **Step 3: Implement.**
`PlaybackItem.swift`:
```swift
import Foundation
public enum PlaybackItem: Sendable, Equatable {
    case liveStation(Station)
    case onDemand(reciterName: String, surah: Surah, url: URL)
    public var isLive: Bool { if case .liveStation = self { return true }; return false }
    public var url: URL { switch self { case .liveStation(let s): return s.url; case .onDemand(_, _, let u): return u } }
    public var sourceID: String {
        switch self {
        case .liveStation(let s): return "live:\(s.id)"
        case .onDemand(let r, let s, _): return "ondemand:\(r):\(s.number)"
        }
    }
}
```
In `PlaybackState.swift` add to `NowPlaying`: `public var elapsed: Double = 0; public var duration: Double = 0` (extend the memberwise init with defaults).
In `PlaybackEngine.swift`: replace `play(_ station:)` with `play(_ item: PlaybackItem)` that sets `.loading`, builds `NowPlaying` (live → title=name, subtitle=reciter??region, isLive=true; onDemand → title=surah.nameAr, subtitle=reciterName, isLive=false), sets `currentSourceID = item.sourceID`, `player.replace(url: item.url)`, `player.volume = volume`, `player.play()`. Add `playStation(_ s:) { play(.liveStation(s)) }`. Rename `currentStationID`→`currentSourceID` (update the late-failure idle guard + `stop()`). Keep the `onStreamTitle`/`onFailure` wiring. Keep `toggle()`/`stop()`.

- [ ] **Step 4: Run, passes** — `swift test` green (existing live tests via `playStation`; new on-demand test).

- [ ] **Step 5: Commit** — `git commit -m "refactor: generalize PlaybackEngine to PlaybackItem"`

---

## Task 2: Widen the audio seam — time, seek, finish

**Files:** Modify `Sources/QuraniKit/Playback/AudioPlayer.swift`, `PlaybackEngine.swift`, `App/System/AVAudioPlayerAdapter.swift`; Test `PlaybackEngineTests`.

**Interfaces:** `AudioPlayer.onTime/onFinish/seek`; `PlaybackEngine` publishes `nowPlaying.elapsed/duration`, `seek(toFraction:)`, `onFinish` hook.

- [ ] **Step 1: Failing tests:**
```swift
@MainActor @Test func timeUpdatesPopulateNowPlaying() {
    let p = FakePlayer(); let e = PlaybackEngine(player: p)
    e.play(.onDemand(reciterName: "R", surah: testSurah, url: URL(string:"https://e/1.mp3")!))
    p.onTime?(12, 60)
    #expect(e.nowPlaying?.elapsed == 12); #expect(e.nowPlaying?.duration == 60)
}
@MainActor @Test func seekDelegatesFraction() {
    let p = FakePlayer(); let e = PlaybackEngine(player: p)
    e.play(.onDemand(reciterName: "R", surah: testSurah, url: URL(string:"https://e/1.mp3")!))
    e.seek(toFraction: 0.5); #expect(p.lastSeekFraction == 0.5)
}
@MainActor @Test func finishInvokesHook() {
    let p = FakePlayer(); let e = PlaybackEngine(player: p); var fired = false
    e.onFinish = { fired = true }
    e.play(.onDemand(reciterName: "R", surah: testSurah, url: URL(string:"https://e/1.mp3")!))
    p.onFinish?(); #expect(fired)
}
```
(Add `lastSeekFraction` to `FakePlayer`; `func seek(toFraction f: Double) { lastSeekFraction = f }`.)

- [ ] **Step 2: Run, fails.**

- [ ] **Step 3: Implement.** Add to the `AudioPlayer` protocol: `func seek(toFraction f: Double)`, `var onTime: ((Double, Double) -> Void)?`, `var onFinish: (() -> Void)?`. In `PlaybackEngine.init`, wire `player.onTime = { [weak self] el, du in guard let self, var np = self.nowPlaying else { return }; np.elapsed = el; np.duration = du; self.nowPlaying = np }` and `player.onFinish = { [weak self] in self?.onFinish?() }`. Add `public var onFinish: (() -> Void)?` and `public func seek(toFraction f: Double) { player.seek(toFraction: f) }`.
In `AVAudioPlayerAdapter`: implement `seek(toFraction:)` using `player.currentItem?.duration` × f → `player.seek(to:)`; add a `periodicTimeObserver` (`player.addPeriodicTimeObserver(forInterval: CMTime(seconds:0.5,…), queue:.main)`) that reads `currentTime().seconds` + `currentItem?.duration.seconds` and calls `onTime` (guard against NaN/indefinite); observe `AVPlayerItem.didPlayToEndTimeNotification` (or the KVO `currentItem` end) on `.main` → `onFinish`. Keep all observation race-safe and warning-clean (compute Sendable Doubles before any hop; the periodic observer already delivers on `.main`).

- [ ] **Step 4: Run, passes** — `swift test` green.

- [ ] **Step 5: Build app** — `xcodegen generate && xcodebuild … build CODE_SIGNING_ALLOWED=NO` → SUCCEEDED, 0 source warnings.

- [ ] **Step 6: Commit** — `git commit -m "feat: audio seam — periodic time, seek, finish"`

---

## Task 3: Reciter/Moshaf models + CatalogService decode

**Files:** Create `Sources/QuraniKit/Model/Reciter.swift`, `Sources/QuraniKit/Catalog/CatalogService.swift`; Test `Tests/QuraniKitTests/CatalogServiceTests.swift`.

- [ ] **Step 1: Failing test** (real mp3quran v3 shape):
```swift
import Testing; import Foundation; @testable import QuraniKit
@Test func decodesRecitersUpgradingHttp() throws {
    let json = """
    {"reciters":[{"id":123,"name":"Sudais","moshaf":[
      {"id":1,"name":"Hafs - Murattal","server":"http://server7.mp3quran.net/sds/","surah_total":"114","surah_list":"1,2,3,67,114"}]}]}
    """.data(using: .utf8)!
    let rs = try CatalogService.decodeReciters(json)
    #expect(rs.count == 1)
    let m = try #require(rs[0].moshafs.first)
    #expect(m.serverBase.scheme == "https")                 // http upgraded
    #expect(m.surahNumbers == [1,2,3,67,114])
    #expect(CatalogService.audioURL(serverBase: m.serverBase, surah: 67).absoluteString == "https://server7.mp3quran.net/sds/067.mp3")
}
```

- [ ] **Step 2: Run, fails.**

- [ ] **Step 3: Implement.**
`Reciter.swift`: the `Moshaf` + `Reciter` structs from the Interfaces block.
`CatalogService.swift`:
```swift
import Foundation
public enum CatalogService {
    private struct Payload: Decodable { let reciters: [RawReciter] }
    private struct RawReciter: Decodable { let id: Int; let name: String; let moshaf: [RawMoshaf] }
    private struct RawMoshaf: Decodable { let id: Int; let name: String; let server: String; let surah_list: String }
    static func upgrade(_ s: String) -> URL? {
        var str = s; if str.hasPrefix("http://") { str = "https://" + str.dropFirst("http://".count) }
        return URL(string: str)
    }
    public static func decodeReciters(_ data: Data) throws -> [Reciter] {
        try JSONDecoder().decode(Payload.self, from: data).reciters.compactMap { r in
            let moshafs = r.moshaf.compactMap { m -> Moshaf? in
                guard let base = upgrade(m.server) else { return nil }
                let nums = m.surah_list.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                return Moshaf(id: m.id, name: m.name, serverBase: base, surahNumbers: nums)
            }
            return moshafs.isEmpty ? nil : Reciter(id: r.id, name: r.name, moshafs: moshafs)
        }
    }
    public static func audioURL(serverBase: URL, surah: Int) -> URL {
        serverBase.appendingPathComponent(String(format: "%03d.mp3", surah))
    }
}
```

- [ ] **Step 4: Run, passes.**
- [ ] **Step 5: Commit** — `git commit -m "feat: Reciter/Moshaf + mp3quran catalog decode"`

---

## Task 4: CatalogStore — fetch, cache, search, filter

**Files:** Create `Sources/QuraniKit/Catalog/CatalogStore.swift`; Test `Tests/QuraniKitTests/CatalogStoreTests.swift`.

- [ ] **Step 1: Failing test:**
```swift
@MainActor @Test func loadsAndFilters() async throws {
    let store = CatalogStore()
    let json = #"{"reciters":[{"id":1,"name":"Mishary Alafasy","moshaf":[{"id":1,"name":"Hafs","server":"https://s/a/","surah_total":"1","surah_list":"1"}]},{"id":2,"name":"Sudais","moshaf":[{"id":1,"name":"Hafs","server":"https://s/b/","surah_list":"1"}]}]}"#.data(using:.utf8)!
    await store.load { json }
    #expect(store.reciters.count == 2)
    #expect(store.filtered(search: "ala", riwaya: nil).map(\.id) == [1])
    #expect(store.filtered(search: "", riwaya: "Hafs").count == 2)
}
```

- [ ] **Step 2: Run, fails.**
- [ ] **Step 3: Implement** — `@MainActor` ObservableObject: `load` decodes via `CatalogService` (empty on error); `filtered(search:riwaya:)` case-insensitive name contains + riwaya = any moshaf name contains the token; static `fetchReciters()` = `URLRequest(url: …/reciters?language=eng, timeoutInterval: 15)` via URLSession.
- [ ] **Step 4: Run, passes.**
- [ ] **Step 5: Commit** — `git commit -m "feat: CatalogStore fetch/cache/search/filter"`

---

## Task 5: FavoritesStore + MixPoolStore (persisted)

**Files:** Create `Sources/QuraniKit/Library/FavoritesStore.swift`, `MixPoolStore.swift`; Test `Tests/QuraniKitTests/StoresTests.swift`.

- [ ] **Step 1: Failing test** — inject a temp directory; toggle a reciter id; reload a new store from the same dir → membership persisted.
```swift
@MainActor @Test func favoritesPersistAcrossInstances() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let a = FavoritesStore(directory: dir); a.toggle(reciter: 7)
    let b = FavoritesStore(directory: dir)
    #expect(b.isFavorite(reciter: 7))
}
```
(One analogous test for `MixPoolStore`.)

- [ ] **Step 2: Run, fails.**
- [ ] **Step 3: Implement** — each store: `init(directory:)` (default = Application Support/Qurani), loads a JSON `[Int]` into a `Set<Int>`, `toggle`/`isFavorite`/`contains` mutate + persist (write JSON). Use defaulted directory via a zero-arg convenience init (the `Bundle.module` lesson does not apply — this is a real path), but DON'T default an argument to an internal value; compute the support dir inside.
- [ ] **Step 4: Run, passes.**
- [ ] **Step 5: Commit** — `git commit -m "feat: persisted favorites + mix-pool stores"`

---

## Task 6: Wire on-demand playback + stores into AppModel

**Files:** Modify `App/AppModel.swift`; (no new QuraniKit tests — integration via build).

- [ ] **Step 1: Implement** — add `let catalog = CatalogStore()`, `let favorites = FavoritesStore()`, `let pool = MixPoolStore()`; in `bootstrap()` (still one-shot guarded) `await catalog.load { try await CatalogStore.fetchReciters() }`. Add a helper `func playOnDemand(reciter: Reciter, moshaf: Moshaf, surah: Surah)` that builds the URL via `CatalogService.audioURL` and calls `engine.play(.onDemand(reciterName: reciter.name, surah: surah, url: url))`. Keep `engine.onFinish = nil` (Mix is Plan 4).
- [ ] **Step 2: Build** — `xcodegen generate && xcodebuild … build CODE_SIGNING_ALLOWED=NO` → SUCCEEDED, 0 warnings.
- [ ] **Step 3: Commit** — `git commit -m "feat: wire catalog + on-demand playback into AppModel"`

---

## Task 7: Explore tab UI — reciter list, detail, actions

**Files:** Create `App/Views/ExploreTabView.swift`, `ReciterDetailView.swift`, `ReciterRow.swift`; Modify `App/Views/GlassPanel.swift` (route `tab == 1` → ExploreTabView).

Match `.superpowers/brainstorm/4886-1782776450/content/explore-tab.html`: search field; riwaya filter chips (All/Hafs/Warsh/Mujawwad/Muallim); reciter rows (avatar, Arabic + translit name, ＋ pool toggle); tap a reciter → push `ReciterDetailView` (back chevron + reciter name, moshaf chips, ♡ favorite + ＋ pool, the 114-surah list via `SurahNameView` Style-B, tap a surah → `model.playOnDemand(...)`). Use the existing `Tokens`, `SurahNameView`, `EqualizerDots`. Gate the playing-surah highlight on `engine.currentSourceID == "ondemand:\(reciter.name):\(surah.number)" && status == .playing`. The on-demand now-playing flows through the bottom bar.

- [ ] **Step 1: Implement the three views** (reuse Plan 1 patterns; `@ObservedObject` the engine/catalog/favorites/pool directly so they republish).
- [ ] **Step 2: Build** → SUCCEEDED, 0 warnings.
- [ ] **Step 3: Snapshot** — extend the `--snapshot` path to also render `ExploreTabView` (reciter list) + `ReciterDetailView` (surah list, one playing) in Noor; write PNGs.
- [ ] **Step 4: Commit** — `git commit -m "feat: Explore tab — reciter catalog + detail + actions"`

---

## Task 8: Now-playing scrubber (on-demand)

**Files:** Modify `App/Views/NowPlayingBar.swift`.

- [ ] **Step 1: Implement** — when `nowPlaying.isLive == false && duration > 0`, show a draggable progress bar (elapsed/duration, `Slider` or a custom gesture) that calls `engine.seek(toFraction:)`, plus `mm:ss / mm:ss` labels. Live stays the red **LIVE** pill (no scrubber). Keep the failed/retry affordance.
- [ ] **Step 2: Build** → SUCCEEDED, 0 warnings.
- [ ] **Step 3: Snapshot** — render the now-playing bar mid-on-demand (e.g. elapsed 92s / 760s) in both themes.
- [ ] **Step 4: Commit** — `git commit -m "feat: on-demand scrubber in now-playing bar"`

---

## Definition of done (Plan 2)

- `swift test` green (PlaybackItem/seam/catalog/stores tests added).
- App builds pristine; Explore tab browses real mp3quran reciters, search + riwaya filter work, tapping a surah streams it on demand with a working scrubber + accurate now-playing (surah + reciter + progress, `isLive=false`).
- ♡ favorites + ＋ Mix-pool persist across launches.
- Live radio (Plan 1) still works via `playStation`.
- `PlaybackItem` + widened seam in place (unblocks Plan 4 Mix `onFinish`).

Then → Plan 3 (Library).
