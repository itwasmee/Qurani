# Qurani — Plan 5: Settings + polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Ship the full Settings screen (the last missing feature) and clear the banked robustness/persistence fast-follows, leaving Qurani feature-complete and polished.

**Architecture:** A `SettingsStore` (persisted prefs) + a `SettingsView` (full glass panel matching `settings.html`) wire up theme, the global hotkey recorder, a media-keys toggle, the library folder + auto-import, and launch-at-login. Then a robustness pass (mix-pool persistence round-trip, watched-folder hardening, resource-access accrual, `#if DEBUG` seams, time formatting), and a final whole-app snapshot polish. Logic in `QuraniKit` where testable; macOS/UI glue in the app target.

**Tech Stack:** Swift 6, SwiftUI, KeyboardShortcuts (Recorder), ServiceManagement, Swift Testing, XcodeGen.

## Global Constraints
- macOS 26.0+, Swift 6 `-strict-concurrency=complete`, **pristine build (0 source warnings)**. UI `@MainActor`.
- One third-party dep stays `KeyboardShortcuts` (its `Recorder` view is allowed for the hotkey).
- Theme picker drives the same persisted `@AppStorage("theme")` the views already read. Launch-at-login via `SMAppService` (`LoginItem`). Auto-import + media-keys are persisted toggles.
- Match `.superpowers/brainstorm/4886-1782776450/content/settings.html`. Keep attribution (NOTICE.md) surfaced in About.
- Tests use Swift Testing; commit after each task; `swift test`/`xcodebuild`/`git` run sandbox-disabled.
- This is the LAST plan — leave the app feature-complete. Out of v1 scope (do NOT add): ayah text/translation, sleep timer, crossfade.

## File Structure
```
Sources/QuraniKit/Mix/MixEngine.swift     # (no change) — MixPreset persistence is app-level
Sources/QuraniKit/Settings/SettingsStore.swift  # NEW persisted prefs (mediaKeys, autoImport)
App/
├── System/NowPlayingBridge.swift   # MODIFY: media-keys toggle gates remote-command registration
├── System/LibraryImporter.swift    # MODIFY: auto-import toggle gates watching; copy-debounce; cache resolved paths
├── AppModel.swift                  # MODIFY: SettingsStore, mix-pool round-trip, resolveURL accrual fix, empty-queue hint
└── Views/
    ├── SettingsView.swift          # NEW full settings panel
    ├── GlassPanel.swift            # MODIFY: gear opens SettingsView (sheet/overlay)
    └── NowPlayingBar.swift         # MODIFY: mm:ss → h:mm:ss past 60 min
```

---

## Task 1: SettingsStore + SettingsView (the full screen)
**Files:** Create `Sources/QuraniKit/Settings/SettingsStore.swift`, `App/Views/SettingsView.swift`; Modify `App/Views/GlassPanel.swift`; Test `Tests/QuraniKitTests/SettingsStoreTests.swift`.

- `SettingsStore` (`@MainActor ObservableObject`, persisted like the other stores): `@Published var mediaKeysEnabled: Bool = true`, `@Published var autoImportEnabled: Bool = true`; `init(directory:)` + zero-arg; persist on change; missing/corrupt → defaults.
- `SettingsView` matching the mockup: sections —
  - **APPEARANCE:** 4 theme swatches (System / Sahar / Noor / Layl) bound to `@AppStorage("theme")` (selecting updates the panel live, as the gear menu already does).
  - **Play / Pause hotkey:** `KeyboardShortcuts.Recorder(for: .togglePlay)` + label.
  - **Media keys** toggle → `settings.mediaKeysEnabled`.
  - **LIBRARY:** library folder path + **Change** (`importer.chooseLibraryFolder()`) + **Reveal** (`NSWorkspace.activateFileViewerSelecting`); **Auto-import** toggle → `settings.autoImportEnabled`.
  - **GENERAL:** **Launch at login** toggle bound to `LoginItem` (catch the throw).
  - **About:** equalizer mark + "Qurani 1.0" + the NOTICE attribution lines.
