import SwiftUI
import QuraniKit

/// One reciter in the Explore catalog: circular avatar, name, a moshaf-count subtitle,
/// and a ＋/✓ Mix-pool toggle. Observes `pool` directly so the toggle reflects and
/// republishes membership changes (AppModel does not forward child changes). Opening the
/// detail is the parent's job (`.onTapGesture`); the pool button consumes its own click.
struct ReciterRow: View {
    let reciter: Reciter
    @ObservedObject var pool: MixPoolStore
    let tokens: Tokens

    private var inPool: Bool { pool.contains(reciter.id) }

    private var subtitle: String {
        let n = reciter.moshafs.count
        return n == 1 ? "1 recitation" : "\(n) recitations"
    }

    var body: some View {
        HStack(spacing: 11) {
            Circle().fill(tokens.glassTint).frame(width: 42, height: 42)
                .overlay(Circle().stroke(Color.white.opacity(tokens.isDark ? 0.12 : 0.5), lineWidth: 1))
                .overlay(Image(systemName: "person.fill")
                    .font(.system(size: 18)).foregroundStyle(tokens.muted))
            VStack(alignment: .leading, spacing: 1) {
                Text(reciter.name).font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tokens.text).lineLimit(1)
                Text(subtitle).font(.system(size: 10.5)).foregroundStyle(tokens.muted).lineLimit(1)
            }
            Spacer(minLength: 8)
            Button { pool.toggle(reciter: reciter.id) } label: {
                Image(systemName: inPool ? "checkmark" : "plus")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(inPool ? tokens.accent : tokens.muted)
                    .frame(width: 26, height: 26)
                    .background(inPool ? tokens.accent.opacity(0.18) : tokens.glassTint,
                                in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .help(inPool ? "Remove from Mix pool" : "Add to Mix pool")
        }
        .padding(.vertical, 6).padding(.horizontal, 8)
        .contentShape(Rectangle())
    }
}

/// A pill toggle reused by the riwaya filter (Explore) and the moshaf picker (detail).
/// Accent-tinted when active, muted glass otherwise.
struct FilterChip: View {
    let text: String
    let on: Bool
    let tokens: Tokens
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text).font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(on ? tokens.accent : tokens.muted)
                .padding(.horizontal, 11).padding(.vertical, 5)
                .background(on ? tokens.accent.opacity(0.16) : tokens.glassTint, in: Capsule())
                .lineLimit(1).fixedSize()
        }
        .buttonStyle(.plain)
    }
}
