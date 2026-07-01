import SwiftUI
import QuraniKit

struct LiveTabView: View {
    @ObservedObject var sources: SourcesStore
    @ObservedObject var engine: PlaybackEngine
    let tokens: Tokens
    /// Plays a station via `AppModel.playStation` (which ends any active mix first) — not
    /// `engine.playStation` directly, so a live pick can't leave a stale mix session running.
    let play: (Station) -> Void
    /// The reciter list is ~170 stations and the world list is ~37; collapse each to the first
    /// `collapsedCount` by default with a Show-all / Show-fewer toggle so the tab isn't an endless scroll.
    @State private var stationsExpanded = false
    @State private var worldExpanded = false
    private let collapsedCount = 8

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                section("FEATURED · LIVE")
                ForEach(sources.featured) { st in
                    StationRow(station: st, tokens: tokens, isPlaying: isPlaying(st))
                        .onTapGesture { play(st) }
                }

                if !sources.world.isEmpty {
                    section("WORLD QURAN RADIO")
                    if worldExpanded {
                        // Grouped by region (first-appearance order) so 37 stations across ~20
                        // countries read as a browsable list rather than a flat wall.
                        ForEach(worldRegions, id: \.self) { region in
                            regionHeader(region)
                            ForEach(sources.world.filter { $0.region == region }) { st in
                                StationRow(station: st, tokens: tokens, isPlaying: isPlaying(st))
                                    .onTapGesture { play(st) }
                            }
                        }
                    } else {
                        ForEach(Array(sources.world.prefix(collapsedCount))) { st in
                            StationRow(station: st, tokens: tokens, isPlaying: isPlaying(st))
                                .onTapGesture { play(st) }
                        }
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
                    ForEach(stations) { st in
                        StationRow(station: st, tokens: tokens, isPlaying: isPlaying(st))
                            .onTapGesture { play(st) }
                    }
                    if sources.reciterStations.count > collapsedCount {
                        toggleRow(expanded: stationsExpanded, total: sources.reciterStations.count) { stationsExpanded.toggle() }
                    }
                }
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 300)
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
