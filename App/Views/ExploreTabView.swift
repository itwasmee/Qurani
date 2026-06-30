import SwiftUI
import QuraniKit

/// The Explore surface: search + riwaya filter over the reciter catalog, drilling into a
/// `ReciterDetailView` to stream any surah on demand. A `@State selectedReciter` swaps the
/// catalog for the detail in place (no NavigationStack — keeps everything in the 344-wide
/// panel). Observes `catalog`, `favorites`, `pool`, and `engine` directly so they republish.
struct ExploreTabView: View {
    @ObservedObject var catalog: CatalogStore
    @ObservedObject var favorites: FavoritesStore
    @ObservedObject var pool: MixPoolStore
    @ObservedObject var engine: PlaybackEngine
    let surahs: [Surah]
    let tokens: Tokens
    let play: (Reciter, Moshaf, Surah) -> Void

    @State private var search = ""
    @State private var riwaya: String?          // nil == All
    @State private var selectedReciter: Reciter?

    /// Filter labels → the token passed to `catalog.filtered(riwaya:)`. "All" maps to nil.
    private let riwayat = ["Hafs", "Warsh", "Mujawwad", "Muallim"]

    private var results: [Reciter] { catalog.filtered(search: search, riwaya: riwaya) }

    var body: some View {
        if let selectedReciter {
            ReciterDetailView(reciter: selectedReciter, favorites: favorites, pool: pool,
                              engine: engine, surahs: surahs, tokens: tokens,
                              onBack: { self.selectedReciter = nil }, play: play)
                .id(selectedReciter.id)
        } else {
            catalogView
        }
    }

    // MARK: - Catalog (search + chips + list)

    private var catalogView: some View {
        VStack(spacing: 0) {
            searchField
            chipRow
            list
        }
        .frame(height: 300)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(tokens.muted)
            TextField("Search 200+ reciters…", text: $search)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .foregroundStyle(tokens.text)
        }
        .padding(.horizontal, 11).padding(.vertical, 8)
        .background(tokens.glassTint, in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11)
            .stroke(Color.white.opacity(tokens.isDark ? 0.07 : 0.4), lineWidth: 1))
        .padding(.horizontal, 13).padding(.top, 4).padding(.bottom, 10)
    }

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                FilterChip(text: "All", on: riwaya == nil, tokens: tokens) { riwaya = nil }
                ForEach(riwayat, id: \.self) { r in
                    FilterChip(text: r, on: riwaya == r, tokens: tokens) { riwaya = r }
                }
            }
            .padding(.horizontal, 13)
        }
        .padding(.bottom, 8)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                sectionLabel
                if results.isEmpty {
                    emptyState
                } else {
                    ForEach(results) { r in
                        ReciterRow(reciter: r, pool: pool, tokens: tokens)
                            .background(isPlayingReciter(r) ? tokens.accent.opacity(0.10) : .clear,
                                        in: RoundedRectangle(cornerRadius: 13))
                            .overlay(RoundedRectangle(cornerRadius: 13)
                                .stroke(tokens.accent.opacity(isPlayingReciter(r) ? 0.22 : 0), lineWidth: 1))
                            .contentShape(Rectangle())
                            .onTapGesture { selectedReciter = r }
                    }
                }
            }
            .padding(.horizontal, 7).padding(.bottom, 4)
        }
    }

    private var sectionLabel: some View {
        HStack {
            Text("RECITERS").font(.system(size: 9.5, weight: .bold)).tracking(1.4)
            Spacer()
            Text("\(results.count)").font(.system(size: 9.5, weight: .bold)).opacity(0.7)
        }
        .foregroundStyle(tokens.muted)
        .padding(.horizontal, 8).padding(.top, 6).padding(.bottom, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 20)).foregroundStyle(tokens.muted)
            Text(catalog.reciters.isEmpty ? "Loading reciters…" : "No reciters match")
                .font(.system(size: 11)).foregroundStyle(tokens.muted)
        }
        .frame(maxWidth: .infinity).padding(.top, 60)
    }

    /// Highlight the catalog row whose surah is currently streaming (matches the mockup's
    /// active first row). Keyed on the on-demand source id's reciter-id prefix, so it lights up
    /// for any moshaf/surah of that reciter.
    private func isPlayingReciter(_ r: Reciter) -> Bool {
        (engine.currentSourceID?.hasPrefix("ondemand:\(r.id):") ?? false) && engine.status == .playing
    }
}
