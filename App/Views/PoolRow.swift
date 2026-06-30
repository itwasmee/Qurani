import SwiftUI
import QuraniKit

/// One selectable reciter in the Mix-pool builder: a filled-when-selected checkbox, a circular
/// avatar, the reciter name, and a source badge (📚 LOCAL / ☁︎ ON-DEMAND). The whole row is the
/// hit target — tapping toggles membership via `onTap` (the parent owns the selection set, so this
/// row stays stateless and reusable for both local and on-demand candidates).
struct PoolRow: View {
    let name: String
    let source: PoolSource
    let selected: Bool
    let tokens: Tokens
    let onTap: () -> Void

    /// Dark glyph on the light-accent themes (Noor/Layl), white on the dark-accent one (Sahar) —
    /// keyed off `isDark` since the two dark themes carry the light-tinted accents.
    private var onAccent: Color { tokens.isDark ? Color(hex: 0x05291f) : .white }

    var body: some View {
        HStack(spacing: 10) {
            checkbox
            Circle().fill(tokens.glassTint).frame(width: 30, height: 30)
                .overlay(Circle().stroke(Color.white.opacity(tokens.isDark ? 0.12 : 0.5), lineWidth: 1))
                .overlay(Image(systemName: "person.fill")
                    .font(.system(size: 14)).foregroundStyle(tokens.muted))
            Text(name).font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(tokens.text).lineLimit(1)
            Spacer(minLength: 6)
            badge
        }
        .padding(.vertical, 7).padding(.horizontal, 8)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    private var checkbox: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(selected ? tokens.accent : Color.clear)
            .frame(width: 20, height: 20)
            .overlay(RoundedRectangle(cornerRadius: 6)
                .stroke(selected ? tokens.accent : tokens.muted.opacity(0.6), lineWidth: 1.6))
            .overlay(Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(onAccent)
                .opacity(selected ? 1 : 0))
    }

    private var badge: some View {
        let isLocal = source == .local
        let text = isLocal ? "📚 LOCAL" : "☁︎ ON-DEMAND"
        let fg = isLocal ? tokens.gold : (tokens.isDark ? Color(hex: 0x9fd0f0) : Color(hex: 0x2c6e96))
        let bg = isLocal ? tokens.gold.opacity(0.16) : Color(hex: 0x78c8ff, opacity: tokens.isDark ? 0.16 : 0.20)
        return Text(text)
            .font(.system(size: 8.5, weight: .heavy)).tracking(0.3)
            .foregroundStyle(fg)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(bg, in: RoundedRectangle(cornerRadius: 5))
            .fixedSize()
    }
}
