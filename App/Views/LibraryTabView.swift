import SwiftUI
import AppKit
import UniformTypeIdentifiers
import QuraniKit

/// The Library surface: a watched-folder bar (Reveal in Finder + Add files), the imported local pool
/// grouped by reciter → surah (Style-B `SurahNameView` rows, tap to play), and a dashed drop zone.
/// An empty hint shows until the first file is imported.
///
/// Observes `library`, `importer`, and `engine` directly so the list, the folder bar, and the
/// playing-row highlight all republish (AppModel does not forward its child stores' changes — same
/// lesson as Explore / Plan 1's engine).
struct LibraryTabView: View {
    @ObservedObject var library: LibraryStore
    @ObservedObject var importer: LibraryImporter
    @ObservedObject var engine: PlaybackEngine
    let surahs: [Surah]
    let tokens: Tokens
    let playLocal: (LocalTrack) -> Void

    /// number → Surah, memoized once (same reasoning as ReciterDetailView): `body` re-renders ~2×/s
    /// while a track ticks, and rebuilding a 114-entry dictionary each time would be pure churn.
    private let surahsByNumber: [Int: Surah]

    /// Reciter names whose surah list is collapsed. Empty == every group expanded (the useful default
    /// for a local pool); tapping a header toggles the chevron + its membership here.
    @State private var collapsed: Set<String> = []
    @State private var dropTargeted = false

    init(library: LibraryStore, importer: LibraryImporter, engine: PlaybackEngine,
         surahs: [Surah], tokens: Tokens, playLocal: @escaping (LocalTrack) -> Void) {
        _library = ObservedObject(wrappedValue: library)
        _importer = ObservedObject(wrappedValue: importer)
        _engine = ObservedObject(wrappedValue: engine)
        self.surahs = surahs
        self.surahsByNumber = Dictionary(surahs.map { ($0.number, $0) }, uniquingKeysWith: { a, _ in a })
        self.tokens = tokens
        self.playLocal = playLocal
    }

    var body: some View {
        VStack(spacing: 0) {
            folderBar
            if library.tracks.isEmpty {
                emptyState
            } else {
                groupList
            }
            dropZone
        }
        .frame(height: 300)
    }

    // MARK: - Folder bar (path · Add files · Reveal)

