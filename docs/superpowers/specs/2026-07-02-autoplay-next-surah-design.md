# Autoplay next surah (on-demand) — Design Spec

- **Date:** 2026-07-02
- **Status:** Approved, ready for implementation planning.
- **Scope:** One focused feature. No decomposition needed.

## 1. Summary

When a surah is playing **on-demand from a reciter** (Explore → `ReciterDetailView` → `playOnDemand`, and on-demand history replays via `playRecent`), finishing it auto-advances to the **next surah in that moshaf's ordered `surahNumbers` list**. Playback **stops** after the last surah in the list. Behaviour is gated by a new Settings toggle **"Autoplay next surah"**, default **on**.

Out of scope: Live (streams never finish) and Library (single local files). **Mix is untouched** — it already auto-advances through its own queue via `engine.onFinish = advanceMix`.

## 2. Behaviour

- Tap a surah in a reciter's detail page → it plays. When it ends, the next surah the moshaf offers plays automatically, and so on, until the list is exhausted, then playback stops.
- The order is the moshaf's own `surahNumbers` (the surahs that reciter actually offers — may be sparse or partial), **not** a raw 1→114 count.
- Toggle **off** → an on-demand surah plays once and stops (today's behaviour).
- Toggle **off mid-play** → the current surah finishes, no advance.

## 3. Components

### 3.1 `SettingsStore` (QuraniKit)
Add `autoplayEnabled: Bool`, persisted and defaulted exactly like `mediaKeysEnabled` / `autoImportEnabled` (defaults to `true` when the settings file is missing/corrupt).

### 3.2 Pure helper (QuraniKit) — testable core
```
func nextSurahNumber(in order: [Int], after current: Int) -> Int?
```
Returns the element after the first occurrence of `current` in `order`, or `nil` if `current` is last or absent. Placed in QuraniKit (not AppModel) so it is covered by `swift test`; AppModel is in the App target, which has no unit-test bundle.

### 3.3 `AppModel` (App target) — wiring
- New private state: an on-demand context `(reciterID: Int, reciterName: String, moshafID: Int, serverBase: URL, order: [Int])?`.
- `startOnDemand(...)` gains the ordered list and a `record: Bool` flag:
  - Stores the context.
  - Arms `engine.onFinish = { advanceOnDemand() }`.
  - Records to `recents` only when `record == true`.
- `playOnDemand(reciter, moshaf, surah)` → `startOnDemand(..., order: moshaf.surahNumbers, record: true)`.
- `playRecent(.onDemand)` → resolve `order` from `catalog` (match `reciterID` + `moshafID`); if not found, `order = [surah.number]` (single → no autoplay). `record: true` (replays still move history front, unchanged).
- `advanceOnDemand()`:
  - Guard `settings.autoplayEnabled`, else return (stops).
  - Compute `nextSurahNumber(in: ctx.order, after: currentSurahNumber)`. If a next surah exists **and** resolves in `surahs`, play it via `startOnDemand(..., record: false)`. If the next number isn't in `surahs` (sparse feed), continue scanning forward for the next resolvable one; if none, stop + clear context.
  - `record: false` → auto-advanced surahs are **not** added to `recents` (mirrors Mix's "not mix-internal surahs" rule; avoids flooding history). The now-playing bar still reflects the current surah via `engine.play`.
- `playLocal`, `playStation`, `startMix` clear the on-demand context and reassign/clear `engine.onFinish` (mix sets its own; local/live set `nil`) so a finished non-on-demand item never triggers on-demand autoplay.

### 3.4 `SettingsView` (App target)
Add one toggle row, "Autoplay next surah", bound to `settings.autoplayEnabled`, reusing the existing toggle row styling used by media-keys / auto-import.

## 4. Data flow

```
tap surah → playOnDemand → startOnDemand(order, record:true)
              ├─ stores onDemand context
              ├─ engine.onFinish = advanceOnDemand
              └─ engine.play(.onDemand …)
        … surah finishes → engine.onFinish → advanceOnDemand()
              ├─ toggle off → return (stops)
              └─ next in order resolvable → startOnDemand(next, record:false) → repeat
        … last surah finishes → no next → stop, clear context
```

## 5. Edge cases

- **End of list** → stop, clear context.
- **Next number missing from loaded `surahs`** → skip forward to the next resolvable; none → stop.
- **Toggle off** → `advanceOnDemand` no-ops.
- **Source switch** (tap another surah/reciter, Live, Library, Mix) → context replaced or cleared; `onFinish` repurposed.
- **`playRecent` with no catalog match** → single-surah order → plays once, no advance.

## 6. Testing

- Unit-test `nextSurahNumber(in:after:)` in QuraniKit: mid-list returns next; last returns `nil`; absent returns `nil`; single-element returns `nil`; sparse/non-contiguous order.
- `SettingsStore.autoplayEnabled` persistence + default-on (extend existing settings tests).
- AppModel wiring (context arming, record:false on advance, clear-on-switch) verified by building the app and a manual/snapshot run — AppModel has no unit-test target, consistent with the existing `advanceMix` wiring.

## 7. Non-goals

- Library autoplay (advance through a reciter's local surahs) — possible later.
- Looping at end of list.
- Cross-moshaf or cross-reciter continuation.
