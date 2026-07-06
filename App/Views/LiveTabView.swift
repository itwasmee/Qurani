import SwiftUI
import QuraniKit

struct LiveTabView: View {
    @ObservedObject var sources: SourcesStore
    @ObservedObject var engine: PlaybackEngine
    @ObservedObject var stationFavorites: StationFavoritesStore
    @ObservedObject var recents: RecentsStore
    let tokens: Tokens
    /// Plays a station via `AppModel.playStation` (which ends any active mix first) — not
    /// `engine.playStation` directly, so a live pick can't leave a stale mix session running.
    let play: (Station) -> Void
    /// Replay a history entry (`AppModel.playRecent`).
    let playRecent: (RecentItem) -> Void
    /// The reciter list is ~170 stations and the world list is ~36; collapse each to the first
    /// `collapsedCount` by default with a Show-all / Show-fewer toggle so the tab isn't an endless scroll.
    @State private var stationsExpanded = false
    @State private var worldExpanded = false
    @State private var query = ""
    private let collapsedCount = 8

    var body: some View {
        VStack(spacing: 0) {
            searchField
            if query.isEmpty, !recentStations.isEmpty { recentsStrip }
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if query.isEmpty { sectionedList } else { searchResults }
                }
                .padding(.horizontal, 8)
            }
        }
        .frame(height: 300)
    }

    /// Normal browse view: Favorites → Featured → World → Reciter, each with its own collapse.
    @ViewBuilder private var sectionedList: some View {
        let favs = favoriteStations
        if !favs.isEmpty {
            section("★ FAVORITES")
            ForEach(favs) { st in stationRow(st) }
        }

        section("FEATURED · LIVE")
        ForEach(sources.featured) { st in stationRow(st) }

        if !sources.world.isEmpty {
            section("WORLD QURAN RADIO")
            if worldExpanded {
                ForEach(worldRegions, id: \.self) { region in
                    regionHeader(region)
                    ForEach(sources.world.filter { $0.region == region }) { st in stationRow(st) }
                }
            } else {
                ForEach(Array(sources.world.prefix(collapsedCount))) { st in stationRow(st) }
            }
            if sources.world.count > collapsedCount {
                toggleRow(expanded: worldExpanded, total: sources.world.count) { worldExpanded.toggle() }
            }
        }

        if !sources.reciterStations.isEmpty {
            section("RECITER STATIONS · 24/7")
            let stations = stationsExpanded
                ? sources.reciterStations
                : Array(sources.reciterStations.prefix(collapsedCount))
            ForEach(stations) { st in stationRow(st) }
            if sources.reciterStations.count > collapsedCount {
                toggleRow(expanded: stationsExpanded, total: sources.reciterStations.count) { stationsExpanded.toggle() }
            }
        }
    }

    /// Flat filtered view across every source (name or region), shown while the search box is non-empty.
    @ViewBuilder private var searchResults: some View {
        let q = query.lowercased()
        let results = (sources.featured + sources.world + sources.reciterStations)
            .filter { $0.name.lowercased().contains(q) || $0.region.lowercased().contains(q) }
        if results.isEmpty {
            Text("No stations match “\(query)”")
                .font(.system(size: 12)).foregroundStyle(tokens.muted)
                .frame(maxWidth: .infinity, alignment: .center).padding(.top, 24)
        } else {
            section("RESULTS · \(results.count)")
            ForEach(results) { st in stationRow(st) }
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .semibold)).foregroundStyle(tokens.muted)
            TextField("Search stations & countries", text: $query)
                .textFieldStyle(.plain).font(.system(size: 12)).foregroundStyle(tokens.text)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 12)).foregroundStyle(tokens.muted)
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(tokens.glassTint, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(tokens.text.opacity(0.08), lineWidth: 1))
        .padding(.horizontal, 8).padding(.top, 8).padding(.bottom, 4)
    }

    /// The recently-played history narrowed to live stations — surahs played on demand (or from the
    /// library / a mix) belong to their own tabs, so this radio tab only resurfaces stations.
    private var recentStations: [RecentItem] { recents.items.filter { $0.kind == .live } }

    /// Horizontal strip of the last few played stations for one-tap replay.
    private var recentsStrip: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("RECENT STATIONS").font(.system(size: 9.5, weight: .bold)).tracking(1.4)
                .foregroundStyle(tokens.muted).padding(.horizontal, 8).padding(.top, 4)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(recentStations.prefix(8)) { item in
                        Button { playRecent(item) } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "dot.radiowaves.left.and.right").font(.system(size: 10, weight: .semibold))
                                Text(item.title).font(.system(size: 11, weight: .medium)).lineLimit(1)
                            }
                            .foregroundStyle(tokens.text)
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .background(tokens.glassTint, in: Capsule())
                            .overlay(Capsule().stroke(tokens.text.opacity(0.08), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .help("Replay \(item.title) — \(item.subtitle)")
                    }
                }
                .padding(.horizontal, 8)
            }
        }
        .padding(.bottom, 4)
    }

    /// A station row with a favorite star + play-on-tap. Used by every section.
    @ViewBuilder private func stationRow(_ st: Station) -> some View {
        StationRow(station: st, tokens: tokens, isPlaying: isPlaying(st),
                   isFavorite: stationFavorites.contains(st.id),
                   onToggleFavorite: { stationFavorites.toggle(station: st.id) })
            .onTapGesture { play(st) }
    }

    /// Favorited stations resolved across every source, kept in FEATURED → WORLD → RECITER order.
    private var favoriteStations: [Station] {
        (sources.featured + sources.world + sources.reciterStations)
            .filter { stationFavorites.contains($0.id) }
    }

    /// Unique world regions in first-appearance order (the JSON is authored grouped by country).
    private var worldRegions: [String] {
        var seen = Set<String>(); var out: [String] = []
        for s in sources.world where !seen.contains(s.region) { seen.insert(s.region); out.append(s.region) }
        return out
    }

    /// Tappable footer row that flips between the collapsed first-`collapsedCount` view and the
    /// full list. Shared by the World and Reciter sections.
    private func toggleRow(expanded: Bool, total: Int, toggle: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 11, weight: .bold))
            Text(expanded ? "Show fewer" : "Show all (\(total))")
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(tokens.accent)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9).padding(.horizontal, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) { toggle() }
        }
    }

    /// Highlight by station *identity*, and only while actually playing — never
    /// during `.loading`/`.failed`, and never colliding on duplicate display names.
    private func isPlaying(_ st: Station) -> Bool {
        engine.currentSourceID == "live:\(st.id)" && engine.status == .playing
    }

    @ViewBuilder private func section(_ t: String) -> some View {
        Text(t).font(.system(size: 9.5, weight: .bold)).tracking(1.4)
            .foregroundStyle(tokens.muted)
            .padding(.horizontal, 8).padding(.top, 8).padding(.bottom, 4)
    }

    /// A lighter per-country subheader inside the expanded World section.
    @ViewBuilder private func regionHeader(_ t: String) -> some View {
        Text(t).font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(tokens.text.opacity(0.7))
            .padding(.horizontal, 8).padding(.top, 6).padding(.bottom, 1)
    }
}
