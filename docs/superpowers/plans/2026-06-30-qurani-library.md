# Qurani — Plan 3: Library (local files) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Import the user's own Qur'an audio (Add-files, drag-drop, or a watched `~/Music/Qurani` folder), smart-tag it to reciter+surah, and play it locally — grouped reciter→surah in a Library tab.

**Architecture:** First a small PRELUDE clears Plan-2 fast-follow debt (widen `PlaybackItem.sourceID`, harden the decoder, lock-screen progress, memoization, seek-to-0). Then add `PlaybackItem.localTrack`, a persisted `LibraryStore` over **security-scoped bookmarks**, a pure-logic `Tagger`, an import pipeline (NSOpenPanel / `onDrop` / FSEvents watch), the Library tab UI, a tagger review sheet, and the menubar right-click menu. Logic in `QuraniKit` (Swift Testing); macOS file/UI glue in the app target.

**Tech Stack:** Swift 6, SwiftUI, AVFoundation, AppKit (NSOpenPanel), Dispatch (FSEvents source), Swift Testing, XcodeGen.

## Global Constraints

- macOS 26.0+, Swift 6 `-strict-concurrency=complete`, **pristine build (0 source warnings)**. UI `@MainActor`.
- One third-party runtime dep stays `KeyboardShortcuts`.
- **Quran-only is a guideline, not enforced** (no content validation).
- **Security-scoped bookmarks** for every imported file + the watched folder, so access survives relaunch (sandbox-safe). Resolve with `URL.startAccessingSecurityScopedResource()` around reads.
- Default watched folder `~/Music/Qurani`; auto-import new audio dropped there (FSEvents / `DispatchSource`), smart-tag, then surface in the review sheet (don't silently add low-confidence).
- Surah names Style-B (`SurahNameView`). Persist library/tagger data as JSON in `Application Support/Qurani/`.
- Local now-playing shows exact surah + reciter + real progress (`isLive=false`), source tag 📚 LIBRARY.
- Tests use Swift Testing; commit after each task; `swift test`/`xcodebuild`/`git` run sandbox-disabled (env quirk); `gh api` works sandboxed.
- DO NOT build the random Mix engine (Plan 4) or a full Settings screen (Plan 5). The menubar context menu's "Settings…" may be a stub.

## File Structure
```
Sources/QuraniKit/
├── Model/
│   ├── PlaybackItem.swift     # MODIFY: widen .onDemand (reciterID/moshafID), add .localTrack
│   └── LocalTrack.swift       # NEW
├── Catalog/CatalogService.swift  # MODIFY: id/name optional (resilience)
├── Library/
│   ├── Tagger.swift           # NEW pure-logic filename/folder/tag → guess
│   └── LibraryStore.swift     # NEW persisted tracks + bookmark resolution
└── Playback/PlaybackEngine.swift # MODIFY: play(.localTrack), seek-to-0 at end
App/
├── System/
│   ├── AVAudioPlayerAdapter.swift  # MODIFY: (none required beyond Plan 2)
│   ├── NowPlayingBridge.swift      # MODIFY: NEW-1 elapsed/duration in MPNowPlayingInfo
│   ├── LibraryImporter.swift       # NEW NSOpenPanel + drop + FSEvents watch + bookmarks
│   └── MenuBarContextMenu.swift    # NEW right-click menu commands
├── AppModel.swift             # MODIFY: library, importer, playLocal, onDemand id wiring
└── Views/
    ├── LibraryTabView.swift   # NEW grouped reciter→surah + drop zone + folder reveal
    ├── TaggerReviewView.swift # NEW review sheet
    ├── ReciterDetailView.swift# MODIFY: sourceID gating uses ids; memoize surah dict (NEW-2)
    └── NowPlayingBar.swift    # MODIFY: 📚 LIBRARY source tag
```

## Interfaces (locked)
```swift
public enum PlaybackItem: Sendable, Equatable {
    case liveStation(Station)
    case onDemand(reciterID: Int, reciterName: String, moshafID: Int, surah: Surah, url: URL)
    case localTrack(LocalTrack)
    var sourceID: String   // "live:<id>" | "ondemand:<rID>:<mID>:<sNum>" | "local:<track.id>"
    var url: URL
    var isLive: Bool
}
public struct LocalTrack: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public let bookmark: Data            // security-scoped
    public let reciterName: String
    public let surahNumber: Int
    public let confidence: Double        // 0...1
    public let durationMs: Int?
}
public enum Tagger {
    public struct Guess: Equatable, Sendable { public var reciterName: String?; public var surahNumber: Int?; public var confidence: Double }
    // pure: filename (no ext), optional parent-folder name, optional embedded tags (title/artist/album), surah metadata
    public static func guess(filename: String, folder: String?, tags: [String:String], surahs: [Surah]) -> Guess
}
@MainActor public final class LibraryStore: ObservableObject {
    @Published public private(set) var tracks: [LocalTrack]
    public init(directory: URL); public convenience init()
    public func add(_ tracks: [LocalTrack]); public func remove(id: UUID)
    public func grouped() -> [(reciter: String, tracks: [LocalTrack])]   // sorted reciter→surah
}
```

---

## Task 1: PRELUDE — widen sourceID, harden decoder, lock-screen progress, memoize, seek-to-0
**Files:** Modify `Model/PlaybackItem.swift`, `Catalog/CatalogService.swift`, `Playback/PlaybackEngine.swift`, `App/AppModel.swift`, `App/Views/ReciterDetailView.swift`, `App/System/NowPlayingBridge.swift`; Test `PlaybackEngineTests`, `CatalogServiceTests`.

- [ ] **Step 1: Failing tests.**
```swift
// PlaybackEngineTests
@MainActor @Test func onDemandSourceIDCarriesMoshaf() {
    let p = FakePlayer(); let e = PlaybackEngine(player: p)
    e.play(.onDemand(reciterID: 9, reciterName: "Sudais", moshafID: 3, surah: testSurah, url: URL(string:"https://e/067.mp3")!))
    #expect(e.currentSourceID == "ondemand:9:3:67")
}
@MainActor @Test func playAtEndSeeksToZero() {  // NEW-3
    let p = FakePlayer(); let e = PlaybackEngine(player: p)
    e.play(.onDemand(reciterID: 1, reciterName: "R", moshafID: 1, surah: testSurah, url: URL(string:"https://e/1.mp3")!))
    p.onTime?(60, 60)              // at end
    e.toggle()                      // resume from paused-at-end
    #expect(p.lastSeekFraction == 0)   // sought to start before play
}
// CatalogServiceTests
@Test func decoderToleratesMissingReciterName() throws {
    let json = #"{"reciters":[{"id":1,"moshaf":[{"id":1,"name":"Hafs","server":"https://s/a/","surah_list":"1"}]},{"id":2,"name":"OK","moshaf":[{"id":1,"name":"Hafs","server":"https://s/b/","surah_list":"1"}]}]}"#.data(using:.utf8)!
    let rs = try CatalogService.decodeReciters(json)
    #expect(rs.map(\.id).contains(2))   // one bad reciter doesn't nuke the rest
}
```

- [ ] **Step 2: Run, fails.**

- [ ] **Step 3: Implement.**
- `PlaybackItem.onDemand` → `case onDemand(reciterID: Int, reciterName: String, moshafID: Int, surah: Surah, url: URL)`; `sourceID` onDemand → `"ondemand:\(reciterID):\(moshafID):\(surah.number)"`.
- `CatalogService`: make `RawReciter.name` and `RawMoshaf.name` OPTIONAL; a reciter with nil/empty name → use a fallback (`"Reciter \(id)"`) or drop — pick drop to be safe-but-non-throwing; nil moshaf name → `""`. The key: one missing `id`/`name` must not throw the whole payload (decode reciters element-tolerantly: decode into `[FailableReciter]` where a per-element failure is dropped, OR keep id required (reliably present) + name optional with fallback).
- `PlaybackEngine`: in `toggle()`/play-resume, if the player is at end (elapsed≈duration>0) seek to fraction 0 before `play()` (NEW-3). Track end via the last `onTime` (elapsed≈duration).
- `AppModel.playOnDemand(reciter:moshaf:surah:)` → pass `reciter.id` + `moshaf.id` into `.onDemand`.
- `ReciterDetailView`: gating string → `"ondemand:\(reciter.id):\(moshaf.id):\(surah.number)"`; memoize the number→Surah dict as a computed/`let` off `(surahs, activeMoshaf)` instead of rebuilding in `body` (NEW-2).
- `NowPlayingBridge.update(_:)`: also set `MPMediaItemPropertyPlaybackDuration` + `MPNowPlayingInfoPropertyElapsedPlaybackTime` from `np.duration/elapsed` when `!isLive` (NEW-1).

- [ ] **Step 4: Run, passes.** `swift test` green.
- [ ] **Step 5: Build app** → SUCCEEDED, 0 warnings.
- [ ] **Step 6: Commit** — `git commit -m "refactor: widen sourceID + decoder/now-playing/UX prelude fixes"`

---

## Task 2: `PlaybackItem.localTrack` + engine plays it
**Files:** Modify `Model/PlaybackItem.swift`, `Playback/PlaybackEngine.swift`; (LocalTrack model lands in Task 3 — for Task 2 use a minimal inline or land `LocalTrack` here). Test `PlaybackEngineTests`.

Land `LocalTrack` (Interfaces block) in this task so the enum case compiles. `PlaybackItem.localTrack(LocalTrack)`: `url` = resolve later (the engine receives an already-resolved URL via a helper), `sourceID = "local:\(track.id)"`, `isLive=false`. Because the engine plays a URL, add `play(localTrack:resolvedURL:)` or have AppModel resolve the bookmark → pass a `.localTrack` whose playback URL the engine reads. Simplest: `PlaybackItem.localTrack(LocalTrack)` carries the track; engine needs a URL → add `var url` that returns a resolved file URL is NOT pure. Resolution: AppModel resolves the bookmark to a URL and calls a new `engine.playLocal(track:url:)` that builds NowPlaying (title = surah nameAr via a passed Surah, subtitle = reciterName, isLive false) and plays `url`. Test the engine state for a local play (status/sourceID/isLive) with a FakePlayer.

- [ ] Steps: failing test (`playLocalSetsSourceAndNotLive`) → implement → `swift test` green → build → commit `feat: local-track playback item + engine`.

---

## Task 3: LocalTrack model + LibraryStore (persisted, bookmarks)
**Files:** Create `Model/LocalTrack.swift` (if not in Task 2), `Library/LibraryStore.swift`; Test `LibraryStoreTests`.

- TDD: persist `[LocalTrack]` JSON via the existing App-Support pattern; `add`/`remove`/`grouped()` (group by `reciterName`, sort tracks by `surahNumber`); a fresh store from the same dir reflects prior state. Bookmark RESOLUTION (`URL(resolvingBookmarkData:options:.withSecurityScope…)` + start/stop access) lives in a `resolveURL(_:) -> URL?` (app-callable). Test the persistence + grouping with synthetic bookmarks (`Data()` placeholder is fine for the store-logic tests; real bookmark resolution is exercised in the app-target import path).
- Steps: failing tests → implement → green → commit `feat: LocalTrack + persisted LibraryStore`.

---

## Task 4: Tagger (filename / folder / tag → guess)
**Files:** Create `Library/Tagger.swift`; Test `TaggerTests`.

Pure logic. `guess(filename:folder:tags:surahs:)`:
- **surahNumber:** a leading/standalone 1–3 digit token in 1…114 (everyayah `001.mp3`, `067 Al-Mulk`); else match a surah Arabic name (tashkeel-stripped) or transliteration substring against `surahs`.
- **reciterName:** the `folder` (folder-per-reciter) if present and not a generic name; else the filename portion before a `-`/`_` separator that isn't the surah token; else `tags["artist"]`/`tags["album"]`.
- **confidence:** high (≥0.8) when surah from an explicit number AND reciter from folder/tag; medium when one is guessed; low (≤0.4) when reciter unknown or surah only name-matched.

- [ ] TDD with the brief's representative cases:
```swift
@Test func everyayahNumber() { let g = Tagger.guess(filename:"067", folder:"Alafasy", tags:[:], surahs: SAMPLE); #expect(g.surahNumber==67); #expect(g.reciterName=="Alafasy"); #expect(g.confidence>=0.8) }
@Test func dashedNameAndSurahName() { let g = Tagger.guess(filename:"Sudais - Al-Mulk", folder:nil, tags:[:], surahs: SAMPLE); #expect(g.surahNumber==67); #expect(g.reciterName=="Sudais") }
@Test func unknownReciterLowConfidence() { let g = Tagger.guess(filename:"track12", folder:nil, tags:[:], surahs: SAMPLE); #expect(g.reciterName==nil); #expect(g.confidence<=0.4) }
@Test func tagsFallback() { let g = Tagger.guess(filename:"002", folder:nil, tags:["artist":"Husary"], surahs: SAMPLE); #expect(g.reciterName=="Husary"); #expect(g.surahNumber==2) }
```
- [ ] Steps: failing tests → implement → green → commit `feat: smart tagger (filename/folder/tag heuristics)`.

---

## Task 5: Import pipeline — Add files, drag-drop, watched folder
**Files:** Create `App/System/LibraryImporter.swift`; Modify `App/AppModel.swift`. (App-target; verified by build + the review sheet integration in Task 7.)

- `LibraryImporter` (`@MainActor`): `addFilesPanel()` (NSOpenPanel, audio types, multiple), `importDropped(_ providers:)` (`onDrop` URLs), and a **watched-folder** source: resolve/create `~/Music/Qurani`, store a security-scoped bookmark for it, watch via a `DispatchSource.makeFileSystemObjectSource`/FSEvents for new files → enqueue for tagging. For each incoming file: read AVAsset metadata (title/artist/album) + filename + parent folder → `Tagger.guess` → produce a **pending** `(url, bookmark, Guess)` for the review sheet (don't auto-commit; surface in Task 7's sheet). Make a security-scoped bookmark per file at import.
- AppModel: own `let importer`, a `@Published pendingImports: [PendingImport]`, and `func commitImports(_ reviewed:)` → `library.add(...)`.
- Build → SUCCEEDED 0 warnings. Manual note: the actual panel/drop/FSEvents need a running app (document in report). Commit `feat: import pipeline — panel, drop, watched folder`.

---

## Task 6: Library tab UI
**Files:** Create `App/Views/LibraryTabView.swift`; Modify `App/Views/GlassPanel.swift` (route `tab == 2`).

Match `.superpowers/brainstorm/4886-1782776450/content/library-tab.html`: a `~/Music/Qurani` folder bar with **Reveal** (NSWorkspace.activateFileViewerSelecting), an **Add files** button, grouped reciter→surah rows (Style-B `SurahNameView`, tap → `model.playLocal(track:)`), a dashed **drop zone** (`.onDrop`), and 📚 LIBRARY in the now-playing bar. Empty state when no tracks. Observe `model.library`/`model.engine` directly. Highlight gating on `engine.currentSourceID == "local:\(track.id)" && status == .playing`.
- Extend `--snapshot` to render `LibraryTabView` (a few grouped tracks, one playing) in Noor. Build → SUCCEEDED 0 warnings. Commit `feat: Library tab UI`.

---

## Task 7: Tagger review sheet
**Files:** Create `App/Views/TaggerReviewView.swift`; wire it to `AppModel.pendingImports` (presented when imports arrive).

Match the mockup's review: a list of pending files, each showing detected **Reciter** + **Surah** with a confidence chip (✓ high / ~ low, amber row needs attention), editable (a reciter text field + a surah picker), and **Add N to Library**. On confirm → `model.commitImports(...)` → `library.add`. Drag-over overlay ("Drop to add · Quran only") can live here or in Task 6.
- Extend `--snapshot` to render the review sheet (4 sample pending rows, one amber). Build → SUCCEEDED 0 warnings. Commit `feat: tagger review sheet`.

---

## Task 8: Menubar context menu + local-playback wiring
**Files:** Create `App/System/MenuBarContextMenu.swift`; Modify `App/QuraniApp.swift` (attach to `MenuBarExtra` / icon), `App/Views/NowPlayingBar.swift` (📚 LIBRARY tag).

Right-click the menubar icon → menu: **Add Files to Library…**, **Reveal Library Folder**, ─, Pause/Play, Next, ─, Settings… (stub), Quit. (For `MenuBarExtra` the right-click menu is typically a `.menuBarExtraStyle(.window)` limitation — implement via an `NSStatusItem`-style menu or a secondary `Menu` in the panel header's ••• if a true right-click menu isn't feasible; document the chosen approach.) Wire local now-playing to show the 📚 LIBRARY source tag (pass a source-kind through `NowPlaying` or infer from `currentSourceID` prefix).
- Build → SUCCEEDED 0 warnings. Commit `feat: menubar context menu + local now-playing tag`.

---

## Definition of done (Plan 3)
- `swift test` green (sourceID/localTrack/LibraryStore/Tagger tests).
- App builds pristine; Library tab imports via Add-files / drag-drop / the watched `~/Music/Qurani` folder, smart-tags → review sheet → grouped reciter→surah, and plays local files with progress + 📚 LIBRARY now-playing.
- Security-scoped bookmarks persist access across relaunch.
- Live (Plan 1) + Explore (Plan 2) still work; prelude debt paid (sourceID carries moshaf+id, decoder id/name tolerant, lock-screen progress, seek-to-0).
- `PlaybackItem` now has all of `.liveStation/.onDemand/.localTrack` → Plan 4 Mix only adds `.mixItem` sequencing.

Then → Plan 4 (Mix).
