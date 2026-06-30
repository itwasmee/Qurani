import SwiftUI
import QuraniKit

struct LiveTabView: View {
    @ObservedObject var sources: SourcesStore
    @ObservedObject var engine: PlaybackEngine
    let tokens: Tokens

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                section("FEATURED · LIVE")
                ForEach(sources.featured) { st in
                    StationRow(station: st, tokens: tokens, isPlaying: engine.nowPlaying?.title == st.name)
                        .onTapGesture { engine.play(st) }
                }
                if !sources.reciterStations.isEmpty {
                    section("RECITER STATIONS · 24/7")
                    ForEach(sources.reciterStations.prefix(40)) { st in
                        StationRow(station: st, tokens: tokens, isPlaying: engine.nowPlaying?.title == st.name)
                            .onTapGesture { engine.play(st) }
                    }
                }
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 300)
    }

    @ViewBuilder private func section(_ t: String) -> some View {
        Text(t).font(.system(size: 9.5, weight: .bold)).tracking(1.4)
            .foregroundStyle(tokens.muted)
            .padding(.horizontal, 8).padding(.top, 8).padding(.bottom, 4)
    }
}
