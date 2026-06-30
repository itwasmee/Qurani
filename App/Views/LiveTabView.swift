import SwiftUI
import QuraniKit

struct LiveTabView: View {
    @ObservedObject var sources: SourcesStore
    @ObservedObject var engine: PlaybackEngine
    let tokens: Tokens
    /// Plays a station via `AppModel.playStation` (which ends any active mix first) — not
    /// `engine.playStation` directly, so a live pick can't leave a stale mix session running.
    let play: (Station) -> Void
    /// The reciter list is ~170 stations; collapse to the first `collapsedCount` by default
    /// with a Show-all / Show-fewer toggle so the Live tab isn't an endless scroll.
    @State private var stationsExpanded = false
    private let collapsedCount = 8

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                section("FEATURED · LIVE")
                ForEach(sources.featured) { st in
                    StationRow(station: st, tokens: tokens, isPlaying: isPlaying(st))
                        .onTapGesture { play(st) }
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
                        expandToggleRow
                    }
                }
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 300)
    }

    /// Tappable footer row that flips between the collapsed first-`collapsedCount` view and
    /// the full reciter list.
    private var expandToggleRow: some View {
        HStack(spacing: 6) {
            Image(systemName: stationsExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 11, weight: .bold))
            Text(stationsExpanded ? "Show fewer" : "Show all (\(sources.reciterStations.count))")
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(tokens.accent)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9).padding(.horizontal, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) { stationsExpanded.toggle() }
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
}
