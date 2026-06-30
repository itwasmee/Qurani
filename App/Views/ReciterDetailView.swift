import SwiftUI
import QuraniKit

/// Detail for one reciter: a back + name header, ♡ favorite and ＋/✓ Mix-pool toggles,
/// an optional moshaf (riwaya) picker when there's more than one set, and the surah list.
/// Tapping a surah streams it on demand through the bottom Now-Playing bar.
///
/// Observes `engine`, `favorites`, and `pool` directly so the toggles and the playing-row
/// highlight republish (AppModel does not forward child changes — same lesson as Plan 1).
struct ReciterDetailView: View {
    let reciter: Reciter
    @ObservedObject var favorites: FavoritesStore
    @ObservedObject var pool: MixPoolStore
    @ObservedObject var engine: PlaybackEngine
    let surahs: [Surah]
    let tokens: Tokens
    let onBack: () -> Void
    let play: (Reciter, Moshaf, Surah) -> Void

    @State private var activeMoshaf: Moshaf?

    init(reciter: Reciter, favorites: FavoritesStore, pool: MixPoolStore,
         engine: PlaybackEngine, surahs: [Surah], tokens: Tokens,
         onBack: @escaping () -> Void, play: @escaping (Reciter, Moshaf, Surah) -> Void) {
        self.reciter = reciter
        _favorites = ObservedObject(wrappedValue: favorites)
        _pool = ObservedObject(wrappedValue: pool)
        _engine = ObservedObject(wrappedValue: engine)
        self.surahs = surahs
        self.tokens = tokens
        self.onBack = onBack
        self.play = play
        _activeMoshaf = State(initialValue: reciter.moshafs.first)
    }

    private var moshaf: Moshaf? { activeMoshaf ?? reciter.moshafs.first }
    private var isFavorite: Bool { favorites.isFavorite(reciter: reciter.id) }
    private var inPool: Bool { pool.contains(reciter.id) }

    /// The active moshaf's surahs, mapped from its `surahNumbers` onto the loaded `Surah`
    /// records. Numbers with no match (sparse feeds) are skipped, never crash.
    private var listedSurahs: [Surah] {
        guard let moshaf else { return [] }
        let byNumber = Dictionary(surahs.map { ($0.number, $0) }, uniquingKeysWith: { a, _ in a })
        return moshaf.surahNumbers.compactMap { byNumber[$0] }
    }

    private func isPlaying(_ surah: Surah) -> Bool {
        engine.currentSourceID == "ondemand:\(reciter.name):\(surah.number)" && engine.status == .playing
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if reciter.moshafs.count > 1 { moshafPicker }
            surahList
        }
        .frame(height: 300)
    }

    // MARK: - Header (back + name, favorite + pool)

    private var header: some View {
        HStack(spacing: 8) {
            Button(action: onBack) {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold))
                    Text(reciter.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                }
                .foregroundStyle(tokens.text)
            }
            .buttonStyle(.plain)
            Spacer(minLength: 8)
            actButton(symbol: isFavorite ? "heart.fill" : "heart", on: isFavorite,
                      help: isFavorite ? "Unfavorite" : "Favorite") {
                favorites.toggle(reciter: reciter.id)
            }
            actButton(symbol: inPool ? "checkmark" : "plus", on: inPool,
                      help: inPool ? "Remove from Mix pool" : "Add to Mix pool") {
                pool.toggle(reciter: reciter.id)
            }
        }
        .padding(.horizontal, 13).padding(.top, 4).padding(.bottom, 8)
    }

    private func actButton(symbol: String, on: Bool, help: String,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
                .foregroundStyle(on ? tokens.accent : tokens.muted)
                .frame(width: 28, height: 28)
                .background(on ? tokens.accent.opacity(0.18) : tokens.glassTint,
                            in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - Moshaf (riwaya) picker

    private var moshafPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(reciter.moshafs) { m in
                    FilterChip(text: m.name, on: m.id == moshaf?.id, tokens: tokens) {
                        activeMoshaf = m
                    }
                }
            }
            .padding(.horizontal, 13)
        }
        .padding(.bottom, 8)
    }

    // MARK: - Surah list

    private var surahList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                sectionLabel
                if listedSurahs.isEmpty {
                    emptyState
                } else {
                    ForEach(listedSurahs) { surah in surahRow(surah) }
                }
            }
            .padding(.horizontal, 8).padding(.bottom, 4)
        }
    }

    private var sectionLabel: some View {
        HStack {
            Text("\(listedSurahs.count) SURAHS")
                .font(.system(size: 9.5, weight: .bold)).tracking(1.4)
            Spacer()
            Text("streaming").font(.system(size: 9.5, weight: .bold))
        }
        .foregroundStyle(tokens.muted)
        .padding(.horizontal, 8).padding(.top, 6).padding(.bottom, 4)
    }

    private func surahRow(_ surah: Surah) -> some View {
        let playing = isPlaying(surah)
        return SurahNameView(number: surah.number, nameAr: surah.nameAr,
                             translit: "\(surah.translit) · \(surah.ayahCount) verses",
                             tokens: tokens, playing: playing)
            .padding(.vertical, 6).padding(.horizontal, 8)
            .background(playing ? tokens.accent.opacity(0.10) : .clear,
                        in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(tokens.accent.opacity(playing ? 0.22 : 0), lineWidth: 1))
            .contentShape(Rectangle())
            .onTapGesture { if let moshaf { play(reciter, moshaf, surah) } }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "waveform.slash").font(.system(size: 20)).foregroundStyle(tokens.muted)
            Text("No surahs in this recitation")
                .font(.system(size: 11)).foregroundStyle(tokens.muted)
        }
        .frame(maxWidth: .infinity).padding(.top, 56)
    }
}
