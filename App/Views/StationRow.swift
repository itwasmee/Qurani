import SwiftUI
import QuraniKit

struct StationRow: View {
    let station: Station
    let tokens: Tokens
    let isPlaying: Bool
    var isFavorite: Bool = false
    /// When set, a star button appears trailing; tapping it toggles the favorite without
    /// triggering the row's play tap (a `Button` swallows its own tap).
    var onToggleFavorite: (() -> Void)? = nil

    private var isFeatured: Bool { station.reciter == nil }   // curated live feeds have no reciter
    private var iconName: String {
        if !isFeatured { return "person.fill" }
        return station.hasVideo ? "video.fill" : "dot.radiowaves.left.and.right"
    }

    var body: some View {
        HStack(spacing: 11) {
            RoundedRectangle(cornerRadius: 11).fill(tokens.glassTint).frame(width: 42, height: 42)
                .overlay(RoundedRectangle(cornerRadius: 11)
                    .stroke(Color.white.opacity(tokens.isDark ? 0.12 : 0.5), lineWidth: 1))
                .overlay(Image(systemName: iconName)
                    .font(.system(size: 17))
                    .foregroundStyle(isFeatured ? tokens.gold : tokens.muted))
            VStack(alignment: .leading, spacing: 1) {
                Text(station.name).font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tokens.text).lineLimit(1)
                HStack(spacing: 5) {
                    if isFeatured {
                        HStack(spacing: 3) {
                            Circle().fill(.red).frame(width: 5, height: 5)
                            Text("LIVE").font(.system(size: 9, weight: .heavy)).foregroundStyle(.red)
                        }
                    }
                    Text(station.region).font(.system(size: 10.5)).foregroundStyle(tokens.muted).lineLimit(1)
                }
            }
            Spacer()
            if isPlaying { EqualizerDots(color: tokens.accent) }
            if let onToggleFavorite {
                Button(action: onToggleFavorite) {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isFavorite ? tokens.gold : tokens.muted.opacity(0.55))
                }
                .buttonStyle(.plain)
                .help(isFavorite ? "Remove from favorites" : "Add to favorites")
            }
        }
        .padding(.vertical, 6).padding(.horizontal, 8)
        .background(isPlaying ? tokens.accent.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(tokens.accent.opacity(isPlaying ? 0.22 : 0), lineWidth: 1))
        .contentShape(Rectangle())
    }
}
