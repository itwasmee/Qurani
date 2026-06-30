# Qurani — Design Spec

- **Date:** 2026-06-30
- **Status:** Validated (9 visual mockups approved one-by-one). Ready for implementation planning.
- **Platform:** macOS 26+ (Tahoe), native.

## 1. Summary

Qurani is a minimal, beautiful **macOS menubar app** for listening to the Qur'an. Four surfaces:

- **Live Radio** — curated free live feeds (Makkah, Madinah, Egypt Quran Al-Kareem, Saudi Quran Radio) plus 174 always-on per-reciter stations.
- **Explore Reciters** — browse a free 200+ reciter catalog and stream any surah instantly to discover new qaris.
- **Library** — a personal local pool: drag-drop / watched-folder import, smart auto-tagging, grouped by reciter → surah.
- **Mix** — the signature feature: a **Random per-surah station** where each surah is recited by a randomly-chosen qari from a user-defined pool (local + on-demand).

Native SwiftUI, real Liquid Glass, tiny footprint, **free sources only**.

## 2. Goals & non-goals

**Goals:** minimal top-bar footprint; beautiful Liquid-Glass UI; efficient (near-zero idle cost); latest packages; free/legal sources; explore-new-reciters workflow; mix qaris randomly per surah; local upload.

**Non-goals (v1):** ayah text / translation / word-highlighting; sleep timer; crossfade in mix; video playback (we play the *audio* of HLS video feeds — a video popout is a possible future); offline downloads of on-demand audio; iOS / Windows.

## 3. Platform & stack