    private var folderBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder").font(.system(size: 13)).foregroundStyle(tokens.gold)
            Text(folderDisplayPath)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(tokens.gold.opacity(0.85))
                .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 6)
            Button(action: { importer.addFilesPanel() }) {
                HStack(spacing: 4) {
                    Image(systemName: "plus").font(.system(size: 10, weight: .bold))
                    Text("Add files").font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(tokens.accent)
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(tokens.accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .help("Add audio files to the library")
            Button(action: revealFolder) {
                HStack(spacing: 3) {
                    Text("Reveal").font(.system(size: 10, weight: .bold))
                    Image(systemName: "arrow.up.forward").font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(tokens.gold)
            }
            .buttonStyle(.plain)
            .help("Reveal the library folder in Finder")
        }
        .padding(.horizontal, 11).padding(.vertical, 8)
        .background(tokens.gold.opacity(0.08), in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(tokens.gold.opacity(0.16), lineWidth: 1))
        .padding(.horizontal, 13).padding(.top, 4).padding(.bottom, 8)
    }

    /// `~/Music/Qurani` (or the chosen folder), home abbreviated to `~` to match the mockup.
    private var folderDisplayPath: String {
        (importer.libraryFolderURL.path as NSString).abbreviatingWithTildeInPath
    }

    private func revealFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([importer.libraryFolderURL])
    }

    // MARK: - Grouped reciter → surah list

    private var groupList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(library.grouped(), id: \.reciter) { group in
                    groupHeader(group)
                    if !collapsed.contains(group.reciter) {
                        ForEach(group.tracks) { track in surahRow(track) }
                    }
                }
            }
            .padding(.horizontal, 7).padding(.bottom, 4)
        }
        .frame(maxHeight: .infinity)
    }

    private func groupHeader(_ group: (reciter: String, tracks: [LocalTrack])) -> some View {
        let expanded = !collapsed.contains(group.reciter)
        return HStack(spacing: 9) {
            Circle().fill(tokens.glassTint).frame(width: 34, height: 34)
                .overlay(Circle().stroke(Color.white.opacity(tokens.isDark ? 0.12 : 0.5), lineWidth: 1))
                .overlay(Image(systemName: "person.fill").font(.system(size: 15)).foregroundStyle(tokens.muted))
            Text(group.reciter).font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tokens.text).lineLimit(1)
            Spacer(minLength: 6)
            Text("\(group.tracks.count)").font(.system(size: 10, weight: .semibold)).foregroundStyle(tokens.muted)
            Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tokens.muted.opacity(0.8))
                .rotationEffect(.degrees(expanded ? 90 : 0))
        }
        .padding(.vertical, 7).padding(.horizontal, 9)
        .contentShape(Rectangle())
        .onTapGesture {
            if expanded { collapsed.insert(group.reciter) } else { collapsed.remove(group.reciter) }
        }
    }

    private func surahRow(_ track: LocalTrack) -> some View {
        let playing = isPlaying(track)
        let surah = surahsByNumber[track.surahNumber]
        let dur = Self.durationLabel(track.durationMs)
        // Carry the duration on the transliteration line (the mockup's `.sdur`) — reuses the shared
        // SurahNameView unchanged rather than forking it to add a duration slot.
        let translit: String
        switch (surah?.translit, dur) {
        case let (t?, d?): translit = "\(t) · \(d)"
        case let (t?, nil): translit = t
        case let (nil, d?): translit = d
        default: translit = ""
        }
        return SurahNameView(number: track.surahNumber,
                             nameAr: surah?.nameAr ?? "Surah \(track.surahNumber)",
                             translit: translit, tokens: tokens, playing: playing)
            .padding(.vertical, 6).padding(.horizontal, 9)
            .background(playing ? tokens.accent.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(tokens.accent.opacity(playing ? 0.22 : 0), lineWidth: 1))
            .padding(.leading, 12)   // nest the surah rows under their reciter group
            .contentShape(Rectangle())
            .onTapGesture { playLocal(track) }
    }

    /// Highlight the row whose local file is loaded AND actually playing — never during loading /
    /// paused, and keyed on the track id so duplicate surah names never collide.
    private func isPlaying(_ track: LocalTrack) -> Bool {
        engine.currentSourceID == "local:\(track.id)" && engine.status == .playing
    }

    // MARK: - Drop zone

    private var dropZone: some View {
        VStack(spacing: 5) {
            Image(systemName: "square.and.arrow.up").font(.system(size: 17))
                .foregroundStyle(dropTargeted ? tokens.accent : tokens.muted)
            HStack(spacing: 4) {
                Text("Drag audio here · or").font(.system(size: 11)).foregroundStyle(tokens.muted)
                Button(action: { importer.addFilesPanel() }) {
                    Text("Add files…").font(.system(size: 11, weight: .semibold)).foregroundStyle(tokens.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
        .background(dropTargeted ? tokens.accent.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13)
            .strokeBorder(dropTargeted ? tokens.accent.opacity(0.8) : Color.white.opacity(tokens.isDark ? 0.18 : 0.35),
                          style: StrokeStyle(lineWidth: 1.6, dash: [5, 4])))
        .padding(.horizontal, 13).padding(.top, 8).padding(.bottom, 10)
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted, perform: handleDrop)
    }

    /// Collect file URLs from the dropped providers and hand them to the importer. Capture `importer`
    /// (a main-actor — hence Sendable — object) into the `@Sendable` load callbacks rather than the
    /// non-Sendable View `self`; each resolved URL hops back to the main actor to ingest.
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let importer = self.importer
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in importer.importDropped([url]) }
            }
        }
        return true
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note.list").font(.system(size: 24)).foregroundStyle(tokens.muted)
            Text("No local files yet").font(.system(size: 12, weight: .semibold)).foregroundStyle(tokens.text)
            Text("Add files or drop audio").font(.system(size: 11)).foregroundStyle(tokens.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    /// `h:mm:ss` (or `m:ss` under an hour) from a millisecond duration; nil when unknown so the row
    /// shows just the transliteration. Uses the shared `TimeFormat` so a long recitation (≥ 1h, e.g.
    /// Al-Baqarah) reads "1:02:05" rather than the ambiguous "62:05" the old hand-rolled `%d:%02d` gave.
    private static func durationLabel(_ ms: Int?) -> String? {
        guard let ms, ms > 0 else { return nil }
        return TimeFormat.label(Double(ms) / 1000)
    }
}
