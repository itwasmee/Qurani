# Qurani — Plan 4: Mix (random per-surah station) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Build a station that plays surah-by-surah where **each surah is recited by a randomly-chosen qari from a user-selected pool** (local 📚 + on-demand ☁︎), with re-roll, order, and range — the app's signature feature.

**Architecture:** No new `PlaybackItem` case — a `MixEngine` (pure logic) builds a `[MixQueueItem]` (surah → random pool member), and a `MixSession` in `AppModel` resolves each step to an existing `.onDemand`/`.localTrack` and plays it, advancing via the already-wired `engine.onFinish`. The Mix tab UI selects the pool + config and shows the queue. Logic in `QuraniKit` (Swift Testing); UI/orchestration in the app target.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing, XcodeGen.

## Global Constraints
- macOS 26.0+, Swift 6 `-strict-concurrency=complete`, **pristine build (0 source warnings)**. UI `@MainActor`.
- One third-party dep stays `KeyboardShortcuts`. Surah names Style-B (`SurahNameView`).
- Pool draws from **local reciters** (by name, from `LibraryStore`) + **on-demand reciters** (catalog `Reciter`+`Moshaf`, gated to favorited/in-pool). Each surah is played by a **uniformly-random** member that actually HAS that surah (local: that reciter has a `LocalTrack` for it; on-demand: the moshaf's `surahNumbers` contains it).
- Sequential playback (hard cuts — crossfade is out of v1 scope). Re-roll regenerates the random assignment. Order: in-order (1→114) or shuffle. Range: full / by-juz / custom.
- `MixEngine` randomness is **injected** (a picker closure) so it's deterministic in tests; the app passes a `SystemRandomNumberGenerator`-backed picker.
- Now-playing shows a **⤮ MIX** source tag while a mix session is active + an **Up-next** row.
- Tests use Swift Testing; commit after each task; `swift test`/`xcodebuild`/`git` run sandbox-disabled; `gh`/`curl` work for live checks.
- DO NOT build the full Settings screen (Plan 5). Mix-preset SAVE/load is optional (defer to Plan 5 if time-constrained).

## File Structure
```
Sources/QuraniKit/Mix/
├── PoolMember.swift     # NEW pool member (local/on-demand) + availability
├── MixConfig.swift      # NEW order/range
└── MixEngine.swift      # NEW pure: build random per-surah queue
App/
├── AppModel.swift       # MODIFY: MixSession orchestration (start/reroll/next/stop, isMixing, upNext)
└── Views/
    ├── MixTabView.swift     # NEW build (pool+order+range+Start) + playing (queue+reroll)
    ├── PoolRow.swift        # NEW selectable pool member row
    └── NowPlayingBar.swift  # MODIFY: ⤮ MIX tag when mixing
```

## Interfaces (locked)
```swift
public enum PoolSource: String, Codable, Sendable { case local, onDemand }
public struct PoolMember: Identifiable, Sendable, Equatable {
    public let id: String                 // "od:<reciterID>:<moshafID>" | "local:<reciterName>"
    public let source: PoolSource
    public let displayName: String
    public let reciterName: String
    public let surahNumbers: Set<Int>     // availability
    public let reciterID: Int?            // on-demand
    public let moshaf: Moshaf?            // on-demand (serverBase for URL)
}
public struct MixConfig: Sendable, Equatable {
    public enum Order: Sendable, Equatable { case inOrder, shuffle }
    public enum Range: Sendable, Equatable { case full, juz(Int), custom(ClosedRange<Int>) }
    public var order: Order = .shuffle
    public var range: Range = .full
}
public struct MixQueueItem: Sendable, Equatable, Identifiable {
    public let surah: Int
    public let memberID: String
    public var id: Int { surah }          // unique within a queue (each surah once)
}
public enum MixEngine {
    /// Surah list for the range (in-order or shuffled), then each surah assigned a uniformly-random
    /// pool member that HAS it (skip surahs no member has). `pickIndex(count)` returns 0..<count
    /// (injected for determinism); `shuffle` returns a permutation (injected too).
    public static func buildQueue(pool: [PoolMember], config: MixConfig, surahJuz: [Int:Int],
                                  pickIndex: (Int) -> Int,
                                  shuffle: ([Int]) -> [Int]) -> [MixQueueItem]
}
```

---

## Task 1: `PoolMember` + `MixConfig`
**Files:** Create `Mix/PoolMember.swift`, `Mix/MixConfig.swift`; Test `Tests/QuraniKitTests/MixModelTests.swift`.

- [ ] **Step 1: Failing test** — construct an on-demand + a local `PoolMember`, assert `id`/`source`/`surahNumbers`; `MixConfig` defaults (`.shuffle`, `.full`).
```swift
@Test func poolMemberShapes() {
    let m = Moshaf(id: 3, name: "Hafs", serverBase: URL(string:"https://s/x/")!, surahNumbers: [1,2,67])
    let od = PoolMember(id: "od:9:3", source: .onDemand, displayName: "Sudais", reciterName: "Sudais", surahNumbers: [1,2,67], reciterID: 9, moshaf: m)
    #expect(od.surahNumbers.contains(67)); #expect(od.source == .onDemand)
    let lo = PoolMember(id: "local:Husary", source: .local, displayName: "Husary", reciterName: "Husary", surahNumbers: [2], reciterID: nil, moshaf: nil)
    #expect(lo.source == .local); #expect(MixConfig().order == .shuffle)
}
```
- [ ] Steps 2-5: fail → implement the two value types (verbatim from Interfaces) → `swift test` green → commit `feat: Mix pool member + config`.

---

## Task 2: `MixEngine` — random per-surah queue
**Files:** Create `Mix/MixEngine.swift`; Test `Tests/QuraniKitTests/MixEngineTests.swift`.

- [ ] **Step 1: Failing tests** (deterministic via injected pickers):
```swift
private let A = PoolMember(id:"a", source:.onDemand, displayName:"A", reciterName:"A", surahNumbers:[1,2,3], reciterID:1, moshaf:nil)
private let B = PoolMember(id:"b", source:.local, displayName:"B", reciterName:"B", surahNumbers:[2], reciterID:nil, moshaf:nil)

@Test func inOrderAssignsAMemberThatHasEachSurah() {
    let q = MixEngine.buildQueue(pool:[A,B], config: MixConfig(order:.inOrder, range:.custom(1...3)),
                                 surahJuz: [:], pickIndex: { _ in 0 }, shuffle: { $0 })
    #expect(q.map(\.surah) == [1,2,3])
    // surah 1 only A has → A; surah 2 both → pickIndex 0; surah 3 only A
    #expect(q[0].memberID == "a"); #expect(q[2].memberID == "a")
}
@Test func skipsSurahsNoMemberHas() {
    let q = MixEngine.buildQueue(pool:[B], config: MixConfig(order:.inOrder, range:.custom(1...3)),
                                 surahJuz: [:], pickIndex: { _ in 0 }, shuffle: { $0 })
    #expect(q.map(\.surah) == [2])   // only surah 2 is available from B
}
@Test func shuffleUsesInjectedPermutation() {
    let q = MixEngine.buildQueue(pool:[A], config: MixConfig(order:.shuffle, range:.custom(1...3)),
                                 surahJuz: [:], pickIndex: { _ in 0 }, shuffle: { $0.reversed() })
    #expect(q.map(\.surah) == [3,2,1])
}
@Test func rangeFullIs1to114() {
    let q = MixEngine.buildQueue(pool:[A], config: MixConfig(order:.inOrder, range:.full),
                                 surahJuz: [:], pickIndex: { _ in 0 }, shuffle: { $0 })
    #expect(q.map(\.surah) == [1,2,3])   // A only has 1,2,3 so others skipped, but range was full 1...114
}
@Test func juzRangeFiltersBySurahJuz() {
    // surahJuz maps surah→starting juz; range .juz(1) keeps surahs whose juz==1
    let q = MixEngine.buildQueue(pool:[A], config: MixConfig(order:.inOrder, range:.juz(1)),
                                 surahJuz: [1:1, 2:1, 3:3], pickIndex: { _ in 0 }, shuffle: { $0 })
    #expect(q.map(\.surah) == [1,2])
}
```
- [ ] **Step 3: Implement.** Compute the surah-number list for the range: `.full`→1...114; `.custom(r)`→Array(r); `.juz(n)`→ surahs whose `surahJuz[surah]==n`. Apply order (`.inOrder` keep; `.shuffle`→`shuffle(list)`). For each surah, candidates = `pool.filter{ $0.surahNumbers.contains(surah) }`; if empty skip; else pick `candidates[pickIndex(candidates.count)]` → `MixQueueItem(surah:, memberID: member.id)`. Pure, no side effects.
- [ ] Steps 4-5: `swift test` green → commit `feat: MixEngine random per-surah queue`.

---

## Task 3: MixSession orchestration in AppModel
**Files:** Modify `App/AppModel.swift`. (App-target; build + a small testable pool-builder if extracted.)

- Build the pool: `func buildPool() -> [PoolMember]` = on-demand members from `catalog.reciters` whose id ∈ `pool.reciterIDs` (one PoolMember per reciter using its first/primary moshaf; `surahNumbers = Set(moshaf.surahNumbers)`) + local members from `library.grouped()` (one per reciter name; `surahNumbers = Set(tracks.map(\.surahNumber))`, also added to the pool by name — see UI Task 4). 
- `@Published var isMixing = false`, `@Published private(set) var mixQueue: [MixQueueItem] = []`, `private var mixIndex = 0`, and an `upNext: (surah: Int, memberName: String)?` computed from `mixQueue[mixIndex+1]`.
- `func startMix(config: MixConfig)`: `let pool = buildPool()`; `mixQueue = MixEngine.buildQueue(pool:config:surahJuz: <bundled surah→juz from QuranData>, pickIndex: { Int.random(in: 0..<$0) }, shuffle: { $0.shuffled() })`; `mixIndex = 0`; `isMixing = true`; `engine.onFinish = { [weak self] in self?.advanceMix() }`; play index 0.
- `private func playMixIndex(_ i:)`: resolve `mixQueue[i]` → its `PoolMember` → a `PlaybackItem`: on-demand → `.onDemand(reciterID:reciterName:moshafID:surah:url via CatalogService.audioURL)`; local → look up the member's `LocalTrack` for that surah → `library.resolveURL` → `.localTrack`. `engine.play(item)`.
- `func advanceMix()`: `mixIndex += 1`; if in range play it, else `stopMix()`.
- `func rerollMix()`: rebuild `mixQueue` from current config (new random assignment), keep playing position sensibly (restart current surah's reciter or from index 0 — pick + document). `func stopMix()`: `isMixing=false`, `engine.onFinish = nil`, `engine.stop()`.
- Build → SUCCEEDED 0 warnings. Commit `feat: Mix session orchestration (start/advance/reroll/stop)`.

---

## Task 4: Mix tab UI — build (pool + order + range + Start)
**Files:** Create `App/Views/MixTabView.swift`, `App/Views/PoolRow.swift`; Modify `App/Views/GlassPanel.swift` (route `tab == 3`).

Match the **build** panel of `.superpowers/brainstorm/4886-1782776450/content/mix-tab.html`: a "Random Mix" header; a **POOL** section listing selectable reciters — local (from `library.grouped()`, badge 📚 LOCAL) + on-demand (from `catalog.reciters` filtered to favorites/pool, badge ☁︎ ON-DEMAND) — each a `PoolRow` with a checkbox toggling membership in a local `@State Set<String>` (member id) or in `model.pool` (on-demand ids) + a local-name set; **SURAH ORDER** segmented (In order / Shuffle); **RANGE** chips (Full Qur'an / By Juz' / Custom); a **Start Random Mix** button → `model.startMix(config:)` (build `MixConfig` from the controls + the selected pool — wire the selection into `buildPool`). Observe `model.library`/`model.catalog`/`model.pool` directly. Empty-pool → Start disabled.
- Build → SUCCEEDED 0 warnings. Commit `feat: Mix tab — pool selection + config + start`.

---

## Task 5: Mix playing UI + ⤮ MIX now-playing + re-roll
**Files:** Modify `App/Views/MixTabView.swift` (playing state), `App/Views/NowPlayingBar.swift`; extend `--snapshot`.

When `model.isMixing`, the Mix tab shows the **playing** view (mockup's right panel): "Random Mix · {order}" + "{N} qaris · {range}", a **Re-roll** button (`model.rerollMix()`), and the `mixQueue` list — each row = surah (Style-B `SurahNameView`) + the assigned member's name + source badge (📚/☁︎), the current index highlighted with `EqualizerDots`. `NowPlayingBar`: when `model.isMixing`, show a **⤮ MIX** source chip (alongside/instead of the local/live tags) and an **Up next · random** line (`model.upNext`).
- Extend `--snapshot` to render the Mix build panel + the Mix playing panel (seeded queue, one playing) in Noor. Build → SUCCEEDED 0 warnings.
- Commit `feat: Mix playing UI + MIX now-playing tag + re-roll`.

---

## Definition of done (Plan 4)
- `swift test` green (PoolMember/MixConfig/MixEngine tests).
- App builds pristine; the Mix tab selects a pool (local + on-demand), order, range, and Start plays a **random reciter per surah**, advancing automatically via `engine.onFinish`; Re-roll reshuffles the assignment; now-playing shows ⤮ MIX + the current surah/reciter + Up-next.
- Live/Explore/Library all still work.

Then → Plan 5 (Settings + polish).
