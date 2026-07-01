# Autoplay Next Surah Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When a surah plays on-demand from a reciter, auto-advance to the next surah in that moshaf's list when it finishes, stopping at the end, gated by a default-on Settings toggle.

**Architecture:** A pure `Autoplay.nextSurah(in:after:)` helper in QuraniKit computes the next surah; `AppModel` keeps an on-demand "context" (reciter/moshaf + ordered surah list), arms `engine.onFinish` to `advanceOnDemand()` for on-demand plays, and clears it when switching to Library/Live/Mix. A new `SettingsStore.autoplayEnabled` gates advancing; a `SettingsView` toggle exposes it.

**Tech Stack:** Swift 6, SwiftUI, swift-testing (`import Testing`), SwiftPM (QuraniKit) + xcodegen/xcodebuild (App target).

## Global Constraints

- Swift 6, macOS 26 (Tahoe) target.
- Unit tests live in `Tests/QuraniKitTests` (QuraniKit only); the App target has no test bundle — AppModel/SettingsView changes are verified by build + run.
- Do not change Mix behaviour: Mix keeps `engine.onFinish = advanceMix`; on-demand autoplay must not fire for Mix/Library/Live items.
- Run `swift test` and `xcodebuild` outside the command sandbox (nested toolchain sandbox + network for SPM/signing).
- Follow existing patterns: `SettingsStore` field mirrors `mediaKeysEnabled`; `SettingsView` row mirrors `mediaKeysRow`.

---

### Task 1: `Autoplay.nextSurah` pure helper (QuraniKit)

**Files:**
- Create: `Sources/QuraniKit/Playback/Autoplay.swift`
- Test: `Tests/QuraniKitTests/AutoplayTests.swift`

**Interfaces:**
- Produces: `enum Autoplay { static func nextSurah(in order: [Int], after current: Int) -> Int? }`

- [ ] **Step 1: Write the failing tests**

Create `Tests/QuraniKitTests/AutoplayTests.swift`:
```swift
import Testing
@testable import QuraniKit

@Test func nextSurahMidListReturnsFollowing() {
    #expect(Autoplay.nextSurah(in: [1, 2, 3, 55, 67], after: 2) == 3)
}
@Test func nextSurahLastReturnsNil() {
    #expect(Autoplay.nextSurah(in: [1, 2, 3], after: 3) == nil)
}
@Test func nextSurahAbsentReturnsNil() {
    #expect(Autoplay.nextSurah(in: [1, 2, 3], after: 9) == nil)
}
@Test func nextSurahSingleReturnsNil() {
    #expect(Autoplay.nextSurah(in: [36], after: 36) == nil)
}
@Test func nextSurahNonContiguousReturnsNextInList() {
    #expect(Autoplay.nextSurah(in: [1, 36, 55, 112], after: 36) == 55)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test 2>&1 | grep -i autoplay`
Expected: FAIL — "cannot find 'Autoplay' in scope".

- [ ] **Step 3: Write the implementation**

Create `Sources/QuraniKit/Playback/Autoplay.swift`:
```swift
import Foundation

/// Autoplay ordering for on-demand recitation: given a moshaf's ordered surah list, the surah that
/// should play after the current one. Pure and isolated so it is unit-testable — the AppModel wiring
/// that consumes it lives in the App target, which has no unit-test bundle.
public enum Autoplay {
    /// The surah number after the first occurrence of `current` in `order`, or nil when `current`
    /// is the last element or is absent — the signal to stop autoplay.
    public static func nextSurah(in order: [Int], after current: Int) -> Int? {
        guard let i = order.firstIndex(of: current), i + 1 < order.count else { return nil }
        return order[i + 1]
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test 2>&1 | tail -5`
Expected: all tests pass.

- [ ] **Step 5: Commit**
```bash
git add Sources/QuraniKit/Playback/Autoplay.swift Tests/QuraniKitTests/AutoplayTests.swift
git commit -m "feat: Autoplay.nextSurah helper for on-demand advance"
```

