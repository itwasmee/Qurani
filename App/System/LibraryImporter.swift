import AppKit
import AVFoundation
import Combine
import UniformTypeIdentifiers
import QuraniKit

/// A file the importer has identified but not yet committed to the library. Surfaced in the
/// Task 7 review sheet, where the user confirms/edits the reciter + surah before it becomes a
/// `LocalTrack`. `bookmark` is a security-scoped bookmark created at import time; `guess` is the
/// `Tagger` heuristic used to pre-fill the sheet.
struct PendingImport: Identifiable, Sendable, Equatable {
    let id: UUID
    let url: URL
    let bookmark: Data
    let guess: Tagger.Guess
    let durationMs: Int?

    init(id: UUID = UUID(), url: URL, bookmark: Data, guess: Tagger.Guess, durationMs: Int?) {
        self.id = id
        self.url = url
        self.bookmark = bookmark
        self.guess = guess
        self.durationMs = durationMs
    }
}

/// The user's confirmed answer for one `PendingImport`, produced by the review sheet and handed
/// back to `AppModel.commitImports(_:)`.
struct ReviewedImport: Sendable, Equatable {
    let pendingID: UUID
    let reciterName: String
    let surahNumber: Int
}

/// Three import sources funnel into one `ingest(url:)` pipeline:
///   • `addFilesPanel()`   — an `NSOpenPanel` (audio files, multiple selection).
///   • `importDropped(_:)` — URLs from a Library-view drag-and-drop.
///   • watched folder      — a user-granted folder watched via a `DispatchSource`.
/// Each ingested file yields a `PendingImport` (security-scoped bookmark + `Tagger` guess); the
/// review sheet — not the importer — commits them to the library. Everything is `@MainActor`; the
/// only off-actor work is the async `AVAsset` metadata load.
@MainActor final class LibraryImporter: ObservableObject {
    /// Files identified but awaiting the review sheet's confirmation. Single source of truth;
    /// `AppModel` exposes this importer so views can observe the list directly.
    @Published private(set) var pendingImports: [PendingImport] = []

    /// Live surah list for `Tagger.guess` name-matching; set by `AppModel` once data has loaded.
    var surahs: [Surah] = []

    private let library: LibraryStore
    private let defaults: UserDefaults

    // Watched-folder state. `folderSource` fires on directory writes; `watchedFolderURL` holds the
    // folder's security-scoped access for the lifetime of the watch (child files inherit it).
    private var folderSource: DispatchSourceFileSystemObject?
    private var watchedFolderURL: URL?

    private static let libraryFolderBookmarkKey = "libraryFolderBookmark"
    private static let audioExtensions: Set<String> = ["mp3", "m4a", "aac", "m4b", "aif", "aiff", "wav", "caf"]
    private static let audioContentTypes: [UTType] = [.audio, .mp3, .mpeg4Audio]

    init(library: LibraryStore, defaults: UserDefaults = .standard) {
        self.library = library
        self.defaults = defaults
    }

    // Runs on the main actor (the class is `@MainActor`) so it can reach the isolated watch state;
    // releases the DispatchSource + folder access mirrored in `AVAudioPlayerAdapter`'s teardown.
    isolated deinit { stopWatching() }

    // MARK: - Add files panel