- **macOS 26+**, Apple Silicon + Intel. Swift 6, SwiftUI, strict concurrency, SwiftPM.
- **App type:** `MenuBarExtra` with `.menuBarExtraStyle(.window)`, `LSUIElement` agent (no dock icon, no main window).
- **Liquid Glass:** native `.glassEffect` / `GlassEffectContainer` / `NSGlassEffectView`. Wrap sibling glass in one container (glass can't sample glass); content opaque; respect Reduce Transparency.
- **Audio:** `AVPlayer` + `AVPlayerItemMetadataOutput` (streaming, ICY `StreamTitle`, HLS in-band ID3); `AVAsset` metadata for local tag reading. **AudioStreaming** (dimitris-c, MIT) kept on the bench as an Icecast-metadata fallback only.
- **Media keys / Now Playing:** `MPRemoteCommandCenter` + `MPNowPlayingInfoCenter` (also drives Control Center widget).
- **Global hotkey:** `KeyboardShortcuts` (sindresorhus, MIT) — the one third-party runtime dependency.
- **Launch at login:** native `SMAppService`.
- **Surah metadata:** bundled JSON — fully-vowelized names from **Tanzil/QUL**, structure from **semarketir/quranjson** (MIT). 114 surah rows + juz.
- **Fonts (bundled, OFL):** **Amiri Quran** (surah names), **Noto Naskh Arabic** (numerals/secondary). Optional **KFGQPC Surah-Names** font for true plate glyphs (future).
- **mp3quran v3 REST:** hit directly (~3 Codable structs); no wrapper exists.

**Footprint target:** ~5–15 MB bundle, single AVPlayer instance, network only on demand, near-zero idle CPU/RAM.

**Reference reading (not deps):** quran/quran-ios (QuranEngine, Apache-2.0) for architecture; drmikexo2/DIBar-macOS for the exact MenuBarExtra + AVPlayer + remote-command wiring.

## 4. Visual design (validated)

### 4.1 Theming
- **System** (default): auto-switch on `effectiveAppearance` — Light → Sahar, Dark → Noor.
- **Sahar** (Light): warm sand/parchment glass, teal accent.
- **Noor** (Dark): near-monochrome frosted glass, single emerald accent. Primary dark look.
- **Layl** (optional override): midnight glass, moonlit gold accent.
- Settings picker: **System / Sahar / Noor / Layl**.

### 4.2 Menubar icon
- **Equalizer** — 4 bars. **Idle** = static stepped; **Playing** = bouncing animation. Monochrome template image → auto-inverts for light/dark menubars.
- **Right-click context menu:** Add Files to Library…, Reveal Library Folder, Pause, Next (random), Settings…, Quit.

### 4.3 Surah-name standard (Style B — used everywhere)
- Fully **vowelized (tashkeel)** Arabic name in **Amiri Quran**.
- **Numbered medallion** (circle, Noto Naskh numeral, optically centered `padding-top:4px`), thin accent rule on hero.
- Transliteration + English beneath. **Highlighted/active** state = accent background + equalizer.

### 4.4 Panel layout
- ~360 pt glass panel anchored under the menubar icon (notch).
- **Header:** brand (equalizer mark) + ⚙ gear.
- **Segmented tabs:** Live · Explore · Library · Mix.
- **Persistent bottom now-playing bar** (collapsed): art, surah/station, play-pause, hairline progress (or **LIVE** pill for streams). **Tap → expands** to the full Now-Playing sheet.

### 4.5 Now-Playing sheet
Source chip (**LIVE / ON-DEMAND / MIX / LIBRARY**), large art, Style-B surah name, reciter + source tag, scrubber + times, transport (shuffle · prev · play · next · ♡), volume, and for Mix an **Up next · random** row (next surah + its random qari + dice/re-roll).

## 5. Features & screens

Each screen below was mocked and approved. Mockups: `.superpowers/brainstorm/<session>/content/*.html` (git-ignored local artifacts).

### 5.1 Live Radio — `live-tab.html`
- **Featured:** Makkah (Al-Haram, HLS video+audio), Madinah (An-Nabawi, HLS), **Egypt — Quran Al-Kareem, Cairo** (radiojar mp3), Saudi Quran Radio (HLS/mp3). VIDEO badge on Makkah/Madinah (audio is played; video popout is future).
- **174 reciter 24/7 stations** (mp3quran/qurango), searchable. Reciter is fixed per station.
- **Now-playing realism:** station identity + fixed reciter; **best-effort surah** from ICY `StreamTitle` when present; never fabricate metadata.

### 5.2 Explore Reciters — `explore-tab.html`
- mp3quran catalog (200+ reciters); search + riwaya filter (Hafs / Warsh / Mujawwad / Muallim).
- Reciter → moshaf selector → 114-surah list → **instant stream**.
- Actions per reciter/surah: **♡ favorite**, **＋ add to Mix pool**.

### 5.3 Library — `library-tab.html`
- Grouped **reciter → surah** (Style-B names).
- **Import paths:** `Add files…` button; **drag-drop** onto the panel (full-window overlay); **watched folder `~/Music/Qurani`** with **Reveal in Finder** — files dropped there via Finder auto-import.
- **Smart tagger:** parse filename + folder + AVAsset tags → (reciter, surah, confidence). **Review sheet** to fix guesses; amber = low confidence needing attention.
- **Security-scoped bookmarks** so file access survives relaunch.
- **Quran-only is a guideline** (no content enforcement).

### 5.4 Mix — Random per-surah station — `mix-tab.html`
- **Pool:** select reciters from **local 📚 + favorited on-demand ☁︎** (badged).
- **Surah order:** In order (1→114) or **Shuffle**. **Range:** Full Qur'an / By Juz' / Custom.
- **Engine:** over the chosen surah range, for each surah pick a **uniformly-random reciter from the pool that actually has that surah** (local file or on-demand moshaf). Sequential playback, hard cuts. **Re-roll** regenerates assignments. Save as a named preset.
- Each queued surah resolves to either a local file or an on-demand stream depending on the chosen reciter's source.

### 5.5 Settings — `settings.html`
- **Appearance** theme picker (System/Sahar/Noor/Layl).
- **Play/Pause** global hotkey (default ⌃⌥Space, recordable) + **Media keys** toggle.
- **Library** folder (Change / Reveal) + **Auto-import** (watch & smart-tag) toggle.
- **Launch at login** toggle.
- **About** + free-source attribution.

### 5.6 Also validated
`visual-style.html` (theme directions), `menubar-icon.html` (icon/motion), `panel-now-playing.html` (Now-Playing in Noor + Sahar), `surah-typography.html` (Style-B selection).

## 6. Sources (verified live 2026-06-29/30)

All free, keyless, CORS-open, Range-seekable unless noted. Attribution + per-source TOS check before shipping.

### Live streams
| Station | URL | Format | Notes |
|---|---|---|---|
| Makkah — Al-Haram | `https://cdn-globecast.akamaized.net/live/eds/saudi_quran/hls_roku/index.m3u8` | HLS (video+audio) | Akamai, CORS `*` |
| Madinah — An-Nabawi | `https://cdn-globecast.akamaized.net/live/eds/saudi_sunnah/hls_roku/index.m3u8` | HLS (video+audio) | Akamai, CORS `*` |
| KSA Quran Radio | `https://live.kwikmotion.com/sbrksaquranradiolive/srpksaquranradio/playlist.m3u8` | HLS (audio) | |
| Saudi Quran Radio (mp3) | `https://stream.radiojar.com/0tpy1h0kxtzuv` | mp3/ICY | 302 → http; AVPlayer follows natively |
| **Egypt — Quran Al-Kareem, Cairo** | `https://stream.radiojar.com/8s5u5tpdtwzuv` | mp3/ICY | ERTU Cairo |
| 174 reciter stations | `https://www.mp3quran.net/api/v3/radios?language=ar\|eng` → `https://qurango.net/radio/{slug}` | mp3 128k/ICY | **Rewrite `backup.qurango.net` → `qurango.net`** (backup host 500s) |

### On-demand APIs
- **mp3quran v3** `https://www.mp3quran.net/api/v3` — `/reciters`, `/suwar`, `/radios`; audio = `{moshaf.server}/{NNN}.mp3`. Some moshaf servers are `http://` → force `https://` / ATS exception.
- **everyayah** `https://everyayah.com/data/{Reciter_bitrate}/{SSSAAA}.mp3` (per-ayah).
- **quranicaudio** `/api/qaris` (180) + `https://download.quranicaudio.com/quran/{path}{NNN}.mp3` (gapless per-surah).
- **alquran.cloud / cdn.islamic.network** — 42 audio editions, per-surah + per-ayah.
- **Quran.com v4** `https://api.quran.com/api/v4` — `/chapters` (names + transliteration), recitations, optional word-timing `segments` (future highlight feature).

**Caveat (designed-around):** no live stream reliably emits now-playing reciter/surah; `icy-name` is generic/"N/A". Exact now-playing only exists on our own sequenced playback (Explore / Library / Mix).

## 7. Architecture / modules

Each is isolated, single-purpose, independently testable.

- **PlaybackEngine** — sole `AVPlayer` owner; plays a `PlaybackItem`; sequences the Mix queue; publishes `NowPlaying`; bridges `MPNowPlayingInfoCenter` / `MPRemoteCommandCenter`; reads ICY/HLS metadata via `AVPlayerItemMetadataOutput`.
- **SourcesStore** — curated live stations (bundled JSON) + mp3quran `/radios` (fetched, cached, host-rewritten).
- **CatalogService** — mp3quran v3 client (reciters / moshaf / suwar), cached.
- **LibraryStore + Tagger** — import; filename/folder/AVAsset parsing → (reciter, surah, confidence); FSEvents watch on the library folder; security-scoped bookmarks; persistence.
- **MixEngine** — pool → random per-surah queue (order/range), availability resolution, re-roll, presets.
- **QuranData** — bundled vowelized surah metadata (114) + juz.
- **FavoritesStore / RecentsStore**.
- **Hotkeys** (KeyboardShortcuts) · **LoginItem** (SMAppService) · **ThemeController** (effectiveAppearance observer + override).
- **UI** — MenuBarExtra scene; per-tab panel views; NowPlaying sheet; reusable **SurahNameView** (Style-B); glass container wrappers; context menu.

## 8. Data model

```
PlaybackItem = .liveStation(Station)
             | .onDemand(reciter, moshaf, surah)
             | .localTrack(LocalTrack)
             | .mixItem(surah, resolvedSource)

Station   { id, name, region, kind: hls|icecast, url, reciter?, hasVideo, artworkHint }
Reciter   { id, nameAr, nameEn, moshafs: [Moshaf] }
Moshaf    { name(riwaya), serverBase, surahList: Set<Int> }
Surah     { number, nameArTashkeel, translit, nameEn, ayahCount, place: makki|madani, juz }
LocalTrack{ bookmarkData, reciterName, surahNumber, confidence, durationMs }
MixPreset { name, pool: [ReciterRef], order: inOrder|shuffle, range: full|juz|custom }
ReciterRef{ source: local|onDemand, id }
```

## 9. Persistence

- **Defaults:** theme, volume, hotkey, launch-at-login, library folder, last source.
- **Application Support/Qurani:** `library.json` (→ SQLite only if a library grows large), `favorites.json`, `recents.json`, `mixpresets.json`, plus caches (catalog JSON, artwork).
- **Security-scoped bookmarks** for imported files and the library folder.

## 10. Efficiency

`LSUIElement` agent; single paused `AVPlayer` when idle; network strictly on demand; cached catalog/artwork; respects Low Power / Reduce Transparency.

## 11. Risks / open items

- **Live ICY metadata unreliable** → handled (station identity + best-effort, no fake data).
- **radiojar 302→http + ATS** → AVPlayer follows; prefer https base, ATS exceptions for known hosts.
- **mp3quran http moshaf servers** → upgrade to https.
- **qurango backup host 500s** → rewrite to `qurango.net`.
- **Mix pool reciter lacks a surah** → resolve to another pool reciter that has it; if none, skip surah.
- **Licensing** → OFL fonts + permissive metadata; attribution screen; per-source TOS check before any distribution.

## 12. Out of scope (v1)

ayah text/translation/word-highlight (data exists via Quran.com `segments` — future), sleep timer, crossfade, video popout, offline downloads, non-macOS platforms.