---

### Task 2: `SettingsStore.autoplayEnabled` (QuraniKit)

**Files:**
- Modify: `Sources/QuraniKit/Settings/SettingsStore.swift`
- Test: `Tests/QuraniKitTests/SettingsStoreTests.swift`

**Interfaces:**
- Produces: `SettingsStore.autoplayEnabled: Bool` (published, persisted, defaults to `true`).

- [ ] **Step 1: Write the failing test**

Append to `Tests/QuraniKitTests/SettingsStoreTests.swift`:
```swift
@MainActor @Test func autoplayDefaultsOnAndPersistsOff() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let a = SettingsStore(directory: dir)
    #expect(a.autoplayEnabled == true)
    a.autoplayEnabled = false
    let b = SettingsStore(directory: dir)   // reload from disk
    #expect(b.autoplayEnabled == false)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test 2>&1 | grep -i autoplayDefaults`
Expected: FAIL — "value of type 'SettingsStore' has no member 'autoplayEnabled'".

- [ ] **Step 3: Add the property, persistence field, load, and save**

In `Sources/QuraniKit/Settings/SettingsStore.swift`:

Add after the `autoImportEnabled` published property (line ~13):
```swift
    /// Whether finishing an on-demand surah auto-advances to the next surah in the reciter's moshaf.
    @Published public var autoplayEnabled: Bool = true { didSet { save() } }
```

In `init(directory:)`, inside the `if let stored` block, add:
```swift
            autoplayEnabled = stored.autoplayEnabled
```

In `private struct Persisted`, add:
```swift
        var autoplayEnabled = true
```

In `save()`, update the snapshot to include the field:
```swift
        let snapshot = Persisted(mediaKeysEnabled: mediaKeysEnabled, autoImportEnabled: autoImportEnabled,
                                 autoplayEnabled: autoplayEnabled)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test 2>&1 | tail -5`
Expected: all pass, including `autoplayDefaultsOnAndPersistsOff` and the existing `settingsDefaultToOnWhenFileMissing`.

- [ ] **Step 5: Commit**
```bash
git add Sources/QuraniKit/Settings/SettingsStore.swift Tests/QuraniKitTests/SettingsStoreTests.swift
git commit -m "feat: persist autoplayEnabled setting (default on)"
```

---

### Task 3: On-demand autoplay wiring (AppModel)

**Files:**
- Modify: `App/AppModel.swift`

**Interfaces:**
- Consumes: `Autoplay.nextSurah(in:after:)` (Task 1), `settings.autoplayEnabled` (Task 2), existing `engine.onFinish`, `engine.play(_:)`, `catalog.reciters`, `surahs`.
- Produces: on-demand plays that auto-advance; `advanceOnDemand()`; `clearOnDemandAutoplay()`.

- [ ] **Step 1: Add the context type and stored property**

In `App/AppModel.swift`, add near the other private state (e.g. after `private var scopedLocalURL: URL?` at line ~199):
```swift
    // MARK: - On-demand autoplay
    //
    // While an on-demand surah plays, we retain the reciter/moshaf and that moshaf's ordered surah
    // list so a natural finish can advance to the next surah (gated by settings.autoplayEnabled).
    // Cleared whenever a non-on-demand source takes over so Library/Live/Mix never trigger it.
    private struct OnDemandContext {
        let reciterID: Int; let reciterName: String; let moshafID: Int
        let serverBase: URL; let order: [Int]; let current: Int
    }
    private var onDemandContext: OnDemandContext?

    /// Drop the on-demand autoplay context and detach the finish hook. Called when Library/Live take
    /// over (Mix reassigns `onFinish` itself).
    private func clearOnDemandAutoplay() {
        onDemandContext = nil
        engine.onFinish = nil
    }
```

- [ ] **Step 2: Refactor `startOnDemand` to store context, arm onFinish, and take `order` + `record`**

