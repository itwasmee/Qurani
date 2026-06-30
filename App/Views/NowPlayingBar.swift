import SwiftUI
import QuraniKit

struct NowPlayingBar: View {
    @ObservedObject var engine: PlaybackEngine
    let tokens: Tokens

    private var isFailed: Bool { if case .failed = engine.status { return true } else { return false } }

    var body: some View {
        if isFailed, let np = engine.nowPlaying {
            failureBar(np)
        } else if let np = engine.nowPlaying {
            playingBar(np)
        }
    }

    /// Brief, tappable recovery affordance — tapping re-plays the current station.
    @ViewBuilder private func failureBar(_ np: NowPlaying) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 9).fill(tokens.glassTint).frame(width: 34, height: 34)
                .overlay(Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 15)).foregroundStyle(.orange))
            VStack(alignment: .leading, spacing: 1) {
                Text(np.title).font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tokens.text).lineLimit(1)
                Text("Couldn't play — tap to retry")
                    .font(.system(size: 10)).foregroundStyle(.orange).lineLimit(1)
            }
            Spacer()
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(tokens.bg)
                .frame(width: 32, height: 32)
                .background(tokens.accent, in: Circle())
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background {
            ZStack {
                VisualEffectBackground(material: .popover, blending: .behindWindow, isDark: tokens.isDark)
                tokens.glassTint
                tokens.bg.opacity(tokens.isDark ? 0.22 : 0.10)
            }
        }
        .overlay(alignment: .top) { Rectangle().fill(tokens.text.opacity(0.10)).frame(height: 1) }
        .contentShape(Rectangle())
        .onTapGesture { engine.retry() }
    }

    @ViewBuilder private func playingBar(_ np: NowPlaying) -> some View {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 9).fill(tokens.glassTint).frame(width: 34, height: 34)
                    .overlay(RoundedRectangle(cornerRadius: 9)
                        .stroke(Color.white.opacity(tokens.isDark ? 0.12 : 0.5), lineWidth: 1))
                    .overlay(Image(systemName: "waveform").font(.system(size: 16)).foregroundStyle(tokens.accent))
                VStack(alignment: .leading, spacing: 1) {
                    Text(np.surahHint ?? np.title)
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(tokens.text).lineLimit(1)
                    HStack(spacing: 5) {
                        if np.isLive {
                            Text("LIVE").font(.system(size: 8, weight: .heavy)).foregroundStyle(.white)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(.red, in: RoundedRectangle(cornerRadius: 5))
                        }
                        Text(np.subtitle).font(.system(size: 10)).foregroundStyle(tokens.muted).lineLimit(1)
                    }
                }
                Spacer()
                Button { engine.toggle() } label: {
                    Image(systemName: engine.status == .playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(tokens.bg)
                        .frame(width: 32, height: 32)
                        .background(tokens.text, in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background {
                ZStack {
                    VisualEffectBackground(material: .popover, blending: .behindWindow, isDark: tokens.isDark)
                    tokens.glassTint
                    tokens.bg.opacity(tokens.isDark ? 0.22 : 0.10)   // deepen the footer band
                }
            }
            .overlay(alignment: .top) { Rectangle().fill(tokens.text.opacity(0.10)).frame(height: 1) }
    }
}