    /// Present an `NSOpenPanel` for audio files and ingest each chosen URL. `runModal()` keeps the
    /// flow fully on the main actor (no escaping completion handler to reason about).
    func addFilesPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = Self.audioContentTypes
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { ingest(url: url) }
    }

    // MARK: - Drag and drop

    /// Ingest URLs handed over by the Library view's `onDrop`.
    func importDropped(_ urls: [URL]) {
        for url in urls { ingest(url: url) }
    }

    // MARK: - Watched folder

    /// Let the user pick (and grant sandbox access to) the watched library folder, persist a
    /// security-scoped bookmark for it, then begin watching. Defaults the panel to `~/Music/Qurani`.
    func chooseLibraryFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = Self.defaultLibraryFolder()
        guard panel.runModal() == .OK, let url = panel.urls.first else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let bookmark = try? url.bookmarkData(options: .withSecurityScope,
                                                   includingResourceValuesForKeys: nil,
                                                   relativeTo: nil) else { return }
        defaults.set(bookmark, forKey: Self.libraryFolderBookmarkKey)
        stopWatching()      // drop any prior folder's watch before re-arming
        startWatching()
    }

    /// Begin watching the stored library folder for new audio files. A no-op when no folder
    /// bookmark has been granted yet (the user must run `chooseLibraryFolder()` first) or when a
    /// watch is already active.
    func startWatching() {
        guard folderSource == nil, let folder = resolveStoredLibraryFolder() else { return }
        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else { folder.stopAccessingSecurityScopedResource(); return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in
            // Delivered on `.main`, so we're on the main actor — assert it to reach isolated state
            // (same discipline as `AVAudioPlayerAdapter`'s `.main`-queue observers).
            MainActor.assumeIsolated { self?.scanLibraryFolder() }
        }
        source.setCancelHandler { close(fd) }
        folderSource = source
        watchedFolderURL = folder
        source.resume()
        scanLibraryFolder()   // initial sweep — pick up files already present
    }

    /// Stop watching: cancel the source (its cancel handler closes the fd) and release the folder's
    /// security-scoped access.
    func stopWatching() {
        folderSource?.cancel()
        folderSource = nil
        watchedFolderURL?.stopAccessingSecurityScopedResource()
        watchedFolderURL = nil
    }

    /// Enumerate the watched folder's audio files and ingest any not already pending or in the
    /// library. Child files are covered by the folder's security scope, so no per-file grant.
    private func scanLibraryFolder() {
        guard let folder = watchedFolderURL,
              let entries = try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants])
        else { return }
        let known = libraryPaths().union(pendingPaths())
        for entry in entries where Self.isAudioFile(entry) {
            guard !known.contains(entry.standardizedFileURL.path) else { continue }
            ingest(url: entry)
        }
    }

    // MARK: - Ingest

    /// Create a security-scoped bookmark for `url`, read its `AVAsset` metadata + duration, run the
    /// `Tagger` heuristic, and append a `PendingImport`. Does NOT add to the library — that waits
    /// for the review sheet. The async metadata load runs off the main actor; the append is back on it.
    private func ingest(url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        guard let bookmark = try? url.bookmarkData(options: .withSecurityScope,
                                                   includingResourceValuesForKeys: nil,
                                                   relativeTo: nil) else {
            if scoped { url.stopAccessingSecurityScopedResource() }
            return
        }
        let surahs = self.surahs
        Task { @MainActor in
            // Hold the file's access across the async metadata read, then balance the begin above.
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let (tags, durationMs) = await Self.loadMetadata(url: url)
            let guess = Tagger.guess(filename: url.deletingPathExtension().lastPathComponent,
                                     folder: url.deletingLastPathComponent().lastPathComponent,
                                     tags: tags, surahs: surahs)
            // De-dup by path against BOTH in-flight pending imports and already-committed library
            // tracks — so re-adding an imported file via Add-files / drag-drop can't create a
            // duplicate (mirrors `scanLibraryFolder`'s guard). Two write events for the same file can
            // also race two ingests here; the check + append run with no `await` between them, so it
            // stays atomic on the main actor.
            let path = url.standardizedFileURL.path
            guard !libraryPaths().union(pendingPaths()).contains(path) else { return }
            pendingImports.append(PendingImport(url: url, bookmark: bookmark, guess: guess, durationMs: durationMs))
        }
    }

    /// Remove the pending imports the review sheet has committed.
    func clearPending(ids: Set<UUID>) {
        pendingImports.removeAll { ids.contains($0.id) }
    }

    /// Seed `pendingImports` directly, bypassing the ingest pipeline — for snapshots / tests of the
    /// review sheet (mirrors `CatalogStore.seed` / `SourcesStore.seed`).
    func seedPending(_ imports: [PendingImport]) {
        pendingImports = imports
    }

    // MARK: - Metadata

    /// Load common `title`/`artist`/`album` tags and a millisecond duration off the main actor.
    /// Returns Sendable values only; the non-Sendable `AVMetadataItem`s never leave this task.
    nonisolated private static func loadMetadata(url: URL) async -> (tags: [String: String], durationMs: Int?) {
        let asset = AVURLAsset(url: url)
        var tags: [String: String] = [:]
        if let items = try? await asset.load(.commonMetadata) {
            for item in items {
                guard let key = item.commonKey else { continue }
                let mapped: String?
                if key == .commonKeyTitle { mapped = "title" }
                else if key == .commonKeyArtist { mapped = "artist" }
                else if key == .commonKeyAlbumName { mapped = "album" }
                else { mapped = nil }
                guard let mapped,
                      let value = (try? await item.load(.stringValue)) ?? nil,
                      !value.isEmpty else { continue }
                tags[mapped] = value
            }
        }
        var durationMs: Int?
        if let duration = try? await asset.load(.duration) {
            let seconds = duration.seconds
            if seconds.isFinite, seconds > 0 { durationMs = Int((seconds * 1000).rounded()) }
        }
        return (tags, durationMs)
    }

    // MARK: - Helpers

    /// Paths of files already committed to the library. Resolving a bookmark (unlike
    /// `startAccessingSecurityScopedResource`) doesn't begin access, so this has no side effects.
    private func libraryPaths() -> Set<String> {
        var paths: Set<String> = []
        for track in library.tracks {
            if let (url, _) = Self.resolveScopedBookmark(track.bookmark) {
                paths.insert(url.standardizedFileURL.path)
            }
        }
        return paths
    }

    private func pendingPaths() -> Set<String> {
        Set(pendingImports.map { $0.url.standardizedFileURL.path })
    }

    /// Resolve the stored library-folder bookmark and begin security-scoped access. Refreshes the
    /// stored bookmark in place if the system reports it stale. Returns nil when nothing is stored
    /// or resolution/access fails.
    private func resolveStoredLibraryFolder() -> URL? {
        guard let data = defaults.data(forKey: Self.libraryFolderBookmarkKey),
              let (url, isStale) = Self.resolveScopedBookmark(data),
              url.startAccessingSecurityScopedResource() else { return nil }
        if isStale, let refreshed = try? url.bookmarkData(options: .withSecurityScope,
                                                          includingResourceValuesForKeys: nil,
                                                          relativeTo: nil) {
            defaults.set(refreshed, forKey: Self.libraryFolderBookmarkKey)
        }
        return url
    }

    nonisolated private static func resolveScopedBookmark(_ data: Data) -> (url: URL, isStale: Bool)? {
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope],
                                 relativeTo: nil, bookmarkDataIsStale: &isStale) else { return nil }
        return (url, isStale)
    }

    /// The default watched-folder URL (`~/Music/Qurani`) *without* creating it — for display (the
    /// Library tab's folder bar) and as the base for `defaultLibraryFolder()`.
    nonisolated static func defaultLibraryFolderURL() -> URL {
        let music = (try? FileManager.default.url(for: .musicDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: false))
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Music", isDirectory: true)
        return music.appendingPathComponent("Qurani", isDirectory: true)
    }

    /// The default watched folder (`~/Music/Qurani`), created if missing so the panel can open there.
    nonisolated static func defaultLibraryFolder() -> URL {
        let folder = defaultLibraryFolderURL()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// The folder shown in the Library tab's bar: the user's granted watched folder if one has been
    /// chosen, else the default `~/Music/Qurani`. Display / Reveal only — resolving the bookmark here
    /// does NOT begin security-scoped access or create the directory.
    var libraryFolderURL: URL {
        if let data = defaults.data(forKey: Self.libraryFolderBookmarkKey),
           let (url, _) = Self.resolveScopedBookmark(data) {
            return url
        }
        return Self.defaultLibraryFolderURL()
    }

    private static func isAudioFile(_ url: URL) -> Bool {
        audioExtensions.contains(url.pathExtension.lowercased())
    }
}