Replace the existing `startOnDemand(...)` (lines ~128-139) with:
```swift
    /// Shared on-demand start used by `playOnDemand`, `playRecent`, and autoplay advances. `order` is
    /// the moshaf's ordered surah list (drives autoplay); `record` adds a recents entry (true for a
    /// user-initiated play, false for an autoplay advance so history isn't flooded).
    private func startOnDemand(reciterID: Int, reciterName: String, moshafID: Int, serverBase: URL,
                               surah: Surah, order: [Int], record: Bool) {
        if isMixing { stopMix() }   // an explicit single play ends any active random-mix session
        releaseLocalScope()         // switching to a streamed source — drop any held local file scope
        let url = CatalogService.audioURL(serverBase: serverBase, surah: surah.number)
        engine.play(.onDemand(reciterID: reciterID, reciterName: reciterName,
                              moshafID: moshafID, surah: surah, url: url))
        onDemandContext = OnDemandContext(reciterID: reciterID, reciterName: reciterName,
                                          moshafID: moshafID, serverBase: serverBase,
                                          order: order, current: surah.number)
        engine.onFinish = { [weak self] in self?.advanceOnDemand() }
        if record {
            recents.record(RecentItem(sourceID: "ondemand:\(reciterID):\(moshafID):\(surah.number)",
                                      kind: .onDemand, title: surah.translit, subtitle: reciterName,
                                      reciterID: reciterID, reciterName: reciterName, moshafID: moshafID,
                                      serverBase: serverBase.absoluteString, surahNumber: surah.number))
        }
    }
```

- [ ] **Step 3: Pass the moshaf order from `playOnDemand`**

Replace `playOnDemand(reciter:moshaf:surah:)` body (lines ~123-126) with:
```swift
    func playOnDemand(reciter: Reciter, moshaf: Moshaf, surah: Surah) {
        startOnDemand(reciterID: reciter.id, reciterName: reciter.name, moshafID: moshaf.id,
                      serverBase: moshaf.serverBase, surah: surah, order: moshaf.surahNumbers, record: true)
    }
```

- [ ] **Step 4: Resolve order from the catalog in `playRecent`**

In `playRecent(_:)`, replace the `.onDemand` case body (lines ~176-181) with:
```swift
        case .onDemand:
            guard let rID = item.reciterID, let rName = item.reciterName, let mID = item.moshafID,
                  let base = item.serverBase, let baseURL = URL(string: base), let n = item.surahNumber,
                  let surah = surahs.first(where: { $0.number == n })
            else { return }
            // Recents store only a single surah; recover the moshaf's full order from the catalog so a
            // replay can still autoplay. No match (catalog not loaded / reciter gone) → single-surah order.
            let order = catalog.reciters.first { $0.id == rID }?
                .moshafs.first { $0.id == mID }?.surahNumbers ?? [n]
            startOnDemand(reciterID: rID, reciterName: rName, moshafID: mID, serverBase: baseURL,
                          surah: surah, order: order, record: true)
```

- [ ] **Step 5: Add `advanceOnDemand()`**

Add near the mix advance methods (after `advanceMix()` ~line 345):
```swift
    /// Invoked by `engine.onFinish` when an on-demand surah ends: if autoplay is on, play the next
    /// surah the moshaf offers (skipping any number missing from the loaded `surahs`); stop at the end.
    private func advanceOnDemand() {
        guard settings.autoplayEnabled, let ctx = onDemandContext else { return }
        var after = ctx.current
        while let next = Autoplay.nextSurah(in: ctx.order, after: after) {
            if let surah = surahs.first(where: { $0.number == next }) {
                startOnDemand(reciterID: ctx.reciterID, reciterName: ctx.reciterName, moshafID: ctx.moshafID,
                              serverBase: ctx.serverBase, surah: surah, order: ctx.order, record: false)
                return
            }
            after = next   // number not in loaded surahs — keep scanning forward
        }
        clearOnDemandAutoplay()   // no resolvable next surah — stop
    }
```

- [ ] **Step 6: Clear the context when Library/Live/Mix take over**