- `GlassPanel`: the header **gear** opens `SettingsView` as a full-panel overlay/sheet (replacing the small inline theme/login menu, OR keep the menu and add a "Settings…" item that opens the full view — pick the cleaner one; the `•••` menu's "Settings…" stub from Plan 3 should now open this).
- [ ] TDD `SettingsStore` (persist round-trip: toggle mediaKeys off → fresh instance reads false). Build the app. `swift test` green + `xcodebuild` 0 warnings. Extend `--snapshot` to render `SettingsView` in Noor. Commit `feat: Settings store + full Settings screen`.

---

## Task 2: Wire the toggles + Mix-pool persistence round-trip
**Files:** Modify `App/AppModel.swift`, `App/System/NowPlayingBridge.swift`, `App/System/LibraryImporter.swift`, `App/Views/MixTabView.swift`.

- **Media-keys toggle:** `NowPlayingBridge` registers the `MPRemoteCommandCenter` handlers only when `settings.mediaKeysEnabled`; toggling re-applies (enable/disable the commands). Keep `MPNowPlayingInfoCenter` updates regardless.
- **Auto-import toggle:** `LibraryImporter.startWatching()` is a no-op (and `stopWatching()`) when `settings.autoImportEnabled == false`; toggling on re-arms.
- **Mix-pool round-trip (the NEW finding):** the Mix-tab on-demand selection should persist — when a user ticks an on-demand reciter in the Mix build pool, write it to `MixPoolStore` (so it survives relaunch and matches Explore's "add to pool"); seed the Mix tab's on-demand selection from `pool.reciterIDs` and write back on toggle. Local picks stay session-scoped (no persistent local-pool store in v1 — document). Reconcile phantom selections: drop selected ids/names no longer present in `catalog`/`library` before showing the count.
- [ ] Build + manual-note the runtime toggles. `swift test` green, `xcodebuild` 0 warnings. Commit `feat: wire media-keys/auto-import toggles + persist Mix pool selection`.

---

## Task 3: Robustness polish sweep
**Files:** Modify `App/AppModel.swift`, `App/System/LibraryImporter.swift`, `App/Views/NowPlayingBar.swift`, `Sources/QuraniKit/Playback/PlaybackEngine.swift` (doc), plus `#if DEBUG` on the snapshot/test seams.

Clear the banked fast-follows:
- **resolveURL session-accrual:** `AppModel.playLocal` (and the mix local path) should retain the previously-resolved security-scoped URL and `stopAccessingSecurityScopedResource()` it before resolving the next (so distinct plays don't leak scopes).
- **Watched-folder hardening:** in `LibraryImporter`, (a) cache resolved library paths and recompute only when the library changes (not per FS event), and (b) add a brief size-stability debounce before ingesting a newly-appeared file (avoid partial-copy AVAsset reads).
- **Empty-queue Mix Start:** when a non-empty selection yields an empty queue (no covered surah in range), don't silently `engine.stop()` — surface a small "No surahs in range for this pool" hint in the Mix tab and don't tear down current audio.
- **mm:ss → h:mm:ss:** `NowPlayingBar.timeLabel` shows `h:mm:ss` past 60 min (Al-Baqarah etc.).
- **`#if DEBUG`-gate** the snapshot/test seams: `seedMix`, `seedPending`, `seed`, `storesDirectory`/`init(storesDirectory:)`, `SnapshotRunner` — so they don't ship in release.
- **Stale doc comments:** update `PlaybackEngine.currentSourceID` doc to list all three formats (`live:`/`ondemand:`/`local:`).
- [ ] Build + `swift test` green + `xcodebuild` 0 warnings. Add a `timeLabel` h:mm:ss unit test if you extract it to a testable helper. Commit `chore: robustness polish (scoped-access, watch debounce, time format, debug seams)`.

---

## Task 4: Final visual polish pass
**Files:** As needed across `App/Views/`; extend `--snapshot`.

- Render EVERY tab in BOTH Noor (dark) and Sahar (light) via `--snapshot`: Live, Explore (list + detail), Library, Mix (build + playing), Now-Playing (live/on-demand/mix), Settings. Compare against the mockups in `.superpowers/brainstorm/4886-1782776450/content/`.
- Fix any visual gaps that are cheap and high-value: spacing/padding inconsistencies, missing source badges, Sahar-theme legibility (the offscreen render lacks vibrancy — focus on tokens/contrast/layout, not the blur), the equalizer/medallion alignment. Don't refactor; targeted polish only.
- [ ] Build + `swift test` green + `xcodebuild` 0 warnings. Write the PNG paths in the report for controller review. Commit `polish: final visual pass across all tabs (Noor + Sahar)`.

---

## Definition of done (Plan 5)
- `swift test` green (SettingsStore + any extracted helpers).
- App builds pristine; the **gear opens a full Settings screen** (theme / hotkey recorder / media-keys / library folder + auto-import / launch-at-login / About) matching the mockup; the toggles actually gate behavior; the Mix-tab on-demand pool persists.
- Robustness fast-follows cleared (scoped-access accrual, watched-folder debounce, empty-queue hint, h:mm:ss, `#if DEBUG` seams).
- Final snapshots show all tabs faithful in both themes.
- Qurani is **feature-complete** per the spec (v1 scope): Live, Explore, Library, Mix, Settings — all working.

This is the last plan. After merge, Qurani v1 is complete.
