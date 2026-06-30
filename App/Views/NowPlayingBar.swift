import SwiftUI
import QuraniKit

struct NowPlayingBar: View {
    @ObservedObject var engine: PlaybackEngine
    let tokens: Tokens
    /// A random-Mix session is active → swap the ⤮ MIX source chip in for the LIVE / 📚 LIBRARY tag
    /// and show the "up next" hint. Passed from `GlassPanel` (which owns the `AppModel`).
    var isMixing: Bool = false
    /// The reciter + surah of the item that plays after the current mix item, already resolved to
    /// display names by `GlassPanel`. Nil at the tail of the queue (or when not mixing).
    var upNext: (memberName: String, surahName: String)? = nil
    /// Tap on the art + title/reciter region → jump the panel to wherever the current audio plays
    /// from (Mix / Explore-reciter / Live / Library). Only this leading region fires it; the play/pause
    /// button and the scrubber stay independently interactive. Defaults to a no-op so other call sites
    /// (and the snapshot renderer) compile unchanged.
    var onTapSource: () -> Void = {}
    /// Fraction (0…1) under the finger while scrubbing, so the thumb tracks the drag
    /// immediately instead of waiting for the engine's next reported position. `nil` when
    /// not dragging — the track then follows `nowPlaying.elapsed/duration`.
    @State private var dragFraction: Double?

    private var isFailed: Bool { if case .failed = engine.status { return true } else { return false } }
    /// A library-imported local file is loaded — drives the gold 📚 LIBRARY source chip (mirrors how
    /// live shows the red LIVE pill; on-demand has no chip). Keyed on the source-id prefix.
    private var isLocal: Bool { engine.currentSourceID?.hasPrefix("local:") ?? false }

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
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                // Art + title/reciter region is a single tap target that jumps to the source. Wrapping
                // it in a Button (with a subtle press style) keeps it independent of the sibling
                // play/pause Button and the scrubber below — tapping here never toggles playback.
                Button(action: onTapSource) {
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
                                } else if isMixing {
                                    // The mockup's ⤮ MIX chip; the ⤮ glyph isn't in SF Pro, so the native
                                    // `shuffle` SF Symbol stands in (same shuffle/mix concept, matches the
                                    // build view's "Shuffle"). Live keeps precedence so a stale flag can't
                                    // mask a live station's LIVE pill.
                                    HStack(spacing: 3) {
                                        Image(systemName: "shuffle").font(.system(size: 7.5, weight: .heavy))
                                        Text("MIX").font(.system(size: 8, weight: .heavy))
                                    }
                                    .foregroundStyle(tokens.accent)
                                    .padding(.horizontal, 5).padding(.vertical, 2)
                                    .background(tokens.accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 5))
                                } else if isLocal {
                                    Text("📚 LIBRARY").font(.system(size: 8, weight: .heavy)).foregroundStyle(tokens.gold)
                                        .padding(.horizontal, 5).padding(.vertical, 2)
                                        .background(tokens.gold.opacity(0.16), in: RoundedRectangle(cornerRadius: 5))
                                }
                                Text(np.subtitle).font(.system(size: 10)).foregroundStyle(tokens.muted).lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(NowPlayingSourceButtonStyle())
                .help("Go to what's playing")
                Button { engine.toggle() } label: {
                    Image(systemName: engine.status == .playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(tokens.bg)
                        .frame(width: 32, height: 32)
                        .background(tokens.text, in: Circle())
                }
                .buttonStyle(.plain)
            }
            if isMixing, !np.isLive, let upNext { upNextLine(upNext) }
            // On-demand items have a finite length → offer a draggable scrubber. Live keeps
            // only the red LIVE pill (set above) and shows no progress control.
            if !np.isLive, np.duration > 0 { scrubber(np) }
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

    /// The "up next · random" hint shown under the title during a mix: the reciter + surah of the
    /// item the session advances to when the current one finishes.
    @ViewBuilder private func upNextLine(_ next: (memberName: String, surahName: String)) -> some View {
        HStack(spacing: 6) {
            Text("Up next · random").font(.system(size: 9, weight: .semibold)).foregroundStyle(tokens.accent)
            Text("\(next.memberName) — \(next.surahName)")
                .font(.system(size: 9.5)).foregroundStyle(tokens.muted).lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    /// Thin, draggable progress track for on-demand playback. Dragging seeks the engine
    /// live; `h:mm:ss` labels flank the track (elapsed on the left, total on the right).
    @ViewBuilder private func scrubber(_ np: NowPlaying) -> some View {
        let played = np.duration > 0 ? min(max(np.elapsed / np.duration, 0), 1) : 0
        let fraction = dragFraction ?? played
        HStack(spacing: 7) {
            Text(TimeFormat.label(dragFraction.map { $0 * np.duration } ?? np.elapsed))
                .font(.system(size: 9, weight: .medium).monospacedDigit())
                .foregroundStyle(tokens.muted).fixedSize()
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(tokens.text.opacity(0.15)).frame(height: 3)
                    Capsule().fill(tokens.accent).frame(width: max(0, w * fraction), height: 3)
                    Circle().fill(tokens.text).frame(width: 9, height: 9)
                        .overlay(Circle().stroke(tokens.bg.opacity(0.25), lineWidth: 0.5))
                        .offset(x: min(max(w * fraction - 4.5, 0), w - 9))
                }
                .frame(height: 12)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            let f = min(max(v.location.x / max(w, 1), 0), 1)
                            dragFraction = f
                            engine.seek(toFraction: f)
                        }
                        .onEnded { _ in dragFraction = nil }
                )
            }
            .frame(height: 12)
            Text(TimeFormat.label(np.duration))
                .font(.system(size: 9, weight: .medium).monospacedDigit())
                .foregroundStyle(tokens.muted).fixedSize()
        }
    }
}

/// Subtle press affordance for the tappable now-playing source region: dims briefly while pressed
/// without altering the bar's layout (no scale/inset). Kept separate from the play/pause button's
/// `.plain` style so only the art + title region gets the dip.
private struct NowPlayingSourceButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.55 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