In `playLocal(_:)`, add after the `if isMixing { stopMix() }` line (~148):
```swift
        clearOnDemandAutoplay()   // a finished local file must not resume on-demand autoplay
```
In `playStation(_:)`, add after the `if isMixing { stopMix() }` line (~160):
```swift
        clearOnDemandAutoplay()   // live has no finish, but drop any stale on-demand hook
```
In `startMix(config:pool:)`, add immediately before `engine.onFinish = { [weak self] in self?.advanceMix() }` (~301):
```swift
        onDemandContext = nil   // mix owns onFinish now
```
In `stopMix()`, add after `engine.onFinish = nil` (~374):
```swift
        onDemandContext = nil
```

- [ ] **Step 7: Build the app to verify it compiles**

Run: `xcodebuild -project Qurani.xcodeproj -scheme Qurani -configuration Debug -derivedDataPath .build-app -destination 'platform=macOS' build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 8: Commit**
```bash
git add App/AppModel.swift
git commit -m "feat: autoplay next surah for on-demand playback"
```

---

### Task 4: Settings toggle row (SettingsView)

**Files:**
- Modify: `App/Views/SettingsView.swift`

**Interfaces:**
- Consumes: `settings.autoplayEnabled` (Task 2), existing `settingRow(...)` + `toggle(_:)`.

- [ ] **Step 1: Add the `autoplayRow` view**

In `App/Views/SettingsView.swift`, add after `mediaKeysRow` (after line ~150):
```swift
    private var autoplayRow: some View {
        settingRow(icon: "play.circle.fill", title: "Autoplay next surah",
                   subtitle: "Continue through the reciter") {
            toggle($settings.autoplayEnabled)
        }
    }
```

- [ ] **Step 2: Place it in the PLAYBACK section**

In the settings body, add `autoplayRow` immediately after `mediaKeysRow` (line ~39):
```swift
                    hotkeyRow
                    mediaKeysRow
                    autoplayRow
                    sectionLabel("LIBRARY")
```

- [ ] **Step 3: Build to verify it compiles**

Run: `xcodebuild -project Qurani.xcodeproj -scheme Qurani -configuration Debug -derivedDataPath .build-app -destination 'platform=macOS' build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Install and verify by hand**

Run: `./install.sh`
Verify: play a surah from a reciter (Explore → reciter → surah); when it ends the next surah plays. Toggle **Settings → Autoplay next surah** off; the next on-demand surah plays once and stops. Confirm Mix still advances and starting a Mix / Library / Live item does not trigger on-demand autoplay.

- [ ] **Step 5: Commit**
```bash
git add App/Views/SettingsView.swift
git commit -m "feat: Settings toggle for autoplay next surah"
```

---

## Self-Review

**Spec coverage:** §3.1 SettingsStore → Task 2. §3.2 pure helper → Task 1. §3.3 AppModel wiring (context, startOnDemand record flag, playRecent catalog resolve, advanceOnDemand, clear-on-switch) → Task 3. §3.4 SettingsView toggle → Task 4. §5 edge cases (end→stop, missing→skip, toggle-off→no-op, source switch→clear, playRecent no match→single) → Task 3 Steps 4-6 + `advanceOnDemand`. §6 testing → Tasks 1-2 tests + Task 4 manual. All covered.

**Placeholder scan:** none — every step has concrete code/commands.

**Type consistency:** `Autoplay.nextSurah(in:after:) -> Int?` defined Task 1, used Task 3 Step 5. `autoplayEnabled` defined Task 2, used Task 3 (`settings.autoplayEnabled`) + Task 4 (`$settings.autoplayEnabled`). `startOnDemand(reciterID:reciterName:moshafID:serverBase:surah:order:record:)` defined Task 3 Step 2, called in Steps 3, 4, 5 with matching labels. `OnDemandContext` fields (`reciterID/reciterName/moshafID/serverBase/order/current`) consistent between Steps 1, 2, 5. Consistent.
